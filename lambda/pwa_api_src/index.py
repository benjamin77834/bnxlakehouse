import json
import boto3
import os
from datetime import datetime, timedelta

s3 = boto3.client('s3')
lambda_client = boto3.client('lambda')
cw = boto3.client('cloudwatch', region_name='us-east-1')
ct = boto3.client('cloudtrail', region_name='us-east-1')

CACHE_BUCKET = os.environ.get('CACHE_BUCKET', '')
CACHE_KEY = 'cache/costs-daily.json'
CALCULATOR_FN = os.environ.get('CALCULATOR_FN', '')


def get_cached_data():
    """Cache deshabilitado para sandbox - siempre recalcula."""
    return None


def save_cache(data):
    """Guarda en S3."""
    if not CACHE_BUCKET:
        return
    try:
        data['cache_date'] = datetime.utcnow().strftime('%Y-%m-%d')
        s3.put_object(Bucket=CACHE_BUCKET, Key=CACHE_KEY, Body=json.dumps(data), ContentType='application/json')
    except Exception as e:
        print(f"Cache error: {e}")


def fetch_costs_from_calculator():
    """Invoca la Lambda cost-calculator para obtener costos reales."""
    if not CALCULATOR_FN:
        return None
    try:
        resp = lambda_client.invoke(FunctionName=CALCULATOR_FN, InvocationType='RequestResponse')
        payload = json.loads(resp['Payload'].read().decode())
        body = json.loads(payload['body'])
        return body
    except Exception as e:
        print(f"Calculator error: {e}")
        return None


def fetch_users():
    """Actividad por usuario con costo estimado."""
    COST_MAP = {
        'StartQueryExecution': 0.05, 'InvokeModel': 0.01, 'InvokeEndpoint': 0.005,
        'StartJobRun': 0.50, 'StartCrawler': 0.10, 'PutObject': 0.000005,
        'GetObject': 0.0000004, 'RunInstances': 0.10, 'InvokeFunction': 0.0000002,
    }
    users_list = []
    try:
        today = datetime.utcnow().date()
        yesterday = today - timedelta(days=1)
        resp = ct.lookup_events(
            StartTime=datetime(yesterday.year, yesterday.month, yesterday.day),
            EndTime=datetime(today.year, today.month, today.day),
            MaxResults=50
        )
        activity = {}
        for ev in resp.get('Events', []):
            user = ev.get('Username', 'unknown')
            event_name = ev.get('EventName', '')
            event_source = ev.get('EventSource', '').replace('.amazonaws.com', '')
            if user not in activity:
                activity[user] = {'user': user, 'actions': 0, 'services': set(), 'events': [], 'est_cost': 0.0}
            activity[user]['actions'] += 1
            activity[user]['services'].add(event_source)
            if len(activity[user]['events']) < 5:
                activity[user]['events'].append(event_name)
            activity[user]['est_cost'] += COST_MAP.get(event_name, 0.001)

        for u in sorted(activity.values(), key=lambda x: x['est_cost'], reverse=True):
            users_list.append({
                'user': u['user'], 'actions': u['actions'],
                'services': list(u['services'])[:5], 'top_events': u['events'][:5],
                'est_cost': round(u['est_cost'], 4)
            })
    except Exception as e:
        print(f"CloudTrail error: {e}")
    return users_list


def handler(event, context):
    """
    PWA API - usa cost calculator (escaneo de recursos) con cache diario.
    Costo: $0/mes (no usa Cost Explorer API).
    Pasar ?refresh=1 o {"refresh":true} para forzar recalculo.
    """
    # Check force refresh
    force = False
    if isinstance(event, dict):
        qs = event.get('queryStringParameters') or {}
        body_str = event.get('body', '{}') or '{}'
        try:
            body_json = json.loads(body_str)
            force = body_json.get('refresh', False)
        except Exception:
            pass
        force = force or qs.get('refresh') == '1'

    # Cache primero (a menos que sea force)
    if not force:
        cached = get_cached_data()
        if cached:
            cached['alarms'] = fetch_alarms()
            cached['users'] = fetch_users()
            cached['updated'] = datetime.utcnow().isoformat()
            return ok(cached)

    # Calcular costos via Lambda calculator
    calc = fetch_costs_from_calculator()

    if calc:
        data = {
            'total': calc['total'],
            'budget': float(os.environ.get('BUDGET_TOTAL', '5000')),
            'daily': calc['daily_avg'],
            'projected': calc['projected_month'],
            'services': calc['services_summary'],
            'details': calc.get('details', [])[:20],
            'method': calc['method'],
            'from_cache': False
        }
    else:
        data = {
            'total': 0, 'budget': 5000, 'daily': 0, 'projected': 0,
            'services': [], 'details': [], 'method': 'error', 'from_cache': False
        }

    data['alarms'] = fetch_alarms()
    data['users'] = fetch_users()
    data['updated'] = datetime.utcnow().isoformat()

    save_cache(data)
    return ok(data)


def fetch_alarms():
    alarms = []
    try:
        resp = cw.describe_alarms(StateValue='ALARM')
        for a in resp.get('MetricAlarms', []):
            alarms.append({'name': a['AlarmName'], 'status': 'critical', 'detail': a.get('AlarmDescription', '')})
    except Exception:
        pass
    return alarms


def ok(data):
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(data)
    }

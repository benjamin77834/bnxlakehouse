import json
import boto3
import os
from datetime import datetime, timedelta

sts = boto3.client('sts')

CROSS_ACCOUNT_ROLE = os.environ.get(
    'CROSS_ACCOUNT_ROLE',
    'arn:aws:iam::522189038734:role/datalake-cost-reader'
)


def get_ce_client():
    """Intenta asumir rol cross-account. Si falla, usa credenciales locales."""
    # Primero intenta cross-account
    try:
        resp = sts.assume_role(
            RoleArn=CROSS_ACCOUNT_ROLE,
            RoleSessionName='datalake-pwa-api'
        )
        creds = resp['Credentials']
        session = boto3.Session(
            aws_access_key_id=creds['AccessKeyId'],
            aws_secret_access_key=creds['SecretAccessKey'],
            aws_session_token=creds['SessionToken']
        )
        ce = session.client('ce', region_name='us-east-1')
        # Verificar que puede leer datos
        today = datetime.utcnow().date()
        first = today.replace(day=1)
        test = ce.get_cost_and_usage(
            TimePeriod={'Start': first.isoformat(), 'End': today.isoformat()},
            Granularity='MONTHLY',
            Metrics=['UnblendedCost']
        )
        amount = float(test['ResultsByTime'][0]['Total']['UnblendedCost']['Amount'])
        if amount > 0:
            return ce, 'cross-account'
        else:
            print("Cross-account returned $0, falling back to local")
            return boto3.client('ce', region_name='us-east-1'), 'local'
    except Exception as e:
        print(f"Cross-account failed ({e}), using local")
        return boto3.client('ce', region_name='us-east-1'), 'local'


def handler(event, context):
    """
    API backend para PWA de costos.
    Intenta cross-account primero, fallback a cuenta local.
    """
    ce, source = get_ce_client()

    today = datetime.utcnow().date()
    first_of_month = today.replace(day=1)
    yesterday = today - timedelta(days=1)
    budget_total = float(os.environ.get('BUDGET_TOTAL', '5000'))

    try:
        # Gasto acumulado del mes
        month_cost = ce.get_cost_and_usage(
            TimePeriod={
                'Start': first_of_month.isoformat(),
                'End': today.isoformat()
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost']
        )
        month_amount = float(
            month_cost['ResultsByTime'][0]['Total']['UnblendedCost']['Amount']
        )

        # Gasto de ayer
        daily_cost = ce.get_cost_and_usage(
            TimePeriod={
                'Start': yesterday.isoformat(),
                'End': today.isoformat()
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost']
        )
        daily_amount = float(
            daily_cost['ResultsByTime'][0]['Total']['UnblendedCost']['Amount']
        )

        # Proyeccion
        days_elapsed = (today - first_of_month).days or 1
        projected = (month_amount / days_elapsed) * 30

        # Desglose por servicio
        service_cost = ce.get_cost_and_usage(
            TimePeriod={
                'Start': first_of_month.isoformat(),
                'End': today.isoformat()
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
        )

        services = []
        for group in service_cost['ResultsByTime'][0]['Groups']:
            svc_name = group['Keys'][0]
            svc_amount = float(group['Metrics']['UnblendedCost']['Amount'])
            if svc_amount > 0.01:
                services.append({'name': svc_name, 'amount': round(svc_amount, 2)})
        services.sort(key=lambda x: x['amount'], reverse=True)

    except Exception as e:
        print(f"Cost Explorer error: {e}")
        month_amount = 0
        daily_amount = 0
        projected = 0
        services = []

    # Alarmas
    alarms = []
    try:
        cw = boto3.client('cloudwatch', region_name='us-east-1')
        alarms_resp = cw.describe_alarms(StateValue='ALARM')
        for a in alarms_resp.get('MetricAlarms', []):
            alarms.append({
                'name': a['AlarmName'],
                'status': 'critical',
                'detail': a.get('AlarmDescription', '')
            })
    except Exception as e:
        print(f"CloudWatch error: {e}")

    # Actividad por usuario
    users_list = []
    try:
        ct = boto3.client('cloudtrail', region_name='us-east-1')
        events_resp = ct.lookup_events(
            StartTime=datetime(yesterday.year, yesterday.month, yesterday.day),
            EndTime=datetime(today.year, today.month, today.day),
            MaxResults=50
        )
        users_activity = {}
        for event in events_resp.get('Events', []):
            username = event.get('Username', 'unknown')
            event_source = event.get('EventSource', '')
            event_name = event.get('EventName', '')
            if username not in users_activity:
                users_activity[username] = {
                    'user': username, 'actions': 0,
                    'services': set(), 'events': []
                }
            users_activity[username]['actions'] += 1
            users_activity[username]['services'].add(
                event_source.replace('.amazonaws.com', '')
            )
            if len(users_activity[username]['events']) < 5:
                users_activity[username]['events'].append(event_name)

        for ud in sorted(users_activity.values(), key=lambda x: x['actions'], reverse=True):
            users_list.append({
                'user': ud['user'],
                'actions': ud['actions'],
                'services': list(ud['services'])[:5],
                'top_events': ud['events'][:5]
            })
    except Exception as e:
        print(f"CloudTrail error: {e}")

    response = {
        'total': round(month_amount, 2),
        'budget': budget_total,
        'daily': round(daily_amount, 2),
        'projected': round(projected, 2),
        'services': services[:15],
        'alarms': alarms[:10],
        'users': users_list[:10],
        'source': source,
        'updated': datetime.utcnow().isoformat()
    }

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response)
    }

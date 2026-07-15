import json
import boto3
import os
from datetime import datetime, timedelta

sts = boto3.client('sts')

CROSS_ACCOUNT_ROLE = os.environ.get(
    'CROSS_ACCOUNT_ROLE',
    'arn:aws:iam::522189038734:role/datalake-cost-reader'
)


def get_cross_account_session():
    """Asume rol en la management account para leer costos."""
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
        return session
    except Exception as e:
        print(f"Error asumiendo rol cross-account: {e}")
        return boto3.Session()


def handler(event, context):
    """
    API backend para la PWA de costos.
    Asume rol en management account para ver costos reales de la org.
    """
    session = get_cross_account_session()
    ce = session.client('ce', region_name='us-east-1')
    cw = session.client('cloudwatch', region_name='us-east-1')
    ct = session.client('cloudtrail', region_name='us-east-1')

    today = datetime.utcnow().date()
    first_of_month = today.replace(day=1)
    yesterday = today - timedelta(days=1)
    budget_total = float(os.environ.get('BUDGET_TOTAL', '5000'))

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

    # Actividad por usuario (CloudTrail)
    users_activity = {}
    try:
        events_resp = ct.lookup_events(
            StartTime=datetime(yesterday.year, yesterday.month, yesterday.day),
            EndTime=datetime(today.year, today.month, today.day),
            MaxResults=50
        )
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
    except Exception as e:
        print(f"CloudTrail error: {e}")

    users_list = []
    for ud in sorted(users_activity.values(), key=lambda x: x['actions'], reverse=True):
        users_list.append({
            'user': ud['user'],
            'actions': ud['actions'],
            'services': list(ud['services'])[:5],
            'top_events': ud['events'][:5]
        })

    # Alarmas
    alarms = []
    try:
        alarms_resp = cw.describe_alarms(StateValue='ALARM')
        for a in alarms_resp.get('MetricAlarms', []):
            alarms.append({
                'name': a['AlarmName'],
                'status': 'critical',
                'detail': a.get('AlarmDescription', ''),
                'action': None
            })
    except Exception as e:
        print(f"CloudWatch error: {e}")

    response = {
        'total': round(month_amount, 2),
        'budget': budget_total,
        'daily': round(daily_amount, 2),
        'projected': round(projected, 2),
        'services': services[:15],
        'alarms': alarms[:10],
        'users': users_list[:10],
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

import json
import boto3
import os
from datetime import datetime, timedelta

ce = boto3.client('ce')
cw = boto3.client('cloudwatch')
ct = boto3.client('cloudtrail')


def handler(event, context):
    """
    API backend para la PWA de costos.
    Incluye desglose por usuario/rol IAM (quién generó el costo).
    """
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

    # =========================================================================
    # DESGLOSE POR USUARIO/ROL - Quién generó acciones que cuestan
    # Usa CloudTrail para ver quién hizo qué en las últimas 24h
    # =========================================================================
    users_activity = {}
    try:
        # Buscar eventos de las últimas 24h que generan costo
        cost_events = [
            'RunInstances', 'StartQueryExecution', 'InvokeModel',
            'InvokeEndpoint', 'PutObject', 'StartCrawler', 'StartJobRun',
            'CreateEndpoint', 'UpdateWorkgroup'
        ]
        
        events_resp = ct.lookup_events(
            StartTime=datetime(yesterday.year, yesterday.month, yesterday.day),
            EndTime=datetime(today.year, today.month, today.day),
            MaxResults=50
        )

        for event in events_resp.get('Events', []):
            username = event.get('Username', 'unknown')
            event_name = event.get('EventName', '')
            event_source = event.get('EventSource', '')
            
            if username not in users_activity:
                users_activity[username] = {
                    'user': username,
                    'actions': 0,
                    'services': set(),
                    'events': []
                }
            
            users_activity[username]['actions'] += 1
            users_activity[username]['services'].add(
                event_source.replace('.amazonaws.com', '')
            )
            if len(users_activity[username]['events']) < 5:
                users_activity[username]['events'].append(event_name)

    except Exception as e:
        users_activity = {'error': {'user': 'Error consultando CloudTrail', 'actions': 0, 'services': set(), 'events': [str(e)]}}

    # Formatear usuarios para JSON
    users_list = []
    for user_data in sorted(users_activity.values(), key=lambda x: x['actions'], reverse=True):
        users_list.append({
            'user': user_data['user'],
            'actions': user_data['actions'],
            'services': list(user_data['services'])[:5],
            'top_events': user_data['events'][:5]
        })

    # Alarmas activas de CloudWatch
    alarms_resp = cw.describe_alarms(StateValue='ALARM')
    alarms = []
    for a in alarms_resp.get('MetricAlarms', []):
        alarms.append({
            'name': a['AlarmName'],
            'status': 'critical',
            'detail': a.get('AlarmDescription', ''),
            'action': None
        })

    ok_alarms = cw.describe_alarms(StateValue='OK')
    for a in ok_alarms.get('MetricAlarms', [])[:10]:
        if 'cost' in a['AlarmName'].lower() or 'budget' in a['AlarmName'].lower():
            alarms.append({
                'name': a['AlarmName'],
                'status': 'ok',
                'detail': a.get('AlarmDescription', ''),
                'action': None
            })

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

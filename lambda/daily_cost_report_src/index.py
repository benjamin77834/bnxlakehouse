import json
import boto3
import os
from datetime import datetime, timedelta

ce = boto3.client('ce')
sns = boto3.client('sns')


def handler(event, context):
    """
    Genera reporte diario de costos y lo envia por email via SNS.
    Incluye: gasto de ayer, acumulado del mes, proyeccion, y desglose por servicio.
    """
    project = os.environ['PROJECT_NAME']
    env = os.environ['ENVIRONMENT']
    sns_arn = os.environ['SNS_TOPIC_ARN']
    budget_total = float(os.environ.get('BUDGET_TOTAL', '5000'))

    today = datetime.utcnow().date()
    yesterday = today - timedelta(days=1)
    first_of_month = today.replace(day=1)

    # Costo de ayer
    yesterday_cost = ce.get_cost_and_usage(
        TimePeriod={
            'Start': yesterday.isoformat(),
            'End': today.isoformat()
        },
        Granularity='DAILY',
        Metrics=['UnblendedCost']
    )
    daily_amount = float(
        yesterday_cost['ResultsByTime'][0]['Total']['UnblendedCost']['Amount']
    )

    # Acumulado del mes
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

    # Proyeccion a fin de mes
    days_elapsed = (today - first_of_month).days or 1
    days_in_month = 30
    projected = (month_amount / days_elapsed) * days_in_month
    budget_pct = (month_amount / budget_total) * 100

    # Desglose por servicio (top 10)
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
            services.append((svc_name, svc_amount))
    services.sort(key=lambda x: x[1], reverse=True)

    # Construir email
    separator = '=' * 60
    line_sep = '-' * 60
    lines = [
        separator,
        f"  REPORTE DIARIO DE COSTOS - {project.upper()} ({env})",
        f"  Fecha: {yesterday.isoformat()}",
        separator,
        "",
        f"  Gasto de ayer:        ${daily_amount:.2f}",
        f"  Acumulado del mes:    ${month_amount:.2f}",
        f"  Proyeccion fin mes:   ${projected:.2f}",
        f"  Budget mensual:       ${budget_total:.2f}",
        f"  % Budget usado:       {budget_pct:.1f}%",
        "",
        line_sep,
        "  DESGLOSE POR SERVICIO (acumulado mes)",
        line_sep,
    ]

    for svc_name, svc_amount in services[:10]:
        bar_len = int((svc_amount / max(month_amount, 1)) * 20)
        bar = '#' * bar_len
        lines.append(f"  ${svc_amount:>8.2f}  {bar:<20}  {svc_name}")

    lines.extend([
        "",
        line_sep,
        "  ALERTAS",
        line_sep,
    ])

    if budget_pct > 80:
        lines.append(f"  ATENCION: Gasto al {budget_pct:.0f}% del budget!")
    if projected > budget_total:
        lines.append(f"  CRITICO: Proyeccion ${projected:.0f} SUPERA budget ${budget_total:.0f}")
    if budget_pct <= 80:
        lines.append("  OK: Gasto dentro de parametros normales")

    lines.extend([
        "",
        separator,
        f"  Reporte automatico - Data Lake {project}",
        separator,
    ])

    message = '\n'.join(lines)

    subject = (
        f"[{project}] Costos {yesterday.isoformat()}: "
        f"${daily_amount:.2f} | Mes: ${month_amount:.2f} ({budget_pct:.0f}%)"
    )

    sns.publish(
        TopicArn=sns_arn,
        Subject=subject,
        Message=message
    )

    return {
        'statusCode': 200,
        'daily': daily_amount,
        'month': month_amount,
        'projected': projected,
        'budget_pct': budget_pct
    }

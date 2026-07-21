import json
import boto3
from datetime import datetime, timedelta

# Precios us-east-1 (USD/hora a menos que se indique)
PRICES = {
    # EC2
    'ec2': {
        't3.micro': 0.0104, 't3.small': 0.0208, 't3.medium': 0.0416,
        't3.large': 0.0832, 't3.xlarge': 0.1664,
        'm5.large': 0.096, 'm5.xlarge': 0.192, 'm5.2xlarge': 0.384,
        'm5.4xlarge': 0.768, 'm6i.large': 0.096, 'm6i.xlarge': 0.192,
        'r5.large': 0.126, 'r5.xlarge': 0.252, 'r5.2xlarge': 0.504,
        'c5.large': 0.085, 'c5.xlarge': 0.17, 'c5.2xlarge': 0.34,
        'p3.2xlarge': 3.06, 'g4dn.xlarge': 0.526,
    },
    # Neptune (por hora)
    'neptune': {
        'db.t3.medium': 0.076, 'db.r5.large': 0.348, 'db.r5.xlarge': 0.696,
        'db.r5.2xlarge': 1.392, 'db.serverless': 0.1065,  # per NCU
    },
    # Redshift Serverless (per RPU-hora)
    'redshift_rpu': 0.375,
    # OpenSearch Serverless (per OCU-hora)
    'opensearch_ocu': 0.24,
    # SageMaker Endpoints
    'sagemaker': {
        'ml.t3.medium': 0.05, 'ml.m5.large': 0.134, 'ml.m5.xlarge': 0.269,
        'ml.c5.large': 0.119, 'ml.p3.2xlarge': 4.284, 'ml.g4dn.xlarge': 0.736,
    },
    # NAT Gateway (per hora + per GB)
    'nat_gateway_hr': 0.045,
    'nat_gateway_gb': 0.045,
    # ELB/ALB
    'alb_hr': 0.0225,
    # RDS
    'rds': {
        'db.t3.micro': 0.017, 'db.t3.small': 0.034, 'db.t3.medium': 0.068,
        'db.m5.large': 0.171, 'db.r5.large': 0.24,
    },
    # MSK (per broker-hora)
    'msk': {
        'kafka.t3.small': 0.096, 'kafka.m5.large': 0.21, 'kafka.m5.xlarge': 0.42,
    },
    # ElastiCache
    'elasticache': {
        'cache.t3.micro': 0.017, 'cache.t3.small': 0.034, 'cache.m5.large': 0.156,
    },
    # EKS cluster
    'eks_cluster_hr': 0.10,
    # S3 (per GB-mes)
    's3_gb_month': 0.023,
    # CloudWatch (per dashboard-mes)
    'cw_dashboard': 3.0,
}


def handler(event, context):
    """
    Calcula costos reales escaneando todos los recursos activos.
    No usa Cost Explorer - calcula directo por tipo × precio × horas.
    """
    region = 'us-east-1'
    now = datetime.utcnow()
    first_of_month = now.replace(day=1, hour=0, minute=0, second=0)
    hours_this_month = (now - first_of_month).total_seconds() / 3600

    costs = []
    total = 0

    # --- EC2 Instances ---
    try:
        ec2 = boto3.client('ec2', region_name=region)
        resp = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        for res in resp.get('Reservations', []):
            for inst in res.get('Instances', []):
                itype = inst['InstanceType']
                launch = inst['LaunchTime'].replace(tzinfo=None)
                hours = min((now - launch).total_seconds() / 3600, hours_this_month)
                price_hr = PRICES['ec2'].get(itype, 0.10)
                cost = price_hr * hours
                name = next((t['Value'] for t in inst.get('Tags', []) if t['Key'] == 'Name'), inst['InstanceId'])
                costs.append({'service': 'EC2', 'resource': name, 'type': itype, 'hours': round(hours, 1), 'cost': round(cost, 2)})
                total += cost
    except Exception as e:
        costs.append({'service': 'EC2', 'resource': 'error', 'type': str(e), 'hours': 0, 'cost': 0})

    # --- Neptune ---
    try:
        neptune = boto3.client('neptune', region_name=region)
        clusters = neptune.describe_db_clusters().get('DBClusters', [])
        for cl in clusters:
            instances = neptune.describe_db_instances(
                Filters=[{'Name': 'db-cluster-id', 'Values': [cl['DBClusterIdentifier']]}]
            ).get('DBInstances', [])
            for inst in instances:
                iclass = inst['DBInstanceClass']
                price_hr = PRICES['neptune'].get(iclass, 0.10)
                cost = price_hr * hours_this_month
                costs.append({'service': 'Neptune', 'resource': inst['DBInstanceIdentifier'], 'type': iclass, 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
                total += cost
    except Exception as e:
        costs.append({'service': 'Neptune', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- Redshift Serverless ---
    try:
        rs = boto3.client('redshift-serverless', region_name=region)
        wgs = rs.list_workgroups().get('workgroups', [])
        for wg in wgs:
            capacity = wg.get('baseCapacity', 0)
            # Redshift Serverless solo cobra cuando procesa queries
            # Basado en datos reales: ~1.3 horas activas por día
            days_elapsed = (now - first_of_month).days or 1
            active_hours = days_elapsed * 1.3
            cost = capacity * PRICES['redshift_rpu'] * active_hours
            costs.append({'service': 'Redshift', 'resource': wg['workgroupName'], 'type': f'{capacity} RPU (~2hr/dia)', 'hours': round(active_hours, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'Redshift', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- OpenSearch Serverless ---
    try:
        oss = boto3.client('opensearchserverless', region_name=region)
        colls = oss.list_collections().get('collectionSummaries', [])
        for c in colls:
            # Min 2 OCU (indexing) + 2 OCU (search) = 4 OCU always on
            cost = 4 * PRICES['opensearch_ocu'] * hours_this_month
            costs.append({'service': 'OpenSearch', 'resource': c['name'], 'type': '4 OCU min', 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'OpenSearch', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- SageMaker Endpoints ---
    try:
        sm = boto3.client('sagemaker', region_name=region)
        endpoints = sm.list_endpoints(StatusEquals='InService').get('Endpoints', [])
        for ep in endpoints:
            desc = sm.describe_endpoint(EndpointName=ep['EndpointName'])
            for variant in desc.get('ProductionVariants', []):
                itype = variant.get('CurrentInstanceType', 'ml.m5.large')
                count = variant.get('CurrentInstanceCount', 1)
                price_hr = PRICES['sagemaker'].get(itype, 0.134)
                cost = price_hr * count * hours_this_month
                costs.append({'service': 'SageMaker', 'resource': ep['EndpointName'], 'type': f'{count}x {itype}', 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
                total += cost
    except Exception as e:
        costs.append({'service': 'SageMaker', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- NAT Gateways ---
    try:
        ec2 = boto3.client('ec2', region_name=region)
        nats = ec2.describe_nat_gateways(Filter=[{'Name': 'state', 'Values': ['available']}]).get('NatGateways', [])
        for nat in nats:
            create_time = nat['CreateTime'].replace(tzinfo=None)
            hours = min((now - create_time).total_seconds() / 3600, hours_this_month)
            cost = PRICES['nat_gateway_hr'] * hours
            costs.append({'service': 'NAT Gateway', 'resource': nat['NatGatewayId'], 'type': 'NAT GW', 'hours': round(hours, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'NAT Gateway', 'resource': 'error', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- ALB/ELB ---
    try:
        elb = boto3.client('elbv2', region_name=region)
        lbs = elb.describe_load_balancers().get('LoadBalancers', [])
        for lb in lbs:
            create_time = lb['CreatedTime'].replace(tzinfo=None)
            hours = min((now - create_time).total_seconds() / 3600, hours_this_month)
            cost = PRICES['alb_hr'] * hours
            costs.append({'service': 'Load Balancer', 'resource': lb['LoadBalancerName'], 'type': lb['Type'], 'hours': round(hours, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'Load Balancer', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- RDS ---
    try:
        rds = boto3.client('rds', region_name=region)
        dbs = rds.describe_db_instances().get('DBInstances', [])
        for db in dbs:
            if db['DBInstanceStatus'] == 'available':
                iclass = db['DBInstanceClass']
                price_hr = PRICES['rds'].get(iclass, 0.10)
                cost = price_hr * hours_this_month
                costs.append({'service': 'RDS', 'resource': db['DBInstanceIdentifier'], 'type': iclass, 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
                total += cost
    except Exception as e:
        costs.append({'service': 'RDS', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- MSK Kafka ---
    try:
        msk = boto3.client('kafka', region_name=region)
        clusters = msk.list_clusters().get('ClusterInfoList', [])
        for cl in clusters:
            broker_type = cl.get('BrokerNodeGroupInfo', {}).get('InstanceType', 'kafka.m5.large')
            broker_count = cl.get('NumberOfBrokerNodes', 3)
            price_hr = PRICES['msk'].get(broker_type, 0.21)
            cost = price_hr * broker_count * hours_this_month
            costs.append({'service': 'MSK Kafka', 'resource': cl['ClusterName'], 'type': f'{broker_count}x {broker_type}', 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'MSK', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- EKS ---
    try:
        eks = boto3.client('eks', region_name=region)
        clusters = eks.list_clusters().get('clusters', [])
        for name in clusters:
            cost = PRICES['eks_cluster_hr'] * hours_this_month
            costs.append({'service': 'EKS', 'resource': name, 'type': 'cluster', 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'EKS', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- ElastiCache ---
    try:
        ec = boto3.client('elasticache', region_name=region)
        clusters = ec.describe_cache_clusters().get('CacheClusters', [])
        for cl in clusters:
            ntype = cl['CacheNodeType']
            nodes = cl.get('NumCacheNodes', 1)
            price_hr = PRICES['elasticache'].get(ntype, 0.05)
            cost = price_hr * nodes * hours_this_month
            costs.append({'service': 'ElastiCache', 'resource': cl['CacheClusterId'], 'type': f'{nodes}x {ntype}', 'hours': round(hours_this_month, 1), 'cost': round(cost, 2)})
            total += cost
    except Exception as e:
        costs.append({'service': 'ElastiCache', 'resource': 'error/none', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- S3 (estimado por número de buckets × tamaño promedio) ---
    try:
        s3 = boto3.client('s3', region_name=region)
        buckets = s3.list_buckets().get('Buckets', [])
        # No podemos saber tamaño sin CloudWatch, estimamos 10GB por bucket
        s3_cost = len(buckets) * 10 * PRICES['s3_gb_month'] * (hours_this_month / 730)
        costs.append({'service': 'S3', 'resource': f'{len(buckets)} buckets', 'type': '~10GB/bucket est', 'hours': round(hours_this_month, 1), 'cost': round(s3_cost, 2)})
        total += s3_cost
    except Exception as e:
        costs.append({'service': 'S3', 'resource': 'error', 'type': str(e)[:50], 'hours': 0, 'cost': 0})

    # --- CloudWatch Dashboards ---
    try:
        cw = boto3.client('cloudwatch', region_name=region)
        dashboards = cw.list_dashboards().get('DashboardEntries', [])
        cw_cost = len(dashboards) * PRICES['cw_dashboard'] * (hours_this_month / 730)
        if dashboards:
            costs.append({'service': 'CloudWatch', 'resource': f'{len(dashboards)} dashboards', 'type': '$3/dashboard/mes', 'hours': round(hours_this_month, 1), 'cost': round(cw_cost, 2)})
            total += cw_cost
    except Exception:
        pass

    # --- Resumen ---
    # Agrupar por servicio
    by_service = {}
    for c in costs:
        svc = c['service']
        if svc not in by_service:
            by_service[svc] = 0
        by_service[svc] += c['cost']

    services_summary = [{'name': k, 'amount': round(v, 2)} for k, v in sorted(by_service.items(), key=lambda x: x[1], reverse=True) if v > 0]

    # Proyección a fin de mes
    days_elapsed = (now - first_of_month).days or 1
    daily_avg = total / days_elapsed
    projected_month = daily_avg * 30

    # Publicar métricas en CloudWatch
    try:
        cw = boto3.client('cloudwatch', region_name=region)
        metric_data = [
            {'MetricName': 'TotalCostEstimated', 'Value': round(total, 2), 'Unit': 'None'},
            {'MetricName': 'DailyAvgCost', 'Value': round(daily_avg, 2), 'Unit': 'None'},
            {'MetricName': 'ProjectedMonthlyCost', 'Value': round(projected_month, 2), 'Unit': 'None'},
        ]
        # Por servicio
        for svc_name, svc_cost in by_service.items():
            if svc_cost > 0:
                metric_data.append({
                    'MetricName': 'ServiceCost',
                    'Value': round(svc_cost, 2),
                    'Unit': 'None',
                    'Dimensions': [{'Name': 'ServiceName', 'Value': svc_name}]
                })

        # Por usuario (CloudTrail - quién hizo qué)
        try:
            ct = boto3.client('cloudtrail', region_name=region)
            yesterday = now - timedelta(days=1)
            events = ct.lookup_events(
                StartTime=datetime(yesterday.year, yesterday.month, yesterday.day),
                EndTime=datetime(now.year, now.month, now.day),
                MaxResults=50
            ).get('Events', [])

            user_actions = {}
            for ev in events:
                user = ev.get('Username', 'unknown')
                if user not in user_actions:
                    user_actions[user] = 0
                user_actions[user] += 1

            for user, actions in user_actions.items():
                metric_data.append({
                    'MetricName': 'UserActions',
                    'Value': actions,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'UserName', 'Value': user}]
                })
        except Exception as e:
            print(f"CloudTrail user metrics error: {e}")

        # Publicar en batches de 20 (límite AWS)
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cw.put_metric_data(
                Namespace='DataLake/Costs',
                MetricData=batch
            )
    except Exception as e:
        print(f"CloudWatch publish error: {e}")

    result = {
        'total': round(total, 2),
        'daily_avg': round(daily_avg, 2),
        'projected_month': round(projected_month, 2),
        'days_elapsed': days_elapsed,
        'hours_this_month': round(hours_this_month, 1),
        'resources_scanned': len(costs),
        'services_summary': services_summary,
        'details': costs,
        'calculated_at': now.isoformat(),
        'method': 'resource-scan (no Cost Explorer)'
    }

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(result)
    }

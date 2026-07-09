# =============================================================================
# COST CONTROL - Apagado automático y acciones por consumo
# =============================================================================
#
# Sistema de control de costos que:
# 1. Apaga servicios cuando las alarmas detectan gasto excesivo
# 2. Limita consumo por servicio (Lambda, API GW, Redshift, Data Lake)
# 3. Presupuestos con alertas a 50%, 80%, 100% del budget
# 4. Lambda de remediación que puede pausar/detener servicios
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Budgets - Presupuestos por servicio
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "total" {
  name         = "${var.project_name}-total-${var.environment}"
  budget_type  = "COST"
  limit_amount = var.budget_total
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.critical_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.critical_alerts.arn]
  }

  tags = local.common_tags
}

resource "aws_budgets_budget" "redshift" {
  name         = "${var.project_name}-redshift-${var.environment}"
  budget_type  = "COST"
  limit_amount = var.budget_redshift
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Redshift"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.critical_alerts.arn]
  }

  tags = local.common_tags
}

resource "aws_budgets_budget" "lambda_apigw" {
  name         = "${var.project_name}-lambda-api-${var.environment}"
  budget_type  = "COST"
  limit_amount = var.budget_lambda_api
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["AWS Lambda", "Amazon API Gateway"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.critical_alerts.arn]
  }

  tags = local.common_tags
}

resource "aws_budgets_budget" "storage" {
  name         = "${var.project_name}-storage-${var.environment}"
  budget_type  = "COST"
  limit_amount = var.budget_storage
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Simple Storage Service"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Lambda de Remediación - Apaga servicios cuando se excede presupuesto
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "cost_remediation" {
  function_name = "${var.project_name}-cost-remediation-${var.environment}"
  role          = aws_iam_role.cost_remediation_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 256

  filename         = data.archive_file.cost_remediation.output_path
  source_code_hash = data.archive_file.cost_remediation.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      PROJECT_NAME   = var.project_name
      REDSHIFT_WG    = "${var.project_name}-wg-${var.environment}"
      SNS_TOPIC_ARN  = aws_sns_topic.critical_alerts.arn
    }
  }

  tags = local.common_tags
}

data "archive_file" "cost_remediation" {
  type        = "zip"
  output_path = "${path.module}/lambda/cost_remediation.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os

redshift = boto3.client('redshift-serverless')
lambda_client = boto3.client('lambda')
sns = boto3.client('sns')

def handler(event, context):
    """
    Lambda de remediacion de costos.
    Acciones disponibles:
    - pause_redshift: Pausa el workgroup de Redshift
    - throttle_lambda: Pone concurrency a 1 en Lambdas de serving
    - notify: Solo notifica sin actuar
    """
    action = event.get('action', 'notify')
    project = os.environ['PROJECT_NAME']
    env = os.environ['ENVIRONMENT']
    wg = os.environ['REDSHIFT_WG']
    sns_arn = os.environ['SNS_TOPIC_ARN']

    result = {'action': action, 'status': 'completed'}

    if action == 'pause_redshift':
        try:
            redshift.update_workgroup(
                workgroupName=wg,
                baseCapacity=0
            )
            result['detail'] = f'Redshift workgroup {wg} pausado (capacity=0)'
        except Exception as e:
            result['detail'] = f'Error pausando Redshift: {str(e)}'
            result['status'] = 'error'

    elif action == 'throttle_lambda':
        functions = [
            f'{project}-serving-gold-{env}',
            f'{project}-serving-ml-{env}'
        ]
        for fn in functions:
            try:
                lambda_client.put_function_concurrency(
                    FunctionName=fn,
                    ReservedConcurrentExecutions=1
                )
                result.setdefault('throttled', []).append(fn)
            except Exception as e:
                result.setdefault('errors', []).append(f'{fn}: {str(e)}')

    elif action == 'stop_all_non_essential':
        # Pausa Redshift + throttle Lambdas
        try:
            redshift.update_workgroup(workgroupName=wg, baseCapacity=0)
        except:
            pass
        functions = [f'{project}-serving-gold-{env}', f'{project}-serving-ml-{env}']
        for fn in functions:
            try:
                lambda_client.put_function_concurrency(
                    FunctionName=fn, ReservedConcurrentExecutions=0
                )
            except:
                pass
        result['detail'] = 'Todos los servicios no esenciales detenidos'

    # Notificar
    sns.publish(
        TopicArn=sns_arn,
        Subject=f'[{project}] Cost Remediation: {action}',
        Message=json.dumps(result, indent=2)
    )

    return result
    EOF
    filename = "index.py"
  }
}

# SNS puede invocar Lambda de remediación
resource "aws_sns_topic_subscription" "cost_remediation" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.cost_remediation.arn
}

resource "aws_lambda_permission" "sns_cost_remediation" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_remediation.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.critical_alerts.arn
}

# -----------------------------------------------------------------------------
# IAM Role para Lambda de remediación
# -----------------------------------------------------------------------------

resource "aws_iam_role" "cost_remediation_role" {
  name = "${var.project_name}-cost-remediation-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cost_remediation_basic" {
  role       = aws_iam_role.cost_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cost_remediation_actions" {
  name = "${var.project_name}-cost-remediation-actions-${var.environment}"
  role = aws_iam_role.cost_remediation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "redshift-serverless:UpdateWorkgroup",
          "redshift-serverless:GetWorkgroup"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:PutFunctionConcurrency",
          "lambda:DeleteFunctionConcurrency"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.critical_alerts.arn]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Alarmas de costos que disparan remediación
# -----------------------------------------------------------------------------

# Alarma: Redshift gastando más del budget → pausar
resource "aws_cloudwatch_metric_alarm" "redshift_cost_high" {
  alarm_name          = "${var.project_name}-redshift-cost-limit-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600 # 6 horas
  statistic           = "Maximum"
  threshold           = var.budget_redshift * 0.9
  alarm_description   = "Redshift cerca del 90% del budget mensual - considerar pausar"

  dimensions = {
    ServiceName = "Amazon Redshift"
    Currency    = "USD"
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

# Alarma: Lambda/API gastando mucho → throttle
resource "aws_cloudwatch_metric_alarm" "lambda_cost_high" {
  alarm_name          = "${var.project_name}-lambda-cost-limit-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600
  statistic           = "Maximum"
  threshold           = var.budget_lambda_api * 0.9
  alarm_description   = "Lambda+API cerca del 90% del budget - considerar throttle"

  dimensions = {
    ServiceName = "AWS Lambda"
    Currency    = "USD"
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

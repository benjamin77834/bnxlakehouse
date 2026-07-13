# -----------------------------------------------------------------------------
# Capa de Salida / Serving - APIs, SageMaker Endpoints, Lambda de consumo
# -----------------------------------------------------------------------------

# API Gateway REST para exponer datos del data lake
resource "aws_api_gateway_rest_api" "data_lake_api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API de salida del Data Lake - expone Gold y modelos ML"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# Lambda de salida: sirve datos Gold via API
resource "aws_lambda_function" "serving_gold" {
  function_name = "${var.project_name}-serving-gold-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.serving_gold.output_path
  source_code_hash = data.archive_file.serving_gold.output_base64sha256

  environment {
    variables = {
      GOLD_BUCKET = aws_s3_bucket.data_lake_gold.bucket
      ENVIRONMENT = var.environment
    }
  }

  tags = local.common_tags
}

data "archive_file" "serving_gold" {
  type        = "zip"
  output_path = "${path.module}/lambda/serving_gold.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os

s3 = boto3.client('s3')
athena = boto3.client('athena')

def handler(event, context):
    """
    Lambda de salida: consulta datos Gold y los expone via API Gateway.
    Soporta queries predefinidas sobre el layer Gold (Augmented).
    """
    gold_bucket = os.environ['GOLD_BUCKET']
    
    # Ejemplo: listar datasets disponibles en Gold
    response = s3.list_objects_v2(
        Bucket=gold_bucket,
        Delimiter='/',
        MaxKeys=100
    )
    
    datasets = [p['Prefix'].rstrip('/') for p in response.get('CommonPrefixes', [])]
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'datasets': datasets, 'bucket': gold_bucket})
    }
    EOF
    filename = "index.py"
  }
}

# Lambda de salida: proxy a SageMaker endpoints
resource "aws_lambda_function" "serving_ml" {
  function_name = "${var.project_name}-serving-ml-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.serving_ml.output_path
  source_code_hash = data.archive_file.serving_ml.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = local.common_tags
}

data "archive_file" "serving_ml" {
  type        = "zip"
  output_path = "${path.module}/lambda/serving_ml.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os

sagemaker_runtime = boto3.client('sagemaker-runtime')

def handler(event, context):
    """
    Lambda de salida: invoca SageMaker endpoint para inferencia real-time.
    Recibe payload del API Gateway y lo envia al modelo.
    """
    body = json.loads(event.get('body', '{}'))
    endpoint_name = body.get('endpoint', '')
    payload = body.get('data', {})
    
    if not endpoint_name:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'endpoint is required'})
        }
    
    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=endpoint_name,
        ContentType='application/json',
        Body=json.dumps(payload)
    )
    
    result = json.loads(response['Body'].read().decode())
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'prediction': result})
    }
    EOF
    filename = "index.py"
  }
}

# SageMaker Domain (Unified) - Studio para Data Scientists
resource "aws_sagemaker_domain" "data_lake" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  domain_name = "${var.project_name}-studio-${var.environment}"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_role.arn

    sharing_settings {
      notebook_output_option = "Allowed"
      s3_output_path         = "s3://${aws_s3_bucket.sagemaker_artifacts.bucket}/studio-output/"
    }
  }

  tags = local.common_tags
}

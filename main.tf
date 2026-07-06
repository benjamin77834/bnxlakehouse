terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# S3 - Data Lake Storage (Medallion Architecture)
# Landing → Bronze (Raw) → Silver (Curated) → Gold (Augmented)
# -----------------------------------------------------------------------------

# Landing Zone: Punto de aterrizaje para datos batch/offline.
# Desde aquí Lambda valida y mueve a Bronze.
resource "aws_s3_bucket" "data_lake_landing" {
  bucket = "${var.project_name}-landing-${var.environment}"
  tags   = local.common_tags
}

# Bronze (Raw): Datos crudos tal cual llegan, sin transformación.
resource "aws_s3_bucket" "data_lake_bronze" {
  bucket = "${var.project_name}-bronze-${var.environment}"
  tags   = local.common_tags
}

# Silver (Curated): Datos limpios, deduplicados, tipados, con calidad.
resource "aws_s3_bucket" "data_lake_silver" {
  bucket = "${var.project_name}-silver-${var.environment}"
  tags   = local.common_tags
}

# Gold (Augmented): Datos enriquecidos, agregados, listos para consumo.
resource "aws_s3_bucket" "data_lake_gold" {
  bucket = "${var.project_name}-gold-${var.environment}"
  tags   = local.common_tags
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project_name}-athena-results-${var.environment}"
  tags   = local.common_tags
}

# Versionado para Bronze (datos crudos, importante mantener historial)
resource "aws_s3_bucket_versioning" "bronze_versioning" {
  bucket = aws_s3_bucket.data_lake_bronze.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación server-side para todos los buckets
resource "aws_s3_bucket_server_side_encryption_configuration" "bronze_encryption" {
  bucket = aws_s3_bucket.data_lake_bronze.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "silver_encryption" {
  bucket = aws_s3_bucket.data_lake_silver.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gold_encryption" {
  bucket = aws_s3_bucket.data_lake_gold.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquear acceso público en todos los buckets
resource "aws_s3_bucket_public_access_block" "bronze_public_access" {
  bucket                  = aws_s3_bucket.data_lake_bronze.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "silver_public_access" {
  bucket                  = aws_s3_bucket.data_lake_silver.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "gold_public_access" {
  bucket                  = aws_s3_bucket.data_lake_gold.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Landing zone: encriptación + bloqueo público + versionado + lifecycle
resource "aws_s3_bucket_server_side_encryption_configuration" "landing_encryption" {
  bucket = aws_s3_bucket.data_lake_landing.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "landing_public_access" {
  bucket                  = aws_s3_bucket.data_lake_landing.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "landing_versioning" {
  bucket = aws_s3_bucket.data_lake_landing.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle: mover archivos del landing a Glacier después de 30 días
resource "aws_s3_bucket_lifecycle_configuration" "landing_lifecycle" {
  bucket = aws_s3_bucket.data_lake_landing.id

  rule {
    id     = "move-to-glacier-after-30-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Notificación S3: cuando llega un archivo al landing, se dispara Lambda
resource "aws_s3_bucket_notification" "landing_notification" {
  bucket = aws_s3_bucket.data_lake_landing.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.landing_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_landing]
}

# Lambda que procesa archivos del landing zone → Bronze
resource "aws_lambda_function" "landing_processor" {
  function_name = "${var.project_name}-landing-processor-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.landing_processor.output_path
  source_code_hash = data.archive_file.landing_processor.output_base64sha256

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.data_lake_bronze.bucket
      ENVIRONMENT   = var.environment
      GLUE_CRAWLER  = aws_glue_crawler.bronze_crawler.name
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_s3_landing" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.landing_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake_landing.arn
}

data "archive_file" "landing_processor" {
  type        = "zip"
  output_path = "${path.module}/lambda/landing_processor.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os
import urllib.parse

s3 = boto3.client('s3')
glue = boto3.client('glue')

def handler(event, context):
    """
    Procesa archivos que llegan al bucket Landing.
    1. Valida el archivo
    2. Lo copia al bucket Bronze (Raw) con prefijo de fecha
    3. Dispara el Glue Crawler para actualizar el catálogo
    """
    bronze_bucket = os.environ['BRONZE_BUCKET']
    crawler_name = os.environ.get('GLUE_CRAWLER', '')

    for record in event.get('Records', []):
        source_bucket = record['s3']['bucket']['name']
        source_key = urllib.parse.unquote_plus(record['s3']['object']['key'])

        from datetime import datetime
        date_prefix = datetime.utcnow().strftime('%Y/%m/%d')
        dest_key = f"{date_prefix}/{source_key}"

        print(f"Landing -> Bronze: s3://{source_bucket}/{source_key} -> s3://{bronze_bucket}/{dest_key}")

        s3.copy_object(
            Bucket=bronze_bucket,
            Key=dest_key,
            CopySource={'Bucket': source_bucket, 'Key': source_key}
        )

    if crawler_name and event.get('Records'):
        try:
            glue.start_crawler(Name=crawler_name)
            print(f"Crawler {crawler_name} iniciado")
        except glue.exceptions.CrawlerRunningException:
            print(f"Crawler {crawler_name} ya está corriendo")

    return {'statusCode': 200, 'body': json.dumps('OK')}
    EOF
    filename = "index.py"
  }
}

# -----------------------------------------------------------------------------
# Glue - Catálogo de datos y Crawlers
# -----------------------------------------------------------------------------

resource "aws_glue_catalog_database" "data_lake" {
  name        = "${var.project_name}_${var.environment}"
  description = "Glue Data Catalog - Medallion Architecture (Bronze/Silver/Gold)"
}

resource "aws_glue_crawler" "bronze_crawler" {
  database_name = aws_glue_catalog_database.data_lake.name
  name          = "${var.project_name}-bronze-crawler-${var.environment}"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake_bronze.bucket}/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = local.common_tags
}

resource "aws_glue_crawler" "silver_crawler" {
  database_name = aws_glue_catalog_database.data_lake.name
  name          = "${var.project_name}-silver-crawler-${var.environment}"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake_silver.bucket}/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Athena - Workgroup
# -----------------------------------------------------------------------------

resource "aws_athena_workgroup" "data_lake" {
  name = "${var.project_name}-${var.environment}"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Redshift Serverless
# -----------------------------------------------------------------------------

resource "aws_redshiftserverless_namespace" "data_lake" {
  namespace_name      = "${var.project_name}-${var.environment}"
  db_name             = var.redshift_db_name
  admin_username      = var.redshift_admin_username
  admin_user_password = var.redshift_admin_password

  iam_roles = [aws_iam_role.redshift_role.arn]

  tags = local.common_tags
}

resource "aws_redshiftserverless_workgroup" "data_lake" {
  namespace_name = aws_redshiftserverless_namespace.data_lake.namespace_name
  workgroup_name = "${var.project_name}-wg-${var.environment}"
  base_capacity  = var.redshift_base_capacity

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  tags = local.common_tags
}

resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-redshift-sg-${var.environment}"
  description = "Security group para Redshift Serverless"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = var.redshift_allowed_cidrs
    description = "Acceso Redshift desde CIDRs permitidos"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Salida a internet"
  }

  tags = local.common_tags
}

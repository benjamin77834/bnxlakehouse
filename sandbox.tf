# -----------------------------------------------------------------------------
# SANDBOX - Ambiente de pruebas aislado (opcional)
# -----------------------------------------------------------------------------
# Habilitar con: enable_sandbox = true en terraform.tfvars
# Crea un ambiente reducido para experimentación sin afectar producción.
# Incluye: S3 buckets propios, Glue DB, Athena workgroup, Redshift mini.
# Todo con prefijo "sandbox-" para identificar fácilmente.
# Para destruir solo el sandbox: usar terraform destroy -target=module...
# o simplemente poner enable_sandbox = false y re-aplicar.
# -----------------------------------------------------------------------------

# S3 Buckets del Sandbox (Bronze, Silver, Gold reducidos)
resource "aws_s3_bucket" "sandbox_bronze" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = "${var.project_name}-sandbox-bronze-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_s3_bucket" "sandbox_silver" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = "${var.project_name}-sandbox-silver-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_s3_bucket" "sandbox_gold" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = "${var.project_name}-sandbox-gold-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

# Encriptación para buckets sandbox
resource "aws_s3_bucket_server_side_encryption_configuration" "sandbox_bronze_enc" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = aws_s3_bucket.sandbox_bronze[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sandbox_silver_enc" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = aws_s3_bucket.sandbox_silver[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sandbox_gold_enc" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = aws_s3_bucket.sandbox_gold[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueo público
resource "aws_s3_bucket_public_access_block" "sandbox_bronze_block" {
  count                   = var.enable_sandbox ? 1 : 0
  bucket                  = aws_s3_bucket.sandbox_bronze[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "sandbox_silver_block" {
  count                   = var.enable_sandbox ? 1 : 0
  bucket                  = aws_s3_bucket.sandbox_silver[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "sandbox_gold_block" {
  count                   = var.enable_sandbox ? 1 : 0
  bucket                  = aws_s3_bucket.sandbox_gold[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: expirar datos del sandbox a los 90 días automáticamente
resource "aws_s3_bucket_lifecycle_configuration" "sandbox_bronze_lifecycle" {
  count  = var.enable_sandbox ? 1 : 0
  bucket = aws_s3_bucket.sandbox_bronze[0].id

  rule {
    id     = "expire-sandbox-data"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 90 }
  }
}

# Glue Catalog Database del Sandbox (aislada de producción)
resource "aws_glue_catalog_database" "sandbox" {
  count       = var.enable_sandbox ? 1 : 0
  name        = "${var.project_name}_sandbox_${var.environment}"
  description = "Sandbox - Base de datos de pruebas aislada"
}

# Glue Crawler del Sandbox
resource "aws_glue_crawler" "sandbox_crawler" {
  count         = var.enable_sandbox ? 1 : 0
  database_name = aws_glue_catalog_database.sandbox[0].name
  name          = "${var.project_name}-sandbox-crawler-${var.environment}"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.sandbox_bronze[0].bucket}/"
  }

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# Athena Workgroup del Sandbox (límite de datos escaneados)
resource "aws_athena_workgroup" "sandbox" {
  count = var.enable_sandbox ? 1 : 0
  name  = "${var.project_name}-sandbox-${var.environment}"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/sandbox-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Límite de 100 MB por query para controlar costos en sandbox
    bytes_scanned_cutoff_per_query = var.sandbox_athena_scan_limit
  }

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# Redshift Serverless del Sandbox (capacidad mínima)
resource "aws_redshiftserverless_namespace" "sandbox" {
  count              = var.enable_sandbox ? 1 : 0
  namespace_name     = "${var.project_name}-sandbox-${var.environment}"
  db_name            = "sandbox"
  admin_username     = var.redshift_admin_username
  admin_user_password = var.redshift_admin_password

  iam_roles = [aws_iam_role.redshift_role.arn]

  tags = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_redshiftserverless_workgroup" "sandbox" {
  count          = var.enable_sandbox ? 1 : 0
  namespace_name = aws_redshiftserverless_namespace.sandbox[0].namespace_name
  workgroup_name = "${var.project_name}-sandbox-wg-${var.environment}"
  base_capacity  = 4 # Mínimo posible para ahorrar

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# SageMaker Notebook para Sandbox (instancia pequeña)
resource "aws_sagemaker_notebook_instance" "sandbox" {
  count                = var.enable_sandbox ? 1 : 0
  name                 = "${var.project_name}-sandbox-nb-${var.environment}"
  role_arn             = aws_iam_role.sagemaker_role.arn
  instance_type        = "ml.t3.medium"
  volume_size          = 10
  direct_internet_access = "Enabled"

  tags = merge(local.common_tags, { Sandbox = "true" })
}

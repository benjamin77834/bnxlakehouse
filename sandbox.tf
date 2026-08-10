# -----------------------------------------------------------------------------
# SANDBOX - Ambiente de pruebas aislado (opcional)
# -----------------------------------------------------------------------------
# Habilitar con: enable_devlabs = true en terraform.tfvars
# Crea un ambiente reducido para experimentación sin afectar producción.
# Incluye: S3 buckets propios, Glue DB, Athena workgroup, Redshift mini.
# Todo con prefijo "devlabs-" para identificar fácilmente.
# Para destruir solo el devlabs: usar terraform destroy -target=module...
# o simplemente poner enable_devlabs = false y re-aplicar.
# -----------------------------------------------------------------------------

# S3 Buckets del Sandbox (Bronze, Silver, Gold reducidos)
resource "aws_s3_bucket" "devlabs_bronze" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = "${var.project_name}-devlabs-bronze-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_s3_bucket" "devlabs_silver" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = "${var.project_name}-devlabs-silver-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_s3_bucket" "devlabs_gold" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = "${var.project_name}-devlabs-gold-${var.environment}"
  tags   = merge(local.common_tags, { Sandbox = "true" })
}

# Encriptación para buckets devlabs
resource "aws_s3_bucket_server_side_encryption_configuration" "devlabs_bronze_enc" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = aws_s3_bucket.devlabs_bronze[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "devlabs_silver_enc" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = aws_s3_bucket.devlabs_silver[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "devlabs_gold_enc" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = aws_s3_bucket.devlabs_gold[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueo público
resource "aws_s3_bucket_public_access_block" "devlabs_bronze_block" {
  count                   = var.enable_devlabs ? 1 : 0
  bucket                  = aws_s3_bucket.devlabs_bronze[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "devlabs_silver_block" {
  count                   = var.enable_devlabs ? 1 : 0
  bucket                  = aws_s3_bucket.devlabs_silver[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "devlabs_gold_block" {
  count                   = var.enable_devlabs ? 1 : 0
  bucket                  = aws_s3_bucket.devlabs_gold[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: expirar datos del devlabs a los 90 días automáticamente
resource "aws_s3_bucket_lifecycle_configuration" "devlabs_bronze_lifecycle" {
  count  = var.enable_devlabs ? 1 : 0
  bucket = aws_s3_bucket.devlabs_bronze[0].id

  rule {
    id     = "expire-devlabs-data"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 90 }
  }
}

# Glue Catalog Database del Sandbox (aislada de producción)
resource "aws_glue_catalog_database" "devlabs" {
  count       = var.enable_devlabs ? 1 : 0
  name        = "${var.project_name}_devlabs_${var.environment}"
  description = "Sandbox - Base de datos de pruebas aislada"
}

# Glue Crawler del Sandbox
resource "aws_glue_crawler" "devlabs_crawler" {
  count         = var.enable_devlabs ? 1 : 0
  database_name = aws_glue_catalog_database.devlabs[0].name
  name          = "${var.project_name}-devlabs-crawler-${var.environment}"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.devlabs_bronze[0].bucket}/"
  }

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# Athena Workgroup del Sandbox (límite de datos escaneados)
resource "aws_athena_workgroup" "devlabs" {
  count = var.enable_devlabs ? 1 : 0
  name  = "${var.project_name}-devlabs-${var.environment}"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/devlabs-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Límite de 100 MB por query para controlar costos en devlabs
    bytes_scanned_cutoff_per_query = var.devlabs_athena_scan_limit
  }

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# Redshift Serverless del Sandbox (capacidad mínima)
resource "aws_redshiftserverless_namespace" "devlabs" {
  count              = var.enable_devlabs && length(var.subnet_ids) > 0 ? 1 : 0
  namespace_name     = "${var.project_name}-devlabs-${var.environment}"
  db_name            = "devlabs"
  admin_username     = var.redshift_admin_username
  admin_user_password = var.redshift_admin_password

  iam_roles = [aws_iam_role.redshift_role.arn]

  tags = merge(local.common_tags, { Sandbox = "true" })
}

resource "aws_redshiftserverless_workgroup" "devlabs" {
  count          = var.enable_devlabs && length(var.subnet_ids) > 0 ? 1 : 0
  namespace_name = aws_redshiftserverless_namespace.devlabs[0].namespace_name
  workgroup_name = "${var.project_name}-devlabs-wg-${var.environment}"
  base_capacity  = 4 # Mínimo posible para ahorrar

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.redshift[0].id]

  tags = merge(local.common_tags, { Sandbox = "true" })
}

# SageMaker Notebook para Sandbox (instancia pequeña)
resource "aws_sagemaker_notebook_instance" "devlabs" {
  count                = var.enable_devlabs ? 1 : 0
  name                 = "${var.project_name}-devlabs-nb-${var.environment}"
  role_arn             = aws_iam_role.sagemaker_role.arn
  instance_type        = "ml.t3.medium"
  volume_size          = 10
  direct_internet_access = "Enabled"

  tags = merge(local.common_tags, { Sandbox = "true" })
}

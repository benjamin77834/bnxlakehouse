# =============================================================================
# AWS LAKE FORMATION - Gobierno de Accesos al Data Lake
# =============================================================================
#
# Control granular de accesos:
# - Quién puede ver qué base de datos
# - Quién puede ver qué tabla
# - Quién puede ver qué columnas
# - Row-level security (futuro)
#
# Roles definidos:
# - Admin: acceso total a Bronze/Silver/Gold
# - Data Engineer: read/write Bronze+Silver, read Gold
# - Data Scientist: read Silver+Gold
# - Analyst: read-only Gold + Athena
# - ML Service: read Gold (para training)
# =============================================================================

# Registrar como administrador de Lake Formation
resource "aws_lakeformation_data_lake_settings" "main" {
  admins = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-glue-role-${var.environment}"
  ]
}

# Registrar buckets del data lake en Lake Formation
resource "aws_lakeformation_resource" "bronze" {
  count    = length(var.subnet_ids) > 0 ? 1 : 0
  arn      = aws_s3_bucket.data_lake_bronze.arn
  role_arn = aws_iam_role.glue_role.arn
}

resource "aws_lakeformation_resource" "silver" {
  count    = length(var.subnet_ids) > 0 ? 1 : 0
  arn      = aws_s3_bucket.data_lake_silver.arn
  role_arn = aws_iam_role.glue_role.arn
}

resource "aws_lakeformation_resource" "gold" {
  count    = length(var.subnet_ids) > 0 ? 1 : 0
  arn      = aws_s3_bucket.data_lake_gold.arn
  role_arn = aws_iam_role.glue_role.arn
}

# -----------------------------------------------------------------------------
# Permisos: Data Engineer - Bronze + Silver (read/write), Gold (read)
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "engineer_bronze" {
  principal   = aws_iam_role.glue_role.arn
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.data_lake.name
  }
}

resource "aws_lakeformation_permissions" "engineer_tables" {
  principal   = aws_iam_role.glue_role.arn
  permissions = ["SELECT", "INSERT", "DELETE", "DESCRIBE", "ALTER"]

  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
}

# -----------------------------------------------------------------------------
# Permisos: Analyst - Solo lectura Gold via Athena
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "analyst_database" {
  principal   = aws_iam_role.athena_role.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.data_lake.name
  }
}

resource "aws_lakeformation_permissions" "analyst_tables" {
  principal   = aws_iam_role.athena_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
}

# -----------------------------------------------------------------------------
# Permisos: ML / SageMaker - Lectura Gold para training
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "ml_database" {
  principal   = aws_iam_role.sagemaker_role.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.data_lake.name
  }
}

resource "aws_lakeformation_permissions" "ml_tables" {
  principal   = aws_iam_role.sagemaker_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
}

# -----------------------------------------------------------------------------
# Permisos: Redshift Spectrum - Lectura Gold
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "redshift_database" {
  principal   = aws_iam_role.redshift_role.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.data_lake.name
  }
}

resource "aws_lakeformation_permissions" "redshift_tables" {
  principal   = aws_iam_role.redshift_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
}

# -----------------------------------------------------------------------------
# Permisos: Lambda - Lectura para serving
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "lambda_database" {
  principal   = aws_iam_role.lambda_role.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.data_lake.name
  }
}

resource "aws_lakeformation_permissions" "lambda_tables" {
  principal   = aws_iam_role.lambda_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog_database.data_lake.name
    wildcard      = true
  }
}

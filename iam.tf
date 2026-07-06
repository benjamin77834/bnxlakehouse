# =============================================================================
# IAM Roles - Data Lake (Glue, Redshift, Athena)
# =============================================================================
#
# Este archivo define los roles y políticas IAM para los servicios core
# del data lake: ETL (Glue), warehouse (Redshift) y consultas ad-hoc (Athena).
#
# =============================================================================
# TABLA RESUMEN DE PERMISOS
# =============================================================================
#
# ┌─────────────────────┬──────────────────────────────┬─────────────────────────────────────────────────┬──────────────┐
# │ ROL                 │ POLÍTICA                     │ ACCIONES                                        │ RECURSO      │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ glue_role           │ AWSGlueServiceRole           │ (política gestionada AWS - crawlers, jobs, etc) │ *            │
# │                     │ glue_s3_access               │ s3:Get/Put/DeleteObject, ListBucket             │ raw, proc,   │
# │                     │                              │                                                 │ curated      │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ redshift_role       │ redshift_s3_access           │ s3:GetObject, PutObject, ListBucket,            │ raw, proc,   │
# │                     │                              │ GetBucketLocation                               │ curated      │
# │                     │ redshift_glue_access         │ glue:GetDatabase/Tables/Partitions,             │ *            │
# │                     │                              │ BatchGetPartition                               │              │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ athena_role         │ athena_access                │ athena:Start/Stop/GetQueryExecution,            │ workgroup    │
# │                     │                              │ GetQueryResults, GetWorkGroup                   │              │
# │                     │                              │ s3:GetObject, ListBucket (lectura data)         │ raw, proc,   │
# │                     │                              │                                                 │ curated      │
# │                     │                              │ s3:Get/PutObject, ListBucket (resultados)       │ athena-results│
# │                     │                              │ glue:GetDatabase/Tables/Partitions              │ *            │
# └─────────────────────┴──────────────────────────────┴─────────────────────────────────────────────────┴──────────────┘
#
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role - AWS Glue
# -----------------------------------------------------------------------------

resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Política gestionada de Glue Service
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Acceso de Glue a los buckets del data lake
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "${var.project_name}-glue-s3-access-${var.environment}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake_landing.arn,
          "${aws_s3_bucket.data_lake_landing.arn}/*",
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Role - Redshift Serverless
# -----------------------------------------------------------------------------

resource "aws_iam_role" "redshift_role" {
  name = "${var.project_name}-redshift-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Redshift puede leer de S3 (COPY/UNLOAD)
resource "aws_iam_role_policy" "redshift_s3_access" {
  name = "${var.project_name}-redshift-s3-access-${var.environment}"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*"
        ]
      }
    ]
  })
}

# Redshift accede al Glue Data Catalog (para Redshift Spectrum)
resource "aws_iam_role_policy" "redshift_glue_access" {
  name = "${var.project_name}-redshift-glue-access-${var.environment}"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Role - Athena (para usuarios/servicios que consultan)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "athena_role" {
  name = "${var.project_name}-athena-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "athena_access" {
  name = "${var.project_name}-athena-access-${var.environment}"
  role = aws_iam_role.athena_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup"
        ]
        Resource = [
          aws_athena_workgroup.data_lake.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Data source
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# =============================================================================
# IAM Roles - SageMaker & Bedrock (AI/ML)
# =============================================================================
#
# Este archivo define los roles y políticas IAM para servicios de IA/ML.
#
# =============================================================================
# TABLA RESUMEN DE PERMISOS
# =============================================================================
#
# ┌─────────────────────┬──────────────────────────────┬─────────────────────────────────────────────────┬──────────────┐
# │ ROL                 │ POLÍTICA                     │ ACCIONES                                        │ RECURSO      │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ sagemaker_role      │ AmazonSageMakerFullAccess    │ (política gestionada AWS)                       │ *            │
# │                     │ sagemaker_s3_access          │ s3:Get/Put/DeleteObject, ListBucket, GetBucket  │ raw,proc,    │
# │                     │                              │                                                 │ curated,     │
# │                     │                              │                                                 │ artifacts    │
# │                     │ sagemaker_glue_access        │ glue:GetDatabase/Tables/Partitions, Search      │ *            │
# │                     │ sagemaker_ecr_access         │ ecr:Get/BatchGet/Create/Put/Upload              │ *            │
# │                     │ sagemaker_pass_role          │ iam:PassRole (a sí mismo)                       │ self role    │
# │                     │ sagemaker_logs               │ logs:Create/Put/Describe                        │ /aws/sage*   │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ bedrock_role        │ bedrock_model_access         │ bedrock:InvokeModel, InvokeModelWithResponse    │ *            │
# │                     │                              │ Stream, ListFoundationModels, GetFoundation     │              │
# │                     │ bedrock_knowledge_base       │ bedrock:Create/Get/List/DeleteKnowledgeBase,    │ *            │
# │                     │                              │ DataSource, IngestionJob, Retrieve,             │              │
# │                     │                              │ RetrieveAndGenerate                             │              │
# │                     │ bedrock_agents               │ bedrock:Create/Get/List/Delete/Update/Prepare/  │ *            │
# │                     │                              │ InvokeAgent, CreateAgentActionGroup/Alias       │              │
# │                     │ bedrock_s3_access            │ s3:Get/PutObject, ListBucket, GetBucketLocation│ curated,     │
# │                     │                              │                                                 │ artifacts    │
# │                     │ bedrock_custom_model         │ bedrock:Create/Get/List/Stop/Delete             │ *            │
# │                     │                              │ ModelCustomizationJob, CustomModel              │              │
# └─────────────────────┴──────────────────────────────┴─────────────────────────────────────────────────┴──────────────┘
#
# RECURSO ADICIONAL: S3 Bucket "sagemaker-artifacts" (modelos, checkpoints, datos de entrenamiento)
#
# =============================================================================

# -----------------------------------------------------------------------------
# SageMaker Execution Role
# Permite al servicio SageMaker asumir este rol para ejecutar notebooks,
# training jobs, processing jobs y endpoints de inferencia.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sagemaker_role" {
  name = "${var.project_name}-sagemaker-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Política gestionada base de SageMaker - incluye permisos para notebooks,
# training, endpoints, feature store, model registry, etc.
resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Acceso a S3: permite a SageMaker leer datos de entrenamiento desde los
# buckets del data lake y escribir artefactos (modelos, checkpoints) en
# el bucket de artefactos.
resource "aws_iam_role_policy" "sagemaker_s3_access" {
  name = "${var.project_name}-sagemaker-s3-access-${var.environment}"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*",
          aws_s3_bucket.sagemaker_artifacts.arn,
          "${aws_s3_bucket.sagemaker_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Acceso a Glue Data Catalog: permite a SageMaker descubrir y leer
# los schemas de tablas registradas en el catálogo (útil para
# SageMaker Data Wrangler, Feature Store, etc.)
resource "aws_iam_role_policy" "sagemaker_glue_access" {
  name = "${var.project_name}-sagemaker-glue-access-${var.environment}"
  role = aws_iam_role.sagemaker_role.id

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
          "glue:SearchTables"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Acceso a ECR: permite construir y descargar imágenes de contenedores
# personalizadas para training jobs y endpoints de inferencia.
resource "aws_iam_role_policy" "sagemaker_ecr_access" {
  name = "${var.project_name}-sagemaker-ecr-access-${var.environment}"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "ecr:CreateRepository",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# PassRole: SageMaker necesita pasarse su propio rol al crear training
# jobs, processing jobs y endpoints. Sin esto, falla al lanzar trabajos.
resource "aws_iam_role_policy" "sagemaker_pass_role" {
  name = "${var.project_name}-sagemaker-pass-role-${var.environment}"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-sagemaker-role-${var.environment}"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "sagemaker.amazonaws.com"
          }
        }
      }
    ]
  })
}

# CloudWatch Logs: permite a SageMaker escribir logs de entrenamiento,
# procesamiento e inferencia para monitoreo y debugging.
resource "aws_iam_role_policy" "sagemaker_logs" {
  name = "${var.project_name}-sagemaker-logs-${var.environment}"
  role = aws_iam_role.sagemaker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Bedrock Invocation Role
# Permite a usuarios y servicios internos de la cuenta asumir este rol
# para invocar modelos fundacionales, gestionar Knowledge Bases y Agents.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bedrock_role" {
  name = "${var.project_name}-bedrock-role-${var.environment}"

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

# Invocación de modelos fundacionales: permite llamar a modelos como
# Claude, Titan, Llama, etc. tanto en modo síncrono como streaming.
resource "aws_iam_role_policy" "bedrock_model_access" {
  name = "${var.project_name}-bedrock-model-access-${var.environment}"
  role = aws_iam_role.bedrock_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Knowledge Bases: permite crear bases de conocimiento, ingestar
# documentos desde S3 y hacer consultas con RAG (Retrieval Augmented
# Generation) para respuestas contextualizadas.
resource "aws_iam_role_policy" "bedrock_knowledge_base" {
  name = "${var.project_name}-bedrock-kb-access-${var.environment}"
  role = aws_iam_role.bedrock_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:CreateKnowledgeBase",
          "bedrock:GetKnowledgeBase",
          "bedrock:ListKnowledgeBases",
          "bedrock:DeleteKnowledgeBase",
          "bedrock:AssociateThirdPartyKnowledgeBase",
          "bedrock:CreateDataSource",
          "bedrock:GetDataSource",
          "bedrock:ListDataSources",
          "bedrock:DeleteDataSource",
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob",
          "bedrock:ListIngestionJobs",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Agents: permite crear y gestionar agentes de Bedrock que pueden
# ejecutar acciones, consultar Knowledge Bases y orquestar flujos
# complejos de IA generativa.
resource "aws_iam_role_policy" "bedrock_agents" {
  name = "${var.project_name}-bedrock-agents-access-${var.environment}"
  role = aws_iam_role.bedrock_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:CreateAgent",
          "bedrock:GetAgent",
          "bedrock:ListAgents",
          "bedrock:DeleteAgent",
          "bedrock:UpdateAgent",
          "bedrock:PrepareAgent",
          "bedrock:InvokeAgent",
          "bedrock:CreateAgentActionGroup",
          "bedrock:CreateAgentAlias"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Acceso a S3: permite a Bedrock leer documentos para Knowledge Bases
# y datos de fine-tuning desde los buckets curated y sagemaker-artifacts.
resource "aws_iam_role_policy" "bedrock_s3_access" {
  name = "${var.project_name}-bedrock-s3-access-${var.environment}"
  role = aws_iam_role.bedrock_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*",
          aws_s3_bucket.sagemaker_artifacts.arn,
          "${aws_s3_bucket.sagemaker_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Custom Models / Fine-tuning: permite crear trabajos de personalización
# de modelos (fine-tuning) y gestionar modelos custom resultantes.
resource "aws_iam_role_policy" "bedrock_custom_model" {
  name = "${var.project_name}-bedrock-custom-model-${var.environment}"
  role = aws_iam_role.bedrock_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:CreateModelCustomizationJob",
          "bedrock:GetModelCustomizationJob",
          "bedrock:ListModelCustomizationJobs",
          "bedrock:StopModelCustomizationJob",
          "bedrock:GetCustomModel",
          "bedrock:ListCustomModels",
          "bedrock:DeleteCustomModel"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# S3 Bucket - Artefactos de SageMaker
# Almacena modelos entrenados (.tar.gz), datos de entrenamiento procesados,
# checkpoints intermedios y resultados de batch transform.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "sagemaker_artifacts" {
  bucket = "${var.project_name}-sagemaker-artifacts-${var.environment}"

  tags = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sagemaker_encryption" {
  bucket = aws_s3_bucket.sagemaker_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sagemaker_public_access" {
  bucket = aws_s3_bucket.sagemaker_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

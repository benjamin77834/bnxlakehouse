# =============================================================================
# ECR - Repositorios de Imágenes Docker
# =============================================================================
#
# Repositorios para:
# 1. Kubernetes (EKS) - Imágenes de microservicios y jobs
# 2. Agentes IA - Imágenes de modelos custom, agentes Bedrock, pipelines ML
# 3. ETL - Contenedores custom para Glue/Spark
# =============================================================================

# -----------------------------------------------------------------------------
# Repositorios EKS / Kubernetes
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "eks_services" {
  name                 = "${var.project_name}/eks-services"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "eks_jobs" {
  name                 = "${var.project_name}/eks-jobs"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "eks_ingestion" {
  name                 = "${var.project_name}/eks-ingestion"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Repositorios Agentes IA / ML
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "ai_training" {
  name                 = "${var.project_name}/ai-training"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "ai_inference" {
  name                 = "${var.project_name}/ai-inference"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "ai_agents" {
  name                 = "${var.project_name}/ai-agents"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "ai_pipelines" {
  name                 = "${var.project_name}/ai-pipelines"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Repositorio ETL Custom (Glue/Spark containers)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "etl_custom" {
  name                 = "${var.project_name}/etl-custom"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data_lake.arn
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Lifecycle Policy - Limpiar imágenes viejas automáticamente
# -----------------------------------------------------------------------------

locals {
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las ultimas 20 imagenes taggeadas"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "release"]
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Eliminar imagenes sin tag despues de 7 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "eks_services" {
  repository = aws_ecr_repository.eks_services.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "eks_jobs" {
  repository = aws_ecr_repository.eks_jobs.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "eks_ingestion" {
  repository = aws_ecr_repository.eks_ingestion.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "ai_training" {
  repository = aws_ecr_repository.ai_training.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "ai_inference" {
  repository = aws_ecr_repository.ai_inference.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "ai_agents" {
  repository = aws_ecr_repository.ai_agents.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "ai_pipelines" {
  repository = aws_ecr_repository.ai_pipelines.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "etl_custom" {
  repository = aws_ecr_repository.etl_custom.name
  policy     = local.ecr_lifecycle_policy
}

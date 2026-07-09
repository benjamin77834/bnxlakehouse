# =============================================================================
# SEGURIDAD - KMS, WAF, GuardDuty, CloudTrail, Config
# =============================================================================
#
# Capa de seguridad transversal del data lake:
# - KMS: Llaves de encriptación gestionadas para S3, Redshift, Glue
# - WAF: Protección del API Gateway contra ataques web
# - GuardDuty: Detección de amenazas y comportamiento anómalo
# - CloudTrail: Auditoría de todas las acciones en la cuenta
# - AWS Config: Compliance y evaluación de configuraciones
# =============================================================================

# -----------------------------------------------------------------------------
# KMS - Llaves de encriptación
# -----------------------------------------------------------------------------

resource "aws_kms_key" "data_lake" {
  description             = "Llave KMS para encriptar datos del data lake"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowDataLakeServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "glue.amazonaws.com",
            "redshift.amazonaws.com",
            "lambda.amazonaws.com",
            "sagemaker.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "data_lake" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.data_lake.key_id
}

# -----------------------------------------------------------------------------
# WAF - Protección de API Gateway
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "api_protection" {
  name        = "${var.project_name}-waf-${var.environment}"
  description = "WAF para proteger API Gateway del data lake"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Regla: Limitar rate (máximo 2000 requests por IP en 5 min)
  rule {
    name     = "RateLimit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
    }
  }

  # Regla: Bloquear SQL Injection
  rule {
    name     = "SQLInjection"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli"
    }
  }

  # Regla: Bloquear ataques conocidos
  rule {
    name     = "CommonRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
  }

  tags = local.common_tags
}

# Asociar WAF con API Gateway
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_rest_api.data_lake_api.execution_arn
  web_acl_arn  = aws_wafv2_web_acl.api_protection.arn
}

# -----------------------------------------------------------------------------
# GuardDuty - Detección de amenazas
# -----------------------------------------------------------------------------

resource "aws_guardduty_detector" "data_lake" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# CloudTrail - Auditoría
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-${var.environment}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "data_lake" {
  name                          = "${var.project_name}-trail-${var.environment}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.bucket
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# AWS Config - Compliance
# -----------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "data_lake" {
  name     = "${var.project_name}-config-${var.environment}"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "data_lake" {
  name           = "${var.project_name}-config-delivery-${var.environment}"
  s3_bucket_name = aws_s3_bucket.cloudtrail.bucket
  s3_key_prefix  = "config"

  depends_on = [aws_config_configuration_recorder.data_lake]
}

resource "aws_config_configuration_recorder_status" "data_lake" {
  name       = aws_config_configuration_recorder.data_lake.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.data_lake]
}

# Regla: S3 buckets deben tener encriptación
resource "aws_config_config_rule" "s3_encryption" {
  name = "${var.project_name}-s3-encryption-${var.environment}"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.data_lake]

  tags = local.common_tags
}

# Regla: S3 buckets no deben ser públicos
resource "aws_config_config_rule" "s3_public_access" {
  name = "${var.project_name}-s3-no-public-${var.environment}"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.data_lake]

  tags = local.common_tags
}

# IAM Role para AWS Config
resource "aws_iam_role" "config_role" {
  name = "${var.project_name}-config-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${var.project_name}-config-s3-${var.environment}"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketAcl"]
        Resource = [
          aws_s3_bucket.cloudtrail.arn,
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# DATA PROTECTION - Guardrails PII, Macie, Bedrock Guardrails
# =============================================================================
#
# Protección de información personal (PII) y datos confidenciales:
# 1. Amazon Macie: Escanea S3 buscando PII (tarjetas, SSN, emails, etc.)
# 2. Bedrock Guardrails: Filtra PII en inputs/outputs de modelos GenAI
# 3. Glue DataBrew: Perfiles de datos para detectar columnas sensibles
# 4. Alarmas cuando se detecta PII en las capas del data lake
# =============================================================================

# -----------------------------------------------------------------------------
# Amazon Macie - Detección de PII en S3
# -----------------------------------------------------------------------------

resource "aws_macie2_account" "data_lake" {}

# Habilitar Macie en los buckets del data lake
resource "aws_macie2_classification_job" "bronze_scan" {
  name     = "${var.project_name}-bronze-pii-scan-${var.environment}"
  job_type = "SCHEDULED"

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [aws_s3_bucket.data_lake_bronze.bucket]
    }
  }

  schedule_frequency {
    weekly_schedule = "MONDAY"
  }

  sampling_percentage = 100

  tags = local.common_tags

  depends_on = [aws_macie2_account.data_lake]
}

resource "aws_macie2_classification_job" "silver_scan" {
  name     = "${var.project_name}-silver-pii-scan-${var.environment}"
  job_type = "SCHEDULED"

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [aws_s3_bucket.data_lake_silver.bucket]
    }
  }

  schedule_frequency {
    weekly_schedule = "WEDNESDAY"
  }

  sampling_percentage = 100

  tags = local.common_tags

  depends_on = [aws_macie2_account.data_lake]
}

resource "aws_macie2_classification_job" "gold_scan" {
  name     = "${var.project_name}-gold-pii-scan-${var.environment}"
  job_type = "SCHEDULED"

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [aws_s3_bucket.data_lake_gold.bucket]
    }
  }

  schedule_frequency {
    weekly_schedule = "FRIDAY"
  }

  sampling_percentage = 100

  tags = local.common_tags

  depends_on = [aws_macie2_account.data_lake]
}

# -----------------------------------------------------------------------------
# Bedrock Guardrails - Filtrado de PII en modelos GenAI
# -----------------------------------------------------------------------------

resource "aws_bedrock_guardrail" "pii_filter" {
  name                      = "${var.project_name}-pii-guardrail-${var.environment}"
  description               = "Filtra PII en inputs y outputs de modelos fundacionales"
  blocked_input_messaging   = "Su mensaje contiene informacion personal que no puede ser procesada. Por favor elimine datos sensibles como nombres, emails, telefonos, tarjetas o documentos de identidad."
  blocked_outputs_messaging = "La respuesta fue filtrada porque contenia informacion personal identificable (PII)."

  # Filtro de PII sensible
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_SECRET_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "IP_ADDRESS"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_PASSPORT_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "DRIVER_ID"
      action = "BLOCK"
    }
  }

  # Filtro de contenido dañino
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }

  tags = local.common_tags
}

resource "aws_bedrock_guardrail_version" "pii_filter" {
  guardrail_arn = aws_bedrock_guardrail.pii_filter.guardrail_arn
  description   = "Version inicial del guardrail PII"
}

# -----------------------------------------------------------------------------
# Alarma: Macie detectó PII
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "macie_pii_detected" {
  alarm_name          = "${var.project_name}-pii-detected-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SensitiveDataDiscoveryResult"
  namespace           = "AWS/Macie"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Macie detecto PII en los buckets del data lake"

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

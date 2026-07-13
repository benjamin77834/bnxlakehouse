# =============================================================================
# OBSERVABILIDAD - CloudWatch Dashboards, Alarmas, Métricas y Logs
# =============================================================================
#
# Tableros de control para cada proceso del data lake:
# 1. Dashboard General - Vista ejecutiva de salud del data lake
# 2. Dashboard Ingesta - Landing, Lambda processor, Kafka
# 3. Dashboard ETL - Glue jobs, crawlers, catálogo
# 4. Dashboard Analítica - Athena, Redshift
# 5. Dashboard IA/ML - SageMaker, Bedrock
# 6. Dashboard Serving - API Gateway, Lambdas de salida
#
# Alarmas SNS para notificaciones críticas.
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic para alertas
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${var.environment}"
  tags = local.common_tags
}

resource "aws_sns_topic" "critical_alerts" {
  name = "${var.project_name}-critical-alerts-${var.environment}"
  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Log Groups centralizados
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_landing" {
  name              = "/aws/lambda/${var.project_name}-landing-processor-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_serving_gold" {
  name              = "/aws/lambda/${var.project_name}-serving-gold-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_serving_ml" {
  name              = "/aws/lambda/${var.project_name}-serving-ml-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "glue_jobs" {
  name              = "/aws/glue/${var.project_name}-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# Dashboard 1: Vista General (Ejecutivo)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "general" {
  dashboard_name = "${var.project_name}-general-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 📊 Data Lake - Vista General\nEstado de salud del data lake **${var.project_name}** (${var.environment})"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 8, height = 6
        properties = {
          title   = "S3 - Objetos por Bucket"
          region  = var.aws_region
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", "${var.project_name}-bronze-${var.environment}", "StorageType", "AllStorageTypes"],
            ["AWS/S3", "NumberOfObjects", "BucketName", "${var.project_name}-silver-${var.environment}", "StorageType", "AllStorageTypes"],
            ["AWS/S3", "NumberOfObjects", "BucketName", "${var.project_name}-gold-${var.environment}", "StorageType", "AllStorageTypes"]
          ]
          period = 86400
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8, y = 2, width = 8, height = 6
        properties = {
          title   = "S3 - Tamaño por Bucket (Bytes)"
          region  = var.aws_region
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", "${var.project_name}-bronze-${var.environment}", "StorageType", "StandardStorage"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", "${var.project_name}-silver-${var.environment}", "StorageType", "StandardStorage"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", "${var.project_name}-gold-${var.environment}", "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16, y = 2, width = 8, height = 6
        properties = {
          title   = "Lambda - Invocaciones Totales"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-landing-processor-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 12, height = 6
        properties = {
          title   = "Lambda - Errores"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-landing-processor-${var.environment}"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 8, width = 12, height = 6
        properties = {
          title   = "Redshift - Queries Ejecutados"
          region  = var.aws_region
          metrics = [
            ["AWS/Redshift-Serverless", "QueriesCompletedPerSecond", "Workgroup", "${var.project_name}-wg-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard 2: Ingesta (Landing, Lambda, Kafka)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "ingestion" {
  dashboard_name = "${var.project_name}-ingesta-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 📥 Ingesta\nMonitoreo de Landing Zone, Lambda Processor y MSK Kafka"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 12, height = 6
        properties = {
          title   = "Landing Processor - Duración (ms)"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-landing-processor-${var.environment}", { stat = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-landing-processor-${var.environment}", { stat = "p99" }]
          ]
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "Landing Processor - Concurrent Executions"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${var.project_name}-landing-processor-${var.environment}"]
          ]
          period = 60
          stat   = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 12, height = 6
        properties = {
          title   = "MSK - Bytes In/Out por Segundo"
          region  = var.aws_region
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", "Cluster Name", "${var.project_name}-msk-${var.environment}"],
            ["AWS/Kafka", "BytesOutPerSec", "Cluster Name", "${var.project_name}-msk-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 8, width = 12, height = 6
        properties = {
          title   = "MSK - Consumer Lag"
          region  = var.aws_region
          metrics = [
            ["AWS/Kafka", "EstimatedMaxTimeLag", "Cluster Name", "${var.project_name}-msk-${var.environment}"]
          ]
          period = 300
          stat   = "Maximum"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard 3: ETL (Glue Jobs, Crawlers)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "etl" {
  dashboard_name = "${var.project_name}-etl-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# ⚙️ ETL - Glue Jobs & Crawlers\nMonitoreo de transformaciones Bronze → Silver → Gold"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 12, height = 6
        properties = {
          title   = "Glue Jobs - Duración (segundos)"
          region  = var.aws_region
          metrics = [
            ["Glue", "glue.driver.aggregate.elapsedTime", "JobName", "${var.project_name}-bronze-to-silver", "Type", "gauge"],
            ["Glue", "glue.driver.aggregate.elapsedTime", "JobName", "${var.project_name}-silver-to-gold", "Type", "gauge"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "Glue Jobs - Bytes Leídos/Escritos"
          region  = var.aws_region
          metrics = [
            ["Glue", "glue.driver.aggregate.bytesRead", "JobName", "${var.project_name}-bronze-to-silver", "Type", "gauge"],
            ["Glue", "glue.driver.aggregate.recordsWritten", "JobName", "${var.project_name}-bronze-to-silver", "Type", "gauge"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 12, height = 6
        properties = {
          title   = "Crawlers - Tablas Creadas/Actualizadas"
          region  = var.aws_region
          metrics = [
            ["Glue", "glue.driver.aggregate.numCompletedStages", "JobName", "${var.project_name}-bronze-crawler-${var.environment}", "Type", "gauge"]
          ]
          period = 3600
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 8, width = 12, height = 6
        properties = {
          title   = "Glue Data Catalog - Tablas Totales"
          region  = var.aws_region
          metrics = [
            ["AWS/Glue", "TablesCount", "DatabaseName", "${var.project_name}_${var.environment}"]
          ]
          period = 86400
          stat   = "Average"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard 4: Analítica (Athena, Redshift)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "analytics" {
  dashboard_name = "${var.project_name}-analitica-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 📊 Analítica\nAthena queries y Redshift Serverless performance"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 12, height = 6
        properties = {
          title   = "Athena - Datos Escaneados (Bytes)"
          region  = var.aws_region
          metrics = [
            ["AWS/Athena", "ProcessedBytes", "WorkGroup", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "Athena - Tiempo de Ejecución (ms)"
          region  = var.aws_region
          metrics = [
            ["AWS/Athena", "TotalExecutionTime", "WorkGroup", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 8, height = 6
        properties = {
          title   = "Redshift - RPU Consumidos"
          region  = var.aws_region
          metrics = [
            ["AWS/Redshift-Serverless", "ComputeCapacity", "Workgroup", "${var.project_name}-wg-${var.environment}"]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8, y = 8, width = 8, height = 6
        properties = {
          title   = "Redshift - Query Duration"
          region  = var.aws_region
          metrics = [
            ["AWS/Redshift-Serverless", "QueryDuration", "Workgroup", "${var.project_name}-wg-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16, y = 8, width = 8, height = 6
        properties = {
          title   = "Redshift - Conexiones Activas"
          region  = var.aws_region
          metrics = [
            ["AWS/Redshift-Serverless", "DatabaseConnections", "Workgroup", "${var.project_name}-wg-${var.environment}"]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard 5: IA/ML (SageMaker, Bedrock)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "ai_ml" {
  dashboard_name = "${var.project_name}-ai-ml-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 🤖 IA Generativa & ML\nSageMaker endpoints, training jobs y Bedrock invocaciones"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 12, height = 6
        properties = {
          title   = "SageMaker Endpoints - Invocaciones"
          region  = var.aws_region
          metrics = [
            ["AWS/SageMaker", "Invocations", "EndpointName", "${var.project_name}-endpoint-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 2, width = 12, height = 6
        properties = {
          title   = "SageMaker Endpoints - Latencia (ms)"
          region  = var.aws_region
          metrics = [
            ["AWS/SageMaker", "ModelLatency", "EndpointName", "${var.project_name}-endpoint-${var.environment}"],
            ["AWS/SageMaker", "OverheadLatency", "EndpointName", "${var.project_name}-endpoint-${var.environment}"]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 12, height = 6
        properties = {
          title   = "Bedrock - Invocaciones de Modelos"
          region  = var.aws_region
          metrics = [
            ["AWS/Bedrock", "Invocations", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            ["AWS/Bedrock", "Invocations", "ModelId", "anthropic.claude-3-haiku-20240307-v1:0"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 8, width = 12, height = 6
        properties = {
          title   = "Bedrock - Latencia y Tokens"
          region  = var.aws_region
          metrics = [
            ["AWS/Bedrock", "InvocationLatency", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            ["AWS/Bedrock", "InputTokenCount", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            ["AWS/Bedrock", "OutputTokenCount", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"]
          ]
          period = 300
          stat   = "Average"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Dashboard 6: Serving / APIs de Salida
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "serving" {
  dashboard_name = "${var.project_name}-serving-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 🚀 Serving - APIs de Salida\nAPI Gateway, Lambdas de datos y ML para consumidores"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 2, width = 8, height = 6
        properties = {
          title   = "API Gateway - Requests"
          region  = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", "${var.project_name}-api-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8, y = 2, width = 8, height = 6
        properties = {
          title   = "API Gateway - Latencia (ms)"
          region  = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", "${var.project_name}-api-${var.environment}", { stat = "Average" }],
            ["AWS/ApiGateway", "Latency", "ApiName", "${var.project_name}-api-${var.environment}", { stat = "p99" }]
          ]
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 16, y = 2, width = 8, height = 6
        properties = {
          title   = "API Gateway - Errores 4xx/5xx"
          region  = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "4XXError", "ApiName", "${var.project_name}-api-${var.environment}"],
            ["AWS/ApiGateway", "5XXError", "ApiName", "${var.project_name}-api-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 8, width = 12, height = 6
        properties = {
          title   = "Lambda Serving Gold - Performance"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 8, width = 12, height = 6
        properties = {
          title   = "Lambda Serving ML - Performance"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"]
          ]
          period = 60
          stat   = "Sum"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Alarmas Críticas
# -----------------------------------------------------------------------------

# Alarma: Lambda Landing con errores
resource "aws_cloudwatch_metric_alarm" "lambda_landing_errors" {
  alarm_name          = "${var.project_name}-landing-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda landing-processor tiene mas de 5 errores en 10 min"

  dimensions = {
    FunctionName = "${var.project_name}-landing-processor-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# Alarma: Glue Job falló
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  alarm_name          = "${var.project_name}-glue-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTask"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Un Glue Job tiene tareas fallidas"

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

# Alarma: Redshift capacity alto (>80% RPUs)
resource "aws_cloudwatch_metric_alarm" "redshift_high_capacity" {
  alarm_name          = "${var.project_name}-redshift-high-capacity-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ComputeCapacity"
  namespace           = "AWS/Redshift-Serverless"
  period              = 300
  statistic           = "Average"
  threshold           = var.redshift_base_capacity * 0.8
  alarm_description   = "Redshift usando mas del 80% de capacidad base"

  dimensions = {
    Workgroup = "${var.project_name}-wg-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# Alarma: API Gateway errores 5xx
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${var.project_name}-api-5xx-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway tiene mas de 10 errores 5xx en 10 min"

  dimensions = {
    ApiName = "${var.project_name}-api-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

# Alarma: MSK Kafka disco >80%
resource "aws_cloudwatch_metric_alarm" "msk_disk_usage" {
  alarm_name          = "${var.project_name}-msk-disk-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "MSK Kafka disco >80% usado"

  dimensions = {
    "Cluster Name" = "${var.project_name}-msk-${var.environment}"
  }

  alarm_actions = [aws_sns_topic.critical_alerts.arn]

  tags = local.common_tags
}

# Dashboard de costos movido a dashboard_costs.tf (dashboard unificado)

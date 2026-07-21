# =============================================================================
# DASHBOARD UNIFICADO DE COSTOS - Todos los servicios en un solo panel
# =============================================================================
#
# Dashboard centralizado que muestra:
# - Gasto total y por servicio (billing)
# - Métricas de consumo que generan costo (RPUs, invocaciones, tokens, etc.)
# - Estado de presupuestos
# - Alertas activas
# - Neptune, Macie, Bedrock, y todos los servicios del data lake
# =============================================================================

resource "aws_cloudwatch_dashboard" "costs_unified" {
  dashboard_name = "${var.project_name}-costos-unificado-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # --- HEADER ---
      {
        type   = "text"
        x      = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# 💰 Dashboard Unificado de Costos - ${var.project_name} (${var.environment})\nTodos los servicios | Actualizado cada 6 horas | Budget total: $${var.budget_total}/mes"
        }
      },

      # --- FILA 1: Gasto Global ---
      {
        type   = "metric"
        x      = 0, y = 2, width = 8, height = 6
        properties = {
          title   = "Gasto Total Estimado (USD)"
          region  = var.aws_region
          metrics = [["DataLake/Costs", "TotalCostEstimated"]]
          period  = 3600
          stat    = "Maximum"
          view    = "singleValue"
        }
      },
      {
        type   = "metric"
        x      = 8, y = 2, width = 16, height = 6
        properties = {
          title   = "Gasto por Servicio (USD) - Calculado"
          region  = var.aws_region
          metrics = [
            ["DataLake/Costs", "ServiceCost", "ServiceName", "Redshift"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "RDS"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "EC2"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "NAT Gateway"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "Load Balancer"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "OpenSearch"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "S3"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "MSK Kafka"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "EKS"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "SageMaker"],
            ["DataLake/Costs", "ServiceCost", "ServiceName", "CloudWatch"]
          ]
          period = 86400
          stat   = "Maximum"
          view   = "bar"
        }
      },

      # --- FILA 2: Proxies de Costo (métricas que generan gasto) ---
      {
        type   = "text"
        x      = 0, y = 8, width = 24, height = 1
        properties = {
          markdown = "### Metricas de Consumo (generan costo)"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 9, width = 6, height = 5
        properties = {
          title   = "Redshift RPU-Horas"
          region  = var.aws_region
          metrics = [["AWS/Redshift-Serverless", "ComputeSeconds", "Workgroup", "${var.project_name}-wg-${var.environment}"]]
          period  = 3600
          stat    = "Sum"
          view    = "singleValue"
        }
      },
      {
        type   = "metric"
        x      = 6, y = 9, width = 6, height = 5
        properties = {
          title   = "Lambda Invocaciones (todas)"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-landing-processor-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-serving-gold-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-serving-ml-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-cost-remediation-${var.environment}"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-daily-cost-report-${var.environment}"]
          ]
          period = 3600
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 9, width = 6, height = 5
        properties = {
          title   = "Athena TB Escaneados"
          region  = var.aws_region
          metrics = [["AWS/Athena", "ProcessedBytes", "WorkGroup", "${var.project_name}-${var.environment}"]]
          period  = 3600
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 18, y = 9, width = 6, height = 5
        properties = {
          title   = "Bedrock Tokens (I/O)"
          region  = var.aws_region
          metrics = [
            ["AWS/Bedrock", "InputTokenCount", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            ["AWS/Bedrock", "OutputTokenCount", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"]
          ]
          period = 3600
          stat   = "Sum"
        }
      },

      # --- FILA 3: Más servicios ---
      {
        type   = "metric"
        x      = 0, y = 14, width = 6, height = 5
        properties = {
          title   = "Neptune - Requests"
          region  = var.aws_region
          metrics = [
            ["AWS/Neptune", "GremlinRequestsPerSec", "DBClusterIdentifier", "${var.project_name}-neptune-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 6, y = 14, width = 6, height = 5
        properties = {
          title   = "MSK Kafka - Bytes In"
          region  = var.aws_region
          metrics = [["AWS/Kafka", "BytesInPerSec", "Cluster Name", "${var.project_name}-msk-${var.environment}"]]
          period  = 3600
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12, y = 14, width = 6, height = 5
        properties = {
          title   = "API Gateway Requests"
          region  = var.aws_region
          metrics = [["AWS/ApiGateway", "Count", "ApiName", "${var.project_name}-api-${var.environment}"]]
          period  = 3600
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 18, y = 14, width = 6, height = 5
        properties = {
          title   = "EKS - Node CPU"
          region  = var.aws_region
          metrics = [["ContainerInsights", "node_cpu_utilization", "ClusterName", "${var.project_name}-eks-${var.environment}"]]
          period  = 3600
          stat    = "Average"
        }
      },

      # --- FILA 4: Alertas y Remediación ---
      {
        type   = "text"
        x      = 0, y = 19, width = 24, height = 1
        properties = {
          markdown = "### Alertas y Remediacion de Costos"
        }
      },
      {
        type   = "metric"
        x      = 0, y = 20, width = 8, height = 5
        properties = {
          title   = "Remediacion Ejecutada"
          region  = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-cost-remediation-${var.environment}"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-cost-remediation-${var.environment}"]
          ]
          period = 86400
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8, y = 20, width = 8, height = 5
        properties = {
          title   = "Actividad por Usuario (acciones/dia)"
          region  = var.aws_region
          metrics = [
            ["DataLake/Costs", "UserActions", "UserName", "benjamin.garcia@banamex.com"],
            ["DataLake/Costs", "UserActions", "UserName", "AWSServiceRoleForConfig"],
            ["DataLake/Costs", "UserActions", "UserName", "datalake-cost-calculator-role-dev"]
          ]
          period = 86400
          stat   = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 16, y = 20, width = 8, height = 5
        properties = {
          title   = "WAF - Blocked Requests"
          region  = var.aws_region
          metrics = [["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.project_name}-waf-${var.environment}", "Region", var.aws_region, "Rule", "ALL"]]
          period  = 3600
          stat    = "Sum"
        }
      },

      # --- FILA 5: Tabla de presupuestos ---
      {
        type   = "text"
        x      = 0, y = 25, width = 24, height = 4
        properties = {
          markdown = "### Presupuestos Configurados\n| Servicio | Budget/Mes | Alerta 80% | Alerta 100% | Accion al 90% |\n|----------|-----------|------------|-------------|---------------|\n| **Total** | $${var.budget_total} | $${tonumber(var.budget_total) * 0.8} | $${var.budget_total} | Notificacion |\n| **Redshift** | $${var.budget_redshift} | $${tonumber(var.budget_redshift) * 0.8} | $${var.budget_redshift} | Pausar (capacity=0) |\n| **Lambda+API** | $${var.budget_lambda_api} | $${tonumber(var.budget_lambda_api) * 0.8} | $${var.budget_lambda_api} | Throttle (concurrency=1) |\n| **Storage S3** | $${var.budget_storage} | $${tonumber(var.budget_storage) * 0.8} | $${var.budget_storage} | Notificacion |\n| **Neptune** | ~$100 | - | - | Auto-stop si idle |\n| **MSK Kafka** | ~$460 | - | - | Notificacion |\n| **Bedrock** | Variable | - | - | Notificacion |\n\n**Reporte diario:** Se envia a las 8 AM UTC a la lista de distribucion configurada."
        }
      }
    ]
  })
}

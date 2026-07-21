# =============================================================================
# PWA - Amplify Hosting + Lambda API Backend
# =============================================================================
#
# App PWA para monitoreo de costos en iOS/Android/Web:
# - Frontend: PWA desplegada en AWS Amplify (CDN global)
# - Backend: Lambda + API Gateway (endpoint /api/costs)
# - Datos: Consulta Cost Explorer y CloudWatch en tiempo real
# =============================================================================

# -----------------------------------------------------------------------------
# Amplify App - Hosting de la PWA
# -----------------------------------------------------------------------------

resource "aws_amplify_app" "costs_pwa" {
  name = "${var.project_name}-costs-pwa-${var.environment}"

  # Sin repositorio - deploy manual via CLI
  # Para conectar repo: agregar access_token de GitHub en variables

  build_spec = <<-YAML
    version: 1
    frontend:
      phases:
        build:
          commands:
            - echo "Static PWA - no build needed"
      artifacts:
        baseDirectory: /
        files:
          - '**/*'
      cache:
        paths: []
  YAML

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "200"
  }

  environment_variables = {
    ENVIRONMENT = var.environment
  }

  tags = local.common_tags
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.costs_pwa.id
  branch_name = "main"

  framework = "Web"
  stage     = "PRODUCTION"
}

# -----------------------------------------------------------------------------
# API Gateway para la PWA (backend)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "pwa_api" {
  name        = "${var.project_name}-pwa-api-${var.environment}"
  description = "API backend para PWA de costos"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id
  parent_id   = aws_api_gateway_rest_api.pwa_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "costs" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "costs"
}

resource "aws_api_gateway_method" "costs_get" {
  rest_api_id   = aws_api_gateway_rest_api.pwa_api.id
  resource_id   = aws_api_gateway_resource.costs.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "costs_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.pwa_api.id
  resource_id             = aws_api_gateway_resource.costs.id
  http_method             = aws_api_gateway_method.costs_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.pwa_api.invoke_arn
}

# CORS
resource "aws_api_gateway_method" "costs_options" {
  rest_api_id   = aws_api_gateway_rest_api.pwa_api.id
  resource_id   = aws_api_gateway_resource.costs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "costs_options" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id
  resource_id = aws_api_gateway_resource.costs.id
  http_method = aws_api_gateway_method.costs_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "costs_options" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id
  resource_id = aws_api_gateway_resource.costs.id
  http_method = aws_api_gateway_method.costs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "costs_options" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id
  resource_id = aws_api_gateway_resource.costs.id
  http_method = aws_api_gateway_method.costs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.costs_options]
}

resource "aws_api_gateway_deployment" "pwa" {
  rest_api_id = aws_api_gateway_rest_api.pwa_api.id

  depends_on = [
    aws_api_gateway_integration.costs_lambda,
    aws_api_gateway_integration.costs_options
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "pwa" {
  deployment_id = aws_api_gateway_deployment.pwa.id
  rest_api_id   = aws_api_gateway_rest_api.pwa_api.id
  stage_name    = var.environment
}

# -----------------------------------------------------------------------------
# Lambda - API Backend de la PWA
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "pwa_api" {
  function_name = "${var.project_name}-pwa-api-${var.environment}"
  role          = aws_iam_role.cost_report_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.pwa_api.output_path
  source_code_hash = data.archive_file.pwa_api.output_base64sha256

  environment {
    variables = {
      BUDGET_TOTAL       = var.budget_total
      ENVIRONMENT        = var.environment
      CROSS_ACCOUNT_ROLE = "arn:aws:iam::522189038734:role/datalake-cost-reader"
      CACHE_BUCKET       = "${var.project_name}-athena-results-${var.environment}"
      CALCULATOR_FN      = "${var.project_name}-cost-calculator-${var.environment}"
    }
  }

  tags = local.common_tags
}

data "archive_file" "pwa_api" {
  type        = "zip"
  output_path = "${path.module}/lambda/pwa_api.zip"
  source_dir  = "${path.module}/lambda/pwa_api_src"
}

resource "aws_lambda_permission" "pwa_api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pwa_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pwa_api.execution_arn}/*/*"
}

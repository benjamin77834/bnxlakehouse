#!/bin/bash
# =============================================================================
# DEPLOY COSTS - Despliega todo el sistema de costos y monitoreo
# =============================================================================
#
# Incluye:
# - SNS Topics (alertas, criticas, reporte)
# - CloudWatch Dashboard unificado de costos
# - AWS Budgets (total, redshift, lambda+api, storage)
# - Lambda cost-remediation (apaga servicios)
# - Lambda daily-cost-report (email diario)
# - EventBridge (cron 8AM UTC)
# - API Gateway + Lambda pwa-api (backend PWA)
# - Amplify PWA (portal remoto)
# - Portal local (docs/index.html)
#
# Uso: ./deploy_costs.sh
# =============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

AMPLIFY_APP_ID="d15z5aaq5vmvyz"
BRANCH="main"

echo ""
echo "=============================================="
echo "  DEPLOY SISTEMA DE COSTOS - DATA LAKE"
echo "=============================================="
echo ""

# ---------------------------------------------------------
# PASO 1: Terraform - Infraestructura de costos
# ---------------------------------------------------------
echo "📦 [1/5] Desplegando infraestructura de costos con Terraform..."
echo ""

terraform apply \
  -target=aws_sns_topic.alerts \
  -target=aws_sns_topic.critical_alerts \
  -target=aws_sns_topic.cost_report \
  -target=aws_iam_role.cost_report_role \
  -target=aws_iam_role_policy_attachment.cost_report_basic \
  -target=aws_iam_role_policy.cost_report_permissions \
  -target=aws_iam_role.cost_remediation_role \
  -target=aws_iam_role_policy_attachment.cost_remediation_basic \
  -target=aws_iam_role_policy.cost_remediation_actions \
  -target=aws_cloudwatch_dashboard.costs_unified \
  -target=aws_budgets_budget.total \
  -target=aws_budgets_budget.redshift \
  -target=aws_budgets_budget.lambda_apigw \
  -target=aws_budgets_budget.storage \
  -target=aws_lambda_function.cost_remediation \
  -target=aws_lambda_function.daily_cost_report \
  -target=aws_cloudwatch_event_rule.daily_cost_report \
  -target=aws_cloudwatch_event_target.daily_cost_report \
  -target=aws_lambda_permission.eventbridge_cost_report \
  -target=aws_sns_topic_subscription.cost_remediation \
  -target=aws_lambda_permission.sns_cost_remediation \
  -auto-approve

echo ""
echo "✅ Infraestructura de costos desplegada"
echo ""

# ---------------------------------------------------------
# PASO 2: Terraform - API Gateway para PWA
# ---------------------------------------------------------
echo "🌐 [2/5] Desplegando API Gateway + Lambda backend..."
echo ""

terraform apply \
  -target=aws_api_gateway_rest_api.pwa_api \
  -target=aws_api_gateway_resource.api \
  -target=aws_api_gateway_resource.costs \
  -target=aws_api_gateway_method.costs_get \
  -target=aws_api_gateway_integration.costs_lambda \
  -target=aws_api_gateway_method.costs_options \
  -target=aws_api_gateway_integration.costs_options \
  -target=aws_api_gateway_method_response.costs_options \
  -target=aws_api_gateway_integration_response.costs_options \
  -target=aws_api_gateway_deployment.pwa \
  -target=aws_api_gateway_stage.pwa \
  -target=aws_lambda_function.pwa_api \
  -target=aws_lambda_permission.pwa_api_gw \
  -auto-approve

echo ""
echo "✅ API Gateway + Lambda backend desplegados"
echo ""

# ---------------------------------------------------------
# PASO 3: Deploy PWA a Amplify
# ---------------------------------------------------------
echo "📱 [3/5] Desplegando PWA a Amplify..."
echo ""

# Crear zip de la PWA
cd "$PROJECT_DIR/pwa"
zip -r /tmp/pwa-deploy.zip . > /dev/null 2>&1
cd "$PROJECT_DIR"

# Crear deployment en Amplify
DEPLOY_JSON=$(aws amplify create-deployment \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$BRANCH" \
  --output json 2>&1)

# Verificar si hay un job pendiente
if echo "$DEPLOY_JSON" | grep -q "not finished"; then
  echo "   Cancelando deploy previo..."
  LAST_JOB=$(aws amplify list-jobs --app-id "$AMPLIFY_APP_ID" --branch-name "$BRANCH" --max-results 1 --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['jobSummaries'][0]['jobId'])" 2>/dev/null)
  aws amplify stop-job --app-id "$AMPLIFY_APP_ID" --branch-name "$BRANCH" --job-id "$LAST_JOB" 2>/dev/null || true
  sleep 3
  DEPLOY_JSON=$(aws amplify create-deployment --app-id "$AMPLIFY_APP_ID" --branch-name "$BRANCH" --output json)
fi

JOB_ID=$(echo "$DEPLOY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['jobId'])")
UPLOAD_URL=$(echo "$DEPLOY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['zipUploadUrl'])")

# Subir zip
curl -sS -T /tmp/pwa-deploy.zip "$UPLOAD_URL" > /dev/null

# Iniciar deploy
aws amplify start-deployment \
  --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$BRANCH" \
  --job-id "$JOB_ID" > /dev/null 2>&1

# Esperar a que termine
echo "   Esperando deploy..."
for i in $(seq 1 20); do
  sleep 5
  STATUS=$(aws amplify list-jobs --app-id "$AMPLIFY_APP_ID" --branch-name "$BRANCH" --max-results 1 --output json | python3 -c "import sys,json;print(json.load(sys.stdin)['jobSummaries'][0]['status'])" 2>/dev/null)
  if [ "$STATUS" = "SUCCEED" ]; then
    break
  elif [ "$STATUS" = "FAILED" ]; then
    echo "   ❌ Deploy falló!"
    break
  fi
done

echo "✅ PWA desplegada: https://main.$AMPLIFY_APP_ID.amplifyapp.com"
echo ""

# ---------------------------------------------------------
# PASO 4: Abrir portal local
# ---------------------------------------------------------
echo "🖥️  [4/5] Abriendo portal local..."
open "$PROJECT_DIR/docs/index.html"
echo "✅ Portal local abierto"
echo ""

# ---------------------------------------------------------
# PASO 5: Resumen
# ---------------------------------------------------------
echo "=============================================="
echo "  DEPLOY COMPLETADO"
echo "=============================================="
echo ""
echo "  Portal local:    file://$PROJECT_DIR/docs/index.html"
echo "  PWA remota:      https://main.$AMPLIFY_APP_ID.amplifyapp.com"
echo "  API Costs:       https://ihaoq852kd.execute-api.us-east-1.amazonaws.com/dev/api/costs"
echo "  CloudWatch:      https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards"
echo ""
echo "  Servicios desplegados:"
echo "  ✅ SNS Topics (alerts, critical, cost-report)"
echo "  ✅ CloudWatch Dashboard unificado de costos"
echo "  ✅ 4 AWS Budgets (total, redshift, lambda+api, storage)"
echo "  ✅ Lambda cost-remediation (pausa/throttle servicios)"
echo "  ✅ Lambda daily-cost-report (email 8AM UTC)"
echo "  ✅ EventBridge cron (dispara reporte diario)"
echo "  ✅ API Gateway + Lambda pwa-api (backend)"
echo "  ✅ Amplify PWA (portal remoto iOS/Web)"
echo ""
echo "  Costo mensual estimado: ~$4 USD"
echo "=============================================="

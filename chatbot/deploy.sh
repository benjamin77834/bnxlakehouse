#!/bin/bash
# =============================================================================
# DEPLOY CHATBOT RAG
# =============================================================================
# Uso: ./deploy.sh
# =============================================================================

set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

echo ""
echo "=============================================="
echo "  DEPLOY CHATBOT RAG - Bedrock + Knowledge Base"
echo "=============================================="
echo ""

echo "📦 [1/4] Inicializando Terraform..."
terraform init -input=false

echo ""
echo "🔍 [2/4] Validando configuración..."
terraform validate

echo ""
echo "🚀 [3/4] Desplegando infraestructura..."
terraform apply -auto-approve

echo ""
echo "📋 [4/4] Resumen:"
echo ""
terraform output

echo ""
echo "=============================================="
echo "  DEPLOY COMPLETADO"
echo "=============================================="
echo ""
echo "  Próximos pasos:"
echo "  1. Sube PDFs:  aws s3 cp *.pdf s3://$(terraform output -raw documents_bucket)/pdfs/ --profile sandboxaxel"
echo "  2. Sincroniza:  aws bedrock-agent start-ingestion-job --knowledge-base-id $(terraform output -raw knowledge_base_id) --data-source-id <DATA_SOURCE_ID> --region us-east-1 --profile sandboxaxel"
echo "  3. Pregunta:    curl -X POST $(terraform output -raw chatbot_api_url) -H 'Content-Type: application/json' -d '{\"question\": \"Hola\"}'"
echo ""
echo "  Costos: ~\$25-30/mes"
echo "    - OpenSearch Serverless: ~\$24/mes (0.5 OCU min)"
echo "    - Bedrock Haiku:         ~\$5-50/mes (según uso)"
echo "    - S3 + Lambda + API GW:  <\$1/mes"
echo "=============================================="

# =============================================================================
# Outputs
# =============================================================================

output "chatbot_api_url" {
  description = "URL del API del chatbot"
  value       = "${aws_api_gateway_stage.chatbot.invoke_url}/chat"
}

output "documents_bucket" {
  description = "Bucket S3 para subir PDFs"
  value       = aws_s3_bucket.documents.bucket
}

output "knowledge_base_id" {
  description = "ID de la Knowledge Base de Bedrock"
  value       = aws_bedrockagent_knowledge_base.chatbot.id
}

output "opensearch_endpoint" {
  description = "Endpoint de OpenSearch Serverless"
  value       = aws_opensearchserverless_collection.vectors.collection_endpoint
}

output "usage" {
  description = "Cómo usar el chatbot"
  value       = <<-EOT
    
    === CHATBOT RAG - Instrucciones ===
    
    1. Subir PDFs:
       aws s3 cp mi-documento.pdf s3://${aws_s3_bucket.documents.bucket}/pdfs/
    
    2. Sincronizar Knowledge Base (después de subir docs):
       aws bedrock-agent start-ingestion-job \
         --knowledge-base-id ${aws_bedrockagent_knowledge_base.chatbot.id} \
         --data-source-id ${aws_bedrockagent_data_source.pdfs.data_source_id}
    
    3. Hacer una pregunta:
       curl -X POST ${aws_api_gateway_stage.chatbot.invoke_url}/chat \
         -H "Content-Type: application/json" \
         -d '{"question": "¿De qué trata el documento?"}'
    
    4. Costos estimados: ~$25-30/mes (OpenSearch Serverless + Bedrock Haiku)
    
  EOT
}

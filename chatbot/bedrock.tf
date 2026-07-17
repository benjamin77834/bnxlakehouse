# =============================================================================
# Bedrock Knowledge Base + Data Source
# =============================================================================

resource "aws_bedrockagent_knowledge_base" "chatbot" {
  name     = "${var.project_name}-kb-${var.environment}"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.vectors.arn
      vector_index_name = "bedrock-knowledge-base-index"
      field_mapping {
        vector_field   = "vector"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = local.common_tags
}

# Data Source: PDFs en S3
resource "aws_bedrockagent_data_source" "pdfs" {
  name                 = "pdfs-source"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.chatbot.id
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.documents.arn
    }
  }
}

# =============================================================================
# CHATBOT RAG - Bedrock Knowledge Base + S3 + OpenSearch Serverless
# =============================================================================
#
# Chatbot que:
# 1. Inicialmente ingesta PDFs subidos a S3
# 2. Posterior conecta al data lake (Bronze/Silver/Gold) como fuente
# 3. Usa Bedrock Knowledge Bases (RAG) para responder preguntas
# 4. Expone via API Gateway + Lambda
#
# Costos estimados:
# - OpenSearch Serverless (vector store): ~$24/mes (0.5 OCU mínimo)
# - Bedrock Claude Haiku (invocaciones): ~$5-50/mes según uso
# - S3 (PDFs): <$1/mes
# - Lambda + API GW: <$1/mes (free tier)
# - Total mínimo: ~$25-30/mes
# =============================================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

variable "aws_region" {
  default = "us-east-1"
}

variable "aws_profile" {
  default = "sandboxaxel"
}

variable "project_name" {
  default = "bnx-chatbot"
}

variable "environment" {
  default = "dev"
}

variable "bedrock_model_id" {
  description = "Modelo de Bedrock para el chatbot"
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "current" {}

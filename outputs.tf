# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "s3_bucket_landing_arn" {
  description = "ARN del bucket S3 de landing zone"
  value       = aws_s3_bucket.data_lake_landing.arn
}

output "s3_bucket_bronze_arn" {
  description = "ARN del bucket S3 Bronze (Raw)"
  value       = aws_s3_bucket.data_lake_bronze.arn
}

output "s3_bucket_silver_arn" {
  description = "ARN del bucket S3 Silver (Curated)"
  value       = aws_s3_bucket.data_lake_silver.arn
}

output "s3_bucket_gold_arn" {
  description = "ARN del bucket S3 Gold (Augmented)"
  value       = aws_s3_bucket.data_lake_gold.arn
}

output "glue_catalog_database_name" {
  description = "Nombre de la base de datos en el Glue Data Catalog"
  value       = aws_glue_catalog_database.data_lake.name
}

output "glue_role_arn" {
  description = "ARN del rol IAM de Glue"
  value       = aws_iam_role.glue_role.arn
}

output "redshift_role_arn" {
  description = "ARN del rol IAM de Redshift"
  value       = aws_iam_role.redshift_role.arn
}

output "athena_role_arn" {
  description = "ARN del rol IAM de Athena"
  value       = aws_iam_role.athena_role.arn
}

output "athena_workgroup_name" {
  description = "Nombre del workgroup de Athena"
  value       = aws_athena_workgroup.data_lake.name
}

output "redshift_workgroup_endpoint" {
  description = "Endpoint del workgroup de Redshift Serverless"
  value       = aws_redshiftserverless_workgroup.data_lake.endpoint
}

output "redshift_namespace_id" {
  description = "ID del namespace de Redshift Serverless"
  value       = aws_redshiftserverless_namespace.data_lake.id
}

# AI/ML Outputs

output "sagemaker_role_arn" {
  description = "ARN del rol IAM de SageMaker"
  value       = aws_iam_role.sagemaker_role.arn
}

output "bedrock_role_arn" {
  description = "ARN del rol IAM de Bedrock"
  value       = aws_iam_role.bedrock_role.arn
}

output "sagemaker_artifacts_bucket_arn" {
  description = "ARN del bucket S3 para artefactos de SageMaker"
  value       = aws_s3_bucket.sagemaker_artifacts.arn
}

# Lambda, API Gateway & EKS Outputs

output "lambda_role_arn" {
  description = "ARN del rol IAM de Lambda"
  value       = aws_iam_role.lambda_role.arn
}

output "apigw_role_arn" {
  description = "ARN del rol IAM de API Gateway"
  value       = aws_iam_role.apigw_role.arn
}

output "eks_cluster_role_arn" {
  description = "ARN del rol IAM del cluster EKS"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "ARN del rol IAM de los nodos EKS"
  value       = aws_iam_role.eks_node_role.arn
}

# Streaming & Serving Outputs

output "msk_cluster_arn" {
  description = "ARN del cluster MSK (Kafka)"
  value       = aws_msk_cluster.data_lake.arn
}

output "msk_bootstrap_brokers_tls" {
  description = "Bootstrap brokers TLS para conectar a Kafka"
  value       = aws_msk_cluster.data_lake.bootstrap_brokers_tls
}

output "api_gateway_id" {
  description = "ID del API Gateway REST de salida"
  value       = aws_api_gateway_rest_api.data_lake_api.id
}

output "sagemaker_domain_id" {
  description = "ID del SageMaker Domain (Studio Unified)"
  value       = aws_sagemaker_domain.data_lake.id
}

output "lambda_serving_gold_arn" {
  description = "ARN de la Lambda de serving Gold"
  value       = aws_lambda_function.serving_gold.arn
}

output "lambda_serving_ml_arn" {
  description = "ARN de la Lambda de serving ML"
  value       = aws_lambda_function.serving_ml.arn
}

# Sandbox Outputs (solo si está habilitado)

output "sandbox_enabled" {
  description = "Si el sandbox está habilitado"
  value       = var.enable_sandbox
}

output "sandbox_bronze_bucket" {
  description = "Bucket Bronze del sandbox"
  value       = var.enable_sandbox ? aws_s3_bucket.sandbox_bronze[0].bucket : null
}

output "sandbox_athena_workgroup" {
  description = "Workgroup de Athena del sandbox"
  value       = var.enable_sandbox ? aws_athena_workgroup.sandbox[0].name : null
}

output "sandbox_redshift_endpoint" {
  description = "Endpoint de Redshift sandbox"
  value       = var.enable_sandbox ? aws_redshiftserverless_workgroup.sandbox[0].endpoint : null
}

# ECR Outputs

output "ecr_eks_services_url" {
  description = "URL del repositorio ECR para servicios EKS"
  value       = aws_ecr_repository.eks_services.repository_url
}

output "ecr_ai_agents_url" {
  description = "URL del repositorio ECR para agentes IA"
  value       = aws_ecr_repository.ai_agents.repository_url
}

output "ecr_ai_inference_url" {
  description = "URL del repositorio ECR para inferencia ML"
  value       = aws_ecr_repository.ai_inference.repository_url
}

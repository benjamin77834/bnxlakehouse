# -----------------------------------------------------------------------------
# Variables generales
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto (se usa como prefijo en los recursos)"
  type        = string
  default     = "datalake"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# -----------------------------------------------------------------------------
# Variables de Red (necesarias para Redshift)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID de la VPC donde se despliega Redshift"
  type        = string
}

variable "subnet_ids" {
  description = "Lista de subnet IDs para Redshift Serverless"
  type        = list(string)
}

variable "redshift_allowed_cidrs" {
  description = "CIDRs permitidos para conectarse a Redshift"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# -----------------------------------------------------------------------------
# Variables de Redshift
# -----------------------------------------------------------------------------

variable "redshift_db_name" {
  description = "Nombre de la base de datos en Redshift"
  type        = string
  default     = "datalake"
}

variable "redshift_admin_username" {
  description = "Usuario administrador de Redshift"
  type        = string
  default     = "admin"
}

variable "redshift_admin_password" {
  description = "Contraseña del administrador de Redshift"
  type        = string
  sensitive   = true
}

variable "redshift_base_capacity" {
  description = "Capacidad base de Redshift Serverless (en RPU)"
  type        = number
  default     = 32
}

# -----------------------------------------------------------------------------
# Variables de MSK (Kafka)
# -----------------------------------------------------------------------------

variable "msk_broker_nodes" {
  description = "Número de nodos broker de Kafka (debe ser múltiplo de AZs)"
  type        = number
  default     = 3
}

variable "msk_instance_type" {
  description = "Tipo de instancia para los brokers de Kafka"
  type        = string
  default     = "kafka.m5.large"
}

variable "msk_ebs_volume_size" {
  description = "Tamaño del volumen EBS por broker (GB)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Variables de Sandbox (opcional)
# -----------------------------------------------------------------------------

variable "enable_sandbox" {
  description = "Habilitar ambiente sandbox de pruebas aislado (true/false)"
  type        = bool
  default     = false
}

variable "sandbox_athena_scan_limit" {
  description = "Límite de bytes escaneados por query en Athena sandbox (100MB default)"
  type        = number
  default     = 104857600 # 100 MB
}

# -----------------------------------------------------------------------------
# Variables Multi-Cuenta
# -----------------------------------------------------------------------------

variable "enable_multi_account" {
  description = "Habilitar creación de cuentas separadas via AWS Organizations"
  type        = bool
  default     = false
}

variable "account_emails" {
  description = "Emails para cada cuenta (requerido si enable_multi_account = true)"
  type        = map(string)
  default = {
    sandbox = "sandbox@example.com"
    uat     = "uat@example.com"
    preprod = "preprod@example.com"
    prod    = "prod@example.com"
  }
}

# -----------------------------------------------------------------------------
# Variables de Control de Costos (Budgets)
# -----------------------------------------------------------------------------

variable "budget_total" {
  description = "Presupuesto mensual total en USD"
  type        = string
  default     = "5000"
}

variable "budget_redshift" {
  description = "Presupuesto mensual para Redshift en USD"
  type        = string
  default     = "2000"
}

variable "budget_lambda_api" {
  description = "Presupuesto mensual para Lambda + API Gateway en USD"
  type        = string
  default     = "500"
}

variable "budget_storage" {
  description = "Presupuesto mensual para S3 storage en USD"
  type        = string
  default     = "500"
}

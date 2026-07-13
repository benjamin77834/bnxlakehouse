# =============================================================================
# Amazon Neptune - Base de datos de grafos
# =============================================================================
#
# Neptune para modelar relaciones entre entidades del data lake:
# - Lineaje de datos (de dónde viene cada dato, transformaciones aplicadas)
# - Knowledge graphs para Bedrock RAG
# - Relaciones entre entidades de negocio
# =============================================================================

resource "aws_neptune_cluster" "data_lake" {
  count                               = length(var.subnet_ids) > 0 ? 1 : 0
  cluster_identifier                  = "${var.project_name}-neptune-${var.environment}"
  engine                              = "neptune"
  backup_retention_period             = 7
  preferred_backup_window             = "03:00-04:00"
  skip_final_snapshot                 = true
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_arn                         = aws_kms_key.data_lake.arn

  vpc_security_group_ids    = [aws_security_group.neptune[0].id]
  neptune_subnet_group_name = aws_neptune_subnet_group.data_lake[0].name

  tags = local.common_tags
}

resource "aws_neptune_cluster_instance" "data_lake" {
  count              = length(var.subnet_ids) > 0 ? var.neptune_instance_count : 0
  cluster_identifier = aws_neptune_cluster.data_lake[0].id
  instance_class     = var.neptune_instance_class
  engine             = "neptune"

  tags = local.common_tags
}

resource "aws_neptune_subnet_group" "data_lake" {
  count      = length(var.subnet_ids) > 0 ? 1 : 0
  name       = "${var.project_name}-neptune-subnet-${var.environment}"
  subnet_ids = var.subnet_ids

  tags = local.common_tags
}

resource "aws_security_group" "neptune" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  name        = "${var.project_name}-neptune-sg-${var.environment}"
  description = "Security group para Neptune"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = var.redshift_allowed_cidrs
    description = "Neptune Gremlin/SPARQL endpoint"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Amazon MSK (Managed Streaming for Apache Kafka) - Ingesta de eventos
# -----------------------------------------------------------------------------

resource "aws_msk_cluster" "data_lake" {
  count                  = length(var.subnet_ids) > 0 ? 1 : 0
  cluster_name           = "${var.project_name}-msk-${var.environment}"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.msk_broker_nodes

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk[0].id]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.project_name}-${var.environment}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_security_group" "msk" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  name        = "${var.project_name}-msk-sg-${var.environment}"
  description = "Security group para MSK (Kafka)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9092
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = var.redshift_allowed_cidrs
    description = "Kafka brokers (plaintext + TLS + SASL)"
  }

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = var.redshift_allowed_cidrs
    description = "Zookeeper"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Salida a internet"
  }

  tags = local.common_tags
}

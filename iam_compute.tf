# =============================================================================
# IAM Roles - Lambda, API Gateway & EKS (Kubernetes)
# =============================================================================
#
# Este archivo define los roles y políticas IAM para los servicios de cómputo
# y APIs que interactúan con el data lake.
#
# =============================================================================
# TABLA RESUMEN DE PERMISOS
# =============================================================================
#
# ┌─────────────────────┬──────────────────────────────┬─────────────────────────────────────────────────┬──────────────┐
# │ ROL                 │ POLÍTICA                     │ ACCIONES                                        │ RECURSO      │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ lambda_role         │ AWSLambdaBasicExecutionRole   │ (gestionada - logs:Create/PutLogEvents)         │ *            │
# │                     │ lambda_s3_access             │ s3:Get/PutObject, ListBucket, GetBucketLocation │ raw, proc,   │
# │                     │                              │                                                 │ curated      │
# │                     │ lambda_glue_access           │ glue:StartCrawler, StartJobRun, GetJob/Crawler  │ *            │
# │                     │                              │ GetJobRun, GetCrawler                           │              │
# │                     │ lambda_athena_access         │ athena:StartQueryExecution, GetQuery*            │ workgroup    │
# │                     │                              │ s3:Get/PutObject (resultados Athena)            │ athena-results│
# │                     │ lambda_sqs_sns               │ sqs:SendMessage, ReceiveMessage, DeleteMessage  │ *            │
# │                     │                              │ sns:Publish                                     │              │
# │                     │ lambda_vpc_access            │ ec2:CreateNetworkInterface, Describe/Delete      │ *            │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ apigw_role          │ apigw_cloudwatch             │ logs:Create/Describe/Put/Get/Filter/Delete       │ *            │
# │                     │ apigw_lambda_invoke          │ lambda:InvokeFunction                           │ account/*    │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ eks_cluster_role    │ AmazonEKSClusterPolicy       │ (gestionada - EKS control plane)                │ *            │
# │                     │ AmazonEKSVPCResourceCont..   │ (gestionada - VPC networking)                   │ *            │
# ├─────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────┼──────────────┤
# │ eks_node_role       │ AmazonEKSWorkerNodePolicy    │ (gestionada - nodo EKS)                         │ *            │
# │                     │ AmazonEKS_CNI_Policy         │ (gestionada - networking CNI)                   │ *            │
# │                     │ AmazonEC2ContainerRegistry.. │ (gestionada - pull imágenes ECR)                │ *            │
# │                     │ eks_node_s3_access           │ s3:GetObject, ListBucket, GetBucketLocation     │ raw, proc,   │
# │                     │                              │                                                 │ curated      │
# │                     │ eks_node_glue_access         │ glue:GetDatabase/Tables/Partitions              │ *            │
# └─────────────────────┴──────────────────────────────┴─────────────────────────────────────────────────┴──────────────┘
#
# =============================================================================

# =============================================================================
# LAMBDA
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Execution Role
# Permite a funciones Lambda procesar datos del data lake, disparar Glue
# crawlers/jobs, ejecutar queries en Athena y comunicarse via SQS/SNS.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Política gestionada - CloudWatch Logs (básico para cualquier Lambda)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda acceso a S3: leer y escribir datos en los buckets del data lake
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake_landing.arn,
          "${aws_s3_bucket.data_lake_landing.arn}/*",
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*"
        ]
      }
    ]
  })
}

# Lambda acceso a Glue: disparar crawlers y jobs de ETL
resource "aws_iam_role_policy" "lambda_glue_access" {
  name = "${var.project_name}-lambda-glue-access-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartCrawler",
          "glue:GetCrawler",
          "glue:GetCrawlerMetrics",
          "glue:StartJobRun",
          "glue:GetJob",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Lambda acceso a Athena: ejecutar queries ad-hoc desde funciones
resource "aws_iam_role_policy" "lambda_athena_access" {
  name = "${var.project_name}-lambda-athena-access-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup"
        ]
        Resource = [
          aws_athena_workgroup.data_lake.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartitions"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Lambda acceso a SQS/SNS: comunicación entre servicios y notificaciones
resource "aws_iam_role_policy" "lambda_sqs_sns" {
  name = "${var.project_name}-lambda-sqs-sns-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-*"
        ]
      }
    ]
  })
}

# Lambda acceso VPC: necesario si Lambda corre dentro de una VPC
# para acceder a Redshift u otros recursos privados
resource "aws_iam_role_policy" "lambda_vpc_access" {
  name = "${var.project_name}-lambda-vpc-access-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Lambda acceso a MSK/Kafka: consumir eventos de topics
resource "aws_iam_role_policy" "lambda_msk_access" {
  name = "${var.project_name}-lambda-msk-access-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:DescribeClusterV2",
          "kafka:GetBootstrapBrokers",
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeClusterDynamicConfiguration"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# Lambda acceso a SageMaker Runtime: invocar endpoints de inferencia
resource "aws_iam_role_policy" "lambda_sagemaker_invoke" {
  name = "${var.project_name}-lambda-sagemaker-invoke-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint",
          "sagemaker:InvokeEndpointAsync"
        ]
        Resource = [
          "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:endpoint/${var.project_name}-*"
        ]
      }
    ]
  })
}

# =============================================================================
# API GATEWAY
# =============================================================================

# -----------------------------------------------------------------------------
# API Gateway Role
# Permite a API Gateway escribir logs en CloudWatch e invocar funciones Lambda.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "apigw_role" {
  name = "${var.project_name}-apigw-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# API Gateway puede escribir logs en CloudWatch (access logs, execution logs)
resource "aws_iam_role_policy" "apigw_cloudwatch" {
  name = "${var.project_name}-apigw-cloudwatch-${var.environment}"
  role = aws_iam_role.apigw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# API Gateway puede invocar funciones Lambda (integración backend)
resource "aws_iam_role_policy" "apigw_lambda_invoke" {
  name = "${var.project_name}-apigw-lambda-invoke-${var.environment}"
  role = aws_iam_role.apigw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
        ]
      }
    ]
  })
}

# =============================================================================
# EKS (Kubernetes)
# =============================================================================

# -----------------------------------------------------------------------------
# EKS Cluster Role
# Rol para el plano de control de EKS. Permite a EKS gestionar el cluster,
# networking y recursos asociados.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Política gestionada - permisos del control plane de EKS
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Política gestionada - permisos de networking VPC para EKS
resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# -----------------------------------------------------------------------------
# EKS Node Group Role
# Rol para los worker nodes (EC2) del cluster EKS. Permite a los nodos
# unirse al cluster, descargar imágenes y acceder al data lake.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-eks-node-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Política gestionada - permisos base de worker node
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Política gestionada - CNI plugin para networking de pods
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Política gestionada - pull de imágenes desde ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Nodos EKS acceso a S3: pods pueden leer datos del data lake
resource "aws_iam_role_policy" "eks_node_s3_access" {
  name = "${var.project_name}-eks-node-s3-access-${var.environment}"
  role = aws_iam_role.eks_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake_bronze.arn,
          "${aws_s3_bucket.data_lake_bronze.arn}/*",
          aws_s3_bucket.data_lake_silver.arn,
          "${aws_s3_bucket.data_lake_silver.arn}/*",
          aws_s3_bucket.data_lake_gold.arn,
          "${aws_s3_bucket.data_lake_gold.arn}/*"
        ]
      }
    ]
  })
}

# Nodos EKS acceso a Glue Catalog: pods pueden leer schemas de tablas
resource "aws_iam_role_policy" "eks_node_glue_access" {
  name = "${var.project_name}-eks-node-glue-access-${var.environment}"
  role = aws_iam_role.eks_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = ["*"]
      }
    ]
  })
}

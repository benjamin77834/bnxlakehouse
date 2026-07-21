# =============================================================================
# Lambda Cost Calculator - Calcula costos escaneando recursos activos
# No usa Cost Explorer API - calcula directo recurso × precio × horas
# =============================================================================

resource "aws_lambda_function" "cost_calculator" {
  function_name = "${var.project_name}-cost-calculator-${var.environment}"
  role          = aws_iam_role.cost_calculator_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.cost_calculator.output_path
  source_code_hash = data.archive_file.cost_calculator.output_base64sha256

  tags = local.common_tags
}

data "archive_file" "cost_calculator" {
  type        = "zip"
  output_path = "${path.module}/lambda/cost_calculator.zip"
  source_dir  = "${path.module}/lambda/cost_calculator_src"
}

resource "aws_iam_role" "cost_calculator_role" {
  name = "${var.project_name}-cost-calculator-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cost_calc_basic" {
  role       = aws_iam_role.cost_calculator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cost_calc_read" {
  name = "${var.project_name}-cost-calc-read-${var.environment}"
  role = aws_iam_role.cost_calculator_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeNatGateways",
        "neptune:DescribeDBClusters",
        "neptune:DescribeDBInstances",
        "redshift-serverless:ListWorkgroups",
        "opensearchserverless:ListCollections",
        "sagemaker:ListEndpoints",
        "sagemaker:DescribeEndpoint",
        "elasticloadbalancing:DescribeLoadBalancers",
        "rds:DescribeDBInstances",
        "kafka:ListClusters",
        "eks:ListClusters",
        "elasticache:DescribeCacheClusters",
        "s3:ListAllMyBuckets",
        "cloudwatch:ListDashboards",
        "cloudwatch:PutMetricData",
        "cloudtrail:LookupEvents"
      ]
      Resource = ["*"]
    }]
  })
}

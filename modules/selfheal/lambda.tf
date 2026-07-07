data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Empacota o código Python (só stdlib + boto3, que já vem no runtime Lambda)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/build/selfheal-lambda.zip"
}

# Trust policy: apenas o serviço Lambda pode assumir esta role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-selfheal-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# Permissões: logs, DynamoDB (cooldown) e sts:GetCallerIdentity
# (usado para gerar o token de autenticação do EKS, no mesmo esquema do aws-iam-authenticator)
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
    ]
    resources = [aws_dynamodb_table.cooldown.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name_prefix}-selfheal-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# Necessária para o Lambda criar/gerenciar ENIs quando anexado a uma VPC
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-selfheal"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "selfheal" {
  function_name    = "${var.name_prefix}-selfheal"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 15
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CLUSTER_NAME        = var.cluster_name
      CLUSTER_ENDPOINT    = var.cluster_endpoint
      CLUSTER_CA          = var.cluster_ca
      NAMESPACE           = var.namespace
      ALLOWED_DEPLOYMENTS = join(",", var.target_deployments)
      WEBHOOK_USERNAME    = var.webhook_username
      WEBHOOK_PASSWORD    = var.webhook_password
      COOLDOWN_SECONDS    = tostring(var.cooldown_seconds)
      COOLDOWN_TABLE      = aws_dynamodb_table.cooldown.name
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy_attachment.lambda_vpc,
  ]
}

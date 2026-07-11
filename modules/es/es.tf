# Criar External Secrets
locals {
  namespace      = "external-secrets"
  sa_name        = "${var.name_prefix}-external-secrets-sa"
  oidc_subject   = "${var.oidc_provider_url}:sub"
  oidc_audience  = "${var.oidc_provider_url}:aud"
}

# Namespace dedicado
resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = local.namespace
  }
}

# IAM Policy para acesso ao Secrets Manager e SSM
resource "aws_iam_policy" "external_secrets" {
  name        = "${var.name_prefix}-external-secrets-policy"
  description = "Permite ao External Secrets Operator ler segredos da AWS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.name_prefix}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.name_prefix}/*"
      }
    ]
  })
}

# IAM Role com IRSA (IAM Roles for Service Accounts)
resource "aws_iam_role" "external_secrets" {
  name = "${var.name_prefix}-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_subject}"  = "system:serviceaccount:${local.namespace}:${local.sa_name}"
          "${local.oidc_audience}" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# Helm chart do External Secrets Operator
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version != "" ? var.chart_version : null
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name

  disable_openapi_validation = true

  set = [
    {
      name  = "serviceAccount.name"
      value = local.sa_name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_secrets.arn
    }
  ]

  depends_on = [
    kubernetes_namespace_v1.external_secrets,
    aws_iam_role_policy_attachment.external_secrets
  ]
}
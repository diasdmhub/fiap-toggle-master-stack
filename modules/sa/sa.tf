locals {
  service_account_name = "${var.name_prefix}-serv-acc"
  role_name            = "${var.name_prefix}-role"
  policy_name          = "${var.name_prefix}-extra-policy"

  # Remove o prefixo "https://" da URL caso venha com ele
  oidc_url = trimprefix(var.oidc_provider_url, "https://")
}

# Política extra da aplicação (equivalente ao toggle-policy.json da fase 2)
resource "aws_iam_policy" "extra" {
  name   = local.policy_name
  policy = templatefile("${path.module}/toggle-policy.json", {
    account_id = data.aws_caller_identity.current.account_id
  })
}

# Role IAM com trust policy IRSA
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${local.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [
        "system:serviceaccount:keda:keda-operator",
        "system:serviceaccount:keda:keda-metrics-server",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
}

# Políticas gerenciadas AWS
locals {
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(local.managed_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "extra" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.extra.arn
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }
}

# Service Account Kubernetes com anotação da role
resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = local.service_account_name
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }
  }
}

data "aws_caller_identity" "current" {}
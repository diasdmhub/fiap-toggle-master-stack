locals {
  k8s_username = "${var.name_prefix}-selfheal-lambda"
}

# Mapeia a role IAM do Lambda como uma identidade autenticável no cluster
# (equivalente a uma entrada no aws-auth ConfigMap, mas via API de Access Entries).
resource "aws_eks_access_entry" "lambda" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.lambda.arn
  type          = "STANDARD"
  user_name     = local.k8s_username
}

# Role Kubernetes restrita: get/patch apenas nos 4 Deployments alvo, nada mais.
resource "kubernetes_role_v1" "selfheal" {
  metadata {
    name      = "${var.name_prefix}-selfheal-restart"
    namespace = var.namespace
  }

  rule {
    api_groups     = ["apps"]
    resources      = ["deployments"]
    resource_names = var.target_deployments
    verbs          = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "selfheal" {
  metadata {
    name      = "${var.name_prefix}-selfheal-restart-binding"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.selfheal.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = local.k8s_username
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [aws_eks_access_entry.lambda]
}

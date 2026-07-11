resource "kubernetes_namespace_v1" "keda" {
  metadata {
    name = "keda"
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.chart_version != "" ? var.chart_version : null
  namespace  = kubernetes_namespace_v1.keda.metadata[0].name

  disable_openapi_validation = true

  set = [
    {
      name  = "watchNamespace"
      value = ""  # vazio = monitora todos os namespaces
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.role_arn
    }
  ]

  depends_on = [kubernetes_namespace_v1.keda]
}
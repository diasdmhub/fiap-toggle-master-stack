output "keda_namespace" {
  description = "Namespace onde o KEDA foi instalado"
  value       = kubernetes_namespace_v1.keda.metadata[0].name
}
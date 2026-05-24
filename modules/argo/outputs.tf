output "argocd_ip" {
  description = "IP do servico LoadBalancer do ArgoCD (só existe se o service_type for LoadBalancer)"
  value       = var.service_type == "LoadBalancer" ? try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].ip, null) : "N/A - Using ClusterIP"
}

output "argocd_url" {
  description = "URL para a API do ArgoCD (só existe se o service_type for LoadBalancer)"
  value       = var.service_type == "LoadBalancer" ? try("http://${data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname}", null) : "N/A - Using ClusterIP"
}

output "namespace" {
  description = "Namespace para o ArgoCD"
  value       = helm_release.argocd.namespace
}

output "argocd_version" {
  description = "Deployed ArgoCD Helm chart version"
  value       = helm_release.argocd.version
}
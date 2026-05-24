variable "chart_version" {
  description = "Versao do Helm chart para o Argo CD (vazio para latest)"
  type        = string
  default     = ""
}

variable "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  type        = string
}

variable "cluster_ca" {
  description = "Certificado do cluster EKS (base64)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "service_type" {
  description = "Tipo de serviço para o ArgoCD (ClusterIP ou LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}
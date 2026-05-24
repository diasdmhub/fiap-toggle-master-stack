variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "chart_version" {
  description = "Versão do Helm chart do KEDA (vazio para latest)"
  type        = string
  default     = ""
}

variable "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  type        = string
}

variable "cluster_ca" {
  description = "Certificado CA do cluster EKS (base64)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "role_arn" {
  description = "IAM Role ARN para anotação IRSA do Keda"
  type        = string
}
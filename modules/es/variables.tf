variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "chart_version" {
  description = "Versão do Helm chart do External Secrets (vazio para latest)"
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

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster EKS (para IRSA)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL do OIDC provider do cluster EKS (para IRSA)"
  type        = string
}
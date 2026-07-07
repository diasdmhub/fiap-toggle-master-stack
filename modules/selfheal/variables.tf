variable "name_prefix" {
  description = "Prefixo para nomear os recursos"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes onde os deployments dos microserviços estão"
  type        = string
  default     = "toggle"
}

variable "target_deployments" {
  description = "Nomes dos Deployments que o Lambda tem permissão de reiniciar"
  type        = list(string)
  default     = ["auth-service", "flag-service", "targeting-service", "evaluation-service"]
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  type        = string
}

variable "cluster_ca" {
  description = "Certificate authority (base64) do cluster EKS"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group do control plane do EKS (para liberar ingress do Lambda)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster roda"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde o Lambda será anexado (mesma VPC do EKS)"
  type        = list(string)
}

variable "webhook_username" {
  description = "Usuário HTTP Basic Auth exigido do contact point webhook do Grafana"
  type        = string
  default     = "grafana-selfheal"
}

variable "webhook_password" {
  description = "Senha HTTP Basic Auth exigida do contact point webhook do Grafana"
  type        = string
  sensitive   = true
}

variable "cooldown_seconds" {
  description = "Janela mínima entre dois restarts consecutivos do mesmo serviço"
  type        = number
  default     = 300
}

variable "log_retention_days" {
  description = "Retenção do CloudWatch Logs do Lambda"
  type        = number
  default     = 14
}

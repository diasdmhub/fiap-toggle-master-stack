variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
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

variable "namespace" {
  description = "Namespace Kubernetes onde os microserviços do ToggleMaster rodam"
  type        = string
  default     = "toggle"
}

variable "prometheus_chart_version" {
  description = "Versão do Helm chart kube-prometheus-stack (vazio para latest)"
  type        = string
  default     = ""
}

variable "loki_chart_version" {
  description = "Versão do Helm chart do Loki (vazio para latest)"
  type        = string
  default     = ""
}

variable "otel_chart_version" {
  description = "Versão do Helm chart do OpenTelemetry Collector (vazio para latest)"
  type        = string
  default     = ""
}

variable "tempo_chart_version" {
  description = "Versão do Helm chart do Grafana Tempo (vazio para latest)"
  type        = string
  default     = ""
}

variable "grafana_pass" {
  description = "Senha do usuário admin do Grafana"
  type        = string
  sensitive   = true
}

variable "grafana_service_type" {
  description = "Tipo de serviço do Grafana (ClusterIP ou LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

# Self-healing
#############################
variable "selfheal_target_deployments" {
  description = "Deployments monitorados pela regra de alerta de self-healing"
  type        = list(string)
}
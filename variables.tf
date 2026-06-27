########################
# Variáveis principais #
########################
variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
  default     = "fiap-toggle"
}

variable "aws_region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-1"
}


#############################
# Variáveis personalizáveis #
#############################

# Variáveis da VPC
#############################
variable "subnet_prefix" {
  description = "Os 2 primeiros octetos do CIDR da VPC"
  type        = string
}

variable "public_subnet_nums" {
  description = "O terceiro octeto para subnets públicas - um por AZ"
  type        = list(number)
  default     = [11, 21, 31, 41, 51, 61]
}

variable "private_subnet_nums" {
  description = "O terceiro octeto para subnets privadas - um por AZ"
  type        = list(number)
  default     = [12, 22, 32, 42, 52, 62]
}

# Variáveis do RDS
#############################
# DEFINA AS CREDENCIAIS DO DB AQUI
variable "db_name" {
  description = "Nome do banco de dados inicial no RDS"
  type        = string
}

variable "db_username" {
  description = "Usuário master do PostgreSQL"
  type        = string
}

variable "db_password" {
  description = "Senha do usuário master (defina uma variável de ambiente)"
  type        = string
  sensitive   = true
}

# Variáveis do CI git
#############################
# URL defaults to GitHub
variable "git_domain" {
  description = "Domínio provedor Git"
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "git_org" {
  description = "Conta do provedor Git"
  type        = string
}

variable "git_repo" {
  description = "Repositório do provedor Git"
  type        = string
}

# Variáveis do ArgoCD
#############################
variable "chart_version" {
  description = "Versao do Helm chart para o Argo CD (vazio para latest)"
  type        = string
  default     = ""
}

variable "service_type" {
  description = "Tipo de serviço para o ArgoCD (ClusterIP ou LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

# Variáveis do External Secrets
#############################
variable "external_secrets_chart_version" {
  description = "Versão do Helm chart do External Secrets Operator (vazio para latest)"
  type        = string
  default     = ""
}

# Variáveis do Keda
#############################
variable "keda_chart_version" {
  description = "Versão do Helm chart do KEDA (vazio para latest)"
  type        = string
  default     = ""
}

# Variáveis do Service Acc
#############################
variable "namespace" {
  description = "Namespace Kubernetes da aplicação"
  type        = string
  default     = "toggle"
}

# Variáveis do Monitoring Stack
#############################
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
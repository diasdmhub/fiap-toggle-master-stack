# Outputs de todos os módulos
output "vpc_outputs" {
  value       = module.vpc
  description = "Outputs do modulo VPC"
}

output "eks_outputs" {
  value       = module.eks
  description = "Outputs do modulo EKS"
}

output "rds_outputs" {
  value       = module.rds
  description = "Outputs do modulo RDS"
  sensitive   = true
}

output "cache_outputs" {
  value       = module.cache
  description = "Outputs do modulo Cache"
}

output "dynamo_outputs" {
  value       = module.dynamo
  description = "Outputs do modulo Dynamo"
}

output "ecr_outputs" {
  value       = module.ecr
  description = "Outputs do modulo ECR"
}

output "sqs_outputs" {
  value       = module.sqs
  description = "Outputs do modulo SQS"
}

output "oidc_outputs" {
  value       = module.oidc
  description = "Outputs do modulo OIDC"
}

output "argocd_outputs" {
  value       = module.argo
  description = "Outputs do modulo Argo"
}

output "es_outputs" {
  value       = module.es
  description = "Outputs do modulo External Secrets (ES)"
}

output "sa_outputs" {
  value       = module.sa
  description = "Outputs do modulo Service Account (SA)"
}

output "keda_outputs" {
  value       = module.keda
  description = "Outputs do modulo Keda"
}

output "secrets_outputs" {
  value       = module.secrets
  description = "Outputs do modulo Secrets"
}

output "monitoring_outputs" {
  value       = module.mon
  description = "Outputs do módulo Monitoring Stack"
}

output "selfheal_outputs" {
  value       = module.selfheal
  description = "Outputs do módulo Self-Healing (Lambda + API Gateway)"
}
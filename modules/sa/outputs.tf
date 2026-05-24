output "service_account_name" {
  description = "Nome da service account criada no Kubernetes"
  value       = kubernetes_service_account_v1.this.metadata[0].name
}

output "role_arn" {
  description = "ARN da IAM Role associada à service account"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nome da IAM Role"
  value       = aws_iam_role.this.name
}
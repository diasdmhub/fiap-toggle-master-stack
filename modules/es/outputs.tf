output "external_secrets_role_name" {
  description = "Nome do IAM Role usado pelo External Secrets Operator"
  value       = local.sa_name
}

output "external_secrets_role_arn" {
  description = "ARN do IAM Role usada pelo External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}
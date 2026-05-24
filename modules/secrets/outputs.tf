output "rds_secret_arn" {
  description = "ARN do secret do RDS no Secrets Manager"
  value       = aws_secretsmanager_secret.rds.arn
}

output "sqs_secret_arn" {
  description = "ARN do secret do SQS no Secrets Manager"
  value       = aws_secretsmanager_secret.sqs.arn
}

output "valkey_secret_arn" {
  description = "ARN do secret do Valkey no Secrets Manager"
  value       = aws_secretsmanager_secret.valkey.arn
}

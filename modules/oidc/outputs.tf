# Output do ARN para uso no git Actions
output "git_actions_role_arn" {
  value       = aws_iam_role.git_actions.arn
  description = "ARN do Git Actions IAM role"
}

output "git_actions_role_name" {
  value       = aws_iam_role.git_actions.name
  description = "Nome da Git Actions IAM role"
}
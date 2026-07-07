output "webhook_url" {
  description = "URL a ser configurada no Contact Point 'webhook' do Grafana"
  value       = "${aws_apigatewayv2_api.this.api_endpoint}/selfheal"
}

output "lambda_function_name" {
  description = "Nome da função Lambda de self-healing"
  value       = aws_lambda_function.selfheal.function_name
}

output "lambda_role_arn" {
  description = "ARN da IAM Role do Lambda (para referência/troubleshooting no EKS)"
  value       = aws_iam_role.lambda.arn
}

output "cooldown_table_name" {
  description = "Nome da tabela DynamoDB de cooldown"
  value       = aws_dynamodb_table.cooldown.name
}

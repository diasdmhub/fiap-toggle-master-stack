output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = aws_sqs_queue.toggle.url
}
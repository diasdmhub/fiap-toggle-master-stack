# Criar fila SQS
resource "aws_sqs_queue" "toggle" {
  name = "${var.name_prefix}-sqs-queue"

  visibility_timeout_seconds = 30
  message_retention_seconds  = 3600
}
# Secrets usados pelos ExternalSecrets do K8s para injetar variáveis sensíveis

# RDS URL de conexão PostgreSQL - kube/010-secrets-db.yaml
resource "aws_secretsmanager_secret" "rds" {
  name        = "${var.name_prefix}/rds"
  description = "URL completa de conexão PostgreSQL pronta para uso"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-secret-rds"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    db_url = var.rds_connection_url
  })
}

# SQS URL da fila de mensagens - kube/020-secrets-sqs.yaml
resource "aws_secretsmanager_secret" "sqs" {
  name        = "${var.name_prefix}/sqs"
  description = "URL da fila SQS"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-secret-sqs"
  }
}

resource "aws_secretsmanager_secret_version" "sqs" {
  secret_id = aws_secretsmanager_secret.sqs.id
  secret_string = jsonencode({
    queue_url = var.sqs_queue_url
  })
}

# Valkey URL de conexão Redis - kube/060-evaluation-service/062-secrets.yaml
resource "aws_secretsmanager_secret" "valkey" {
  name        = "${var.name_prefix}/redis_url"
  description = "String de conexão completa para o Valkey"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.name_prefix}-secret-valkey"
  }
}

resource "aws_secretsmanager_secret_version" "valkey" {
  secret_id = aws_secretsmanager_secret.valkey.id
  secret_string = jsonencode({
    # Usa o schema "rediss://" conforme esperado pelo evaluation-service
    redis_url = "rediss://${var.valkey_connection_string}"
  })
}
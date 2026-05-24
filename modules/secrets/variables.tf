variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "rds_connection_url" {
  description = "URL completa de conexão PostgreSQL pronta para uso"
  type        = string
  sensitive   = true
}

variable "sqs_queue_url" {
  description = "URL da fila SQS"
  type        = string
}

variable "valkey_connection_string" {
  description = "String de conexão completa para o Valkey"
  type        = string
}
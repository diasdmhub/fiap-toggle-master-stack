# Tabela usada apenas para evitar restarts em loop:
# guarda o timestamp do último restart de cada serviço e um TTL de auto-limpeza.
resource "aws_dynamodb_table" "cooldown" {
  name         = "${var.name_prefix}-selfheal-cooldown"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "service_name"

  attribute {
    name = "service_name"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

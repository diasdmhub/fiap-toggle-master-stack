# Criar a tabela do DynamoDB
resource "aws_dynamodb_table" "toggle" {
  name         = "${var.name_prefix}-dynamo-table"
  billing_mode = "PROVISIONED"
  hash_key = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  read_capacity  = 1
  write_capacity = 1
}
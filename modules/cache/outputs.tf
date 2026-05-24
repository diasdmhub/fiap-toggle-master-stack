output "elasticache_valkey_endpoint" {
  description = "Endpoint do ElastiCache Valkey cache"
  value       = aws_elasticache_serverless_cache.valkey.endpoint[0].address
}

output "elasticache_valkey_port" {
  description = "Porta do ElastiCache Valkey cache"
  value       = aws_elasticache_serverless_cache.valkey.endpoint[0].port
}

output "elasticache_valkey_connection_string" {
  description = "String de conexão completa para o Valkey"
  value       = "${aws_elasticache_serverless_cache.valkey.endpoint[0].address}:${aws_elasticache_serverless_cache.valkey.endpoint[0].port}"
}
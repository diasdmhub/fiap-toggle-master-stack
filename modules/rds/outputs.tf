output "rds_endpoint" {
  description = "Endpoint do RDS (hostname:porta)"
  value       = aws_db_instance.main.endpoint
}

output "rds_connection_url" {
  description = "URL completa de conexão PostgreSQL pronta para uso"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.endpoint}/${var.db_name}"
  sensitive   = true
}

output "rds_security_group_id" {
  description = "ID do Security Group do RDS"
  value       = aws_security_group.rds.id
}
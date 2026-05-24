variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados inicial no RDS"
  type        = string
  default     = "toggle_db"
}

variable "db_username" {
  description = "Usuário master do PostgreSQL"
  type        = string
  default     = "toggle"
}

variable "db_password" {
  description = "Senha do usuário master (use variável de ambiente para produção)"
  type        = string
  default     = "toggle_dbmaster"
  sensitive   = true
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC (usado no Security Group)"
  type        = string
}
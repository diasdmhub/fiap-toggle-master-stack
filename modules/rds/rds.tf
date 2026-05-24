# Subnet Group (usa as subnets privadas da VPC)
resource "aws_db_subnet_group" "rds" {
  name       = "${var.name_prefix}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-rds-subnet-group"
  }

  # Depende da VPC e subnets privadas
#  depends_on = [aws_vpc.main, aws_subnet.private]
}

# Security Group do RDS
# - Permite tráfego na porta 5432 de qualquer IP da VPC
# - Garante que os nodes EC2 do EKS consigam conectar ao DB
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Security Group para o RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "Acesso ao PostgreSQL pelos nodes EKS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }
}

# Instância RDS PostgreSQL
resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-rds-psql"

  engine               = "postgres"
  engine_version       = "18"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp3"
  max_allocated_storage = null

  # Database inicial
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Associação às subnets privadas
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Sem backup automático
  backup_retention_period = 0
  skip_final_snapshot     = true

  # Sem Performance Insights
  performance_insights_enabled = false

  # Tags
  tags = {
    Name = "${var.name_prefix}-rds-psql"
  }

  # Dependências explícitas
  depends_on = [aws_db_subnet_group.rds, aws_security_group.rds]
}
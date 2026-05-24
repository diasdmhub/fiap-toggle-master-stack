# Security Group para o Valkey a partir da VPC
resource "aws_security_group" "valkey" {
  name        = "${var.name_prefix}-valkey-sg"
  vpc_id      = var.vpc_id
  description = "Security Group para o Valkey a partir da VPC"

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Acesso ao Valkey a partir da VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Permite todo o trafego de saida"
  }

  tags = {
    Name = "${var.name_prefix}-valkey-sg"
  }
}

# Instância Valkey Serveless
resource "aws_elasticache_serverless_cache" "valkey" {
  name = "${var.name_prefix}-valkey"
  engine         = "valkey"
  description    = "Valkey cache para EKS"

  # Configuração mínima de scaling automático
  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }

  # IDs das subnets privadas - min 2, max 3
  subnet_ids         = slice(var.private_subnet_ids, 0, min(length(var.private_subnet_ids), 3))
  security_group_ids = [aws_security_group.valkey.id]
  
  # Backups automáticos desnecessários para teste
  snapshot_retention_limit = 0

  tags = {
    Name = "${var.name_prefix}-valkey"
  }
}
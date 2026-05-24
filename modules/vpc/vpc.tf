# Busca todas AZs da região
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  vpc_cidr = "${var.subnet_prefix}.0.0/16"

  # Lista de AZs limitada às 4 primeiras para suportar o control-plane
  azs         = data.aws_availability_zones.available.names
  cp_az_count = length(local.azs) < 2 ? error("Pelo menos 2 AZs são necessárias para o control plane EKS") : min(length(local.azs), 4)
  cp_azs      = slice(local.azs, 0, local.cp_az_count)

  # CIDR de subnets públicas (octeto 3 distinto)
  public_subnet_cidrs = [
    for i in range(local.cp_az_count) :
    "${var.subnet_prefix}.${var.public_subnet_nums[i]}.0/24"
  ]

  # CIDR de subnets privadas (octeto 3 distinto)
  private_subnet_cidrs = [
    for i in range(local.cp_az_count) :
    "${var.subnet_prefix}.${var.private_subnet_nums[i]}.0/24"
  ]
}

# Criação da VPC com atributos DNS
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Subnets públicas (uma por AZ) com IP público
resource "aws_subnet" "public" {
  count                   = length(local.cp_azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.cp_azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet-pub-${var.public_subnet_nums[count.index]}"
    Tier = "public"
    AZ   = local.cp_azs[count.index]
    "kubernetes.io/role/elb"                               = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks-cluster" = "shared"
  }
}

# Subnets públicas (uma por AZ) sem IP público
resource "aws_subnet" "private" {
  count                   = length(local.cp_azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.cp_azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-subnet-priv-${var.private_subnet_nums[count.index]}"
    Tier = "private"
    AZ   = local.cp_azs[count.index]
    "kubernetes.io/role/internal-elb"                      = "1"
    "kubernetes.io/cluster/${var.name_prefix}-eks-cluster" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Tag da route table automática da VPC
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = {
    Name = "${var.name_prefix}-auto-main-rtb"
  }
}

# Route table pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-public-rtb"
  }
}

# Route table privada
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-private-rtb"
  }
}

# Incluir a rota default (0.0.0.0/0) via IGW na route table pública
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associar subnets públicas com a route table pública
resource "aws_route_table_association" "public" {
  count          = length(local.cp_azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associar subnets privadas com a route table privada
resource "aws_route_table_association" "private" {
  count          = length(local.cp_azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Elastic IP para o NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway na subnet pública
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # Coloca em uma subnet pública

  tags = {
    Name = "${var.name_prefix}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# Rota default na route table privada via NAT Gateway
resource "aws_route" "private_internet_access" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
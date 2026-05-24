output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of all public subnet IDs (in AZ order)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of all private subnet IDs (in AZ order)"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "availability_zones" {
  description = "Availability zones used for subnets"
  value       = local.azs
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = local.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = local.private_subnet_cidrs
}
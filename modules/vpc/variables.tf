variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "subnet_prefix" {
  description = "Os 2 primeiros octetos do CIDR da VPC"
  type        = string
  default     = "10.12"
}

variable "public_subnet_nums" {
  description = "O terceiro octeto para subnets públicas - um por AZ"
  type        = list(number)
  default     = [11, 21, 31, 41, 51, 61]
}

variable "private_subnet_nums" {
  description = "O terceiro octeto para subnets privadas - um por AZ"
  type        = list(number)
  default     = [12, 22, 32, 42, 52, 62]
}
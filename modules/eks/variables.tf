variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas (para control plane)"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs das subnets públicas (para node group)"
  type        = list(string)
}
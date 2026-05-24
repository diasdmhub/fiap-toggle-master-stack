variable "name_prefix" {
  description = "Prefixo do nome dos recursos"
  type        = string
}

variable "service_list" {
  description = "Lista de nomes de serviços para os repositórios ECR"
  type        = set(string)
  default     = [
    "auth",
    "flag",
    "targeting",
    "evaluation",
    "analytics",
  ]
}
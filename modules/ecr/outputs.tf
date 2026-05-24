output "ecr_repository_urls" {
  description = "Lista de URLs dos repositórios ECR"
  value = {
    for name, repo in aws_ecr_repository.toggle :
    name => repo.repository_url
  }
}
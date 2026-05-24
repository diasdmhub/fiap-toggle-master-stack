output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_ca" {
  description = "Dados do certificado do cluster EKS"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "eks_oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "eks_oidc_provider_url" {
  description = "URL do OIDC provider do cluster EKS (sem https://)"
  value       = trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
}
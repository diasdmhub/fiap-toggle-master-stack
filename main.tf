# VPC (principal)
module "vpc" {
  source = "./modules/vpc"

  name_prefix         = var.name_prefix
  subnet_prefix       = var.subnet_prefix
  public_subnet_nums  = var.public_subnet_nums
  private_subnet_nums = var.private_subnet_nums
}

# Módulos que dependem da VPC
module "eks" {
  source = "./modules/eks"

  name_prefix        = var.name_prefix
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  depends_on = [module.vpc]
}

module "rds" {
  source = "./modules/rds"

  name_prefix        = var.name_prefix
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  depends_on = [module.vpc]
}

module "cache" {
  source = "./modules/cache"

  name_prefix        = var.name_prefix
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  depends_on = [module.vpc]
}

# Módulos independentes
module "sqs" {
  source = "./modules/sqs"

  name_prefix = var.name_prefix
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix  = var.name_prefix
}

module "dynamo" {
  source = "./modules/dynamo"

  name_prefix = var.name_prefix
}

module "oidc" {
  source = "./modules/oidc"

  name_prefix    = var.name_prefix
  git_domain     = var.git_domain
  git_org        = var.git_org
  git_repo       = var.git_repo
}

module "argo" {
  source = "./modules/argo"

  chart_version    = var.chart_version
  service_type     = var.service_type
  cluster_endpoint = module.eks.eks_cluster_endpoint
  cluster_ca       = module.eks.eks_cluster_ca
  cluster_name     = module.eks.eks_cluster_name

  depends_on = [module.eks]
}


module "es" {
  source = "./modules/es"

  name_prefix       = var.name_prefix
  chart_version     = var.external_secrets_chart_version
  cluster_endpoint  = module.eks.eks_cluster_endpoint
  cluster_ca        = module.eks.eks_cluster_ca
  cluster_name      = module.eks.eks_cluster_name
  oidc_provider_arn = module.eks.eks_oidc_provider_arn
  oidc_provider_url = module.eks.eks_oidc_provider_url

  depends_on = [module.eks]
}

module "sa" {
  source = "./modules/sa"

  name_prefix       = var.name_prefix
  namespace         = var.namespace
  oidc_provider_arn = module.eks.eks_oidc_provider_arn
  oidc_provider_url = module.eks.eks_oidc_provider_url

  depends_on = [module.eks]
}

module "keda" {
  source = "./modules/keda"

  name_prefix      = var.name_prefix
  chart_version    = var.keda_chart_version
  cluster_endpoint = module.eks.eks_cluster_endpoint
  cluster_ca       = module.eks.eks_cluster_ca
  cluster_name     = module.eks.eks_cluster_name
  role_arn         = module.sa.role_arn

  depends_on = [module.eks]
}

module "secrets" {
  source                   = "./modules/secrets"

  name_prefix              = var.name_prefix
  rds_connection_url       = module.rds.rds_connection_url
  sqs_queue_url            = module.sqs.sqs_queue_url
  valkey_connection_string = module.cache.elasticache_valkey_connection_string

  depends_on               = [module.rds, module.sqs, module.cache]
}

module "mon" {
  source = "./modules/mon"

  name_prefix          = var.name_prefix
  cluster_endpoint     = module.eks.eks_cluster_endpoint
  cluster_ca           = module.eks.eks_cluster_ca
  cluster_name         = module.eks.eks_cluster_name
  grafana_pass         = var.grafana_pass
  grafana_service_type = var.grafana_service_type

  # Versões dos charts (vazio usa a versão mais recente)
  prometheus_chart_version = var.prometheus_chart_version
  loki_chart_version       = var.loki_chart_version
  otel_chart_version       = var.otel_chart_version
  tempo_chart_version      = var.tempo_chart_version

  depends_on = [module.eks]
}
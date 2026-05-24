#!/usr/bin/env bash

# 1. Validação de requisitos
missing=()
for cmd in git jq argocd aws; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

if (( ${#missing[@]} )); then
    printf 'ERRO: os requisitos abaixo não foram encontrados. Por favor, verifique a instalação deles.\n' >&2
    for m in "${missing[@]}"; do
        printf ' Binário - %s\n' "$m" >&2
    done
    exit 1
fi

# 2. Atualização das URLs

cp argo/argo_deploy.yaml.example argo/argo_deploy.yaml

AWS_REGION="$(grep '^aws_region' terraform.tfvars | cut -d '"' -f 2)"
NAME_PREFIX="$(grep '^name_prefix' terraform.tfvars | cut -d '"' -f 2)"

sed -i -E "s|^(\s+)repoURL: .*|\1repoURL: $(git config --get remote.origin.url)|" argo/argo_deploy.yaml && \
    echo "URL do repositório atualizada"

for serv in "auth" "flag" "targeting" "evaluation" "analytics"; do
    SERVICE=$(terraform output -json ecr_outputs | jq -r .ecr_repository_urls.$serv)
    sed -i "s|^\(\s*\)- toggle\/${serv}-service=.*$|\1- toggle\/${serv}-service=${SERVICE}|" argo/argo_deploy.yaml && \
    echo "URL do $serv-service atualizada"
done

for serv in "evaluation" "analytics"; do
    sed -i "/name: ${serv}-config/,/value:/ s|^\(\s*\)value:.*$|\1value: ${AWS_REGION}|" argo/argo_deploy.yaml && \
    echo "Config do $serv-config atualizada"
done

sed -i "/AWS_DYNAMODB_TABLE/,/value:/ s|^\(\s*\)value:.*$|\1value: $(terraform output -json dynamo_outputs | jq -r .dynamodb_table_name)|" argo/argo_deploy.yaml && \
    echo "Tabela do DynamoDB atualizada"

sed -i "/aws-secrets-manager/,/value:/ s|^\(\s*\)value:.*$|\1value: ${AWS_REGION}|" argo/argo_deploy.yaml && \
    echo "Região do ClusterSecretStore atualizada"

sed -i "/serviceAccountRef/,/value:/ s|^\(\s*\)value:.*$|\1value: $(terraform output -json es_outputs | jq -r .external_secrets_role_name)|" argo/argo_deploy.yaml && \
    echo "Nome do ClusterSecretStore atualizado"

sed -i "/name: db-secrets/,/value:/ s|^\(\s*\)value:.*$|\1value: ${NAME_PREFIX}/rds|" argo/argo_deploy.yaml && \
    echo "Namespace do db-secrets atualizado"

sed -i "/name: sqs-secrets/,/value:/ s|^\(\s*\)value:.*$|\1value: ${NAME_PREFIX}/sqs|" argo/argo_deploy.yaml && \
    echo "Namespace do sqs-secrets atualizado"

sed -i "/name: auth-secrets/,/value:/ s|^\(\s*\)value:.*$|\1value: ${NAME_PREFIX}/master_key|" argo/argo_deploy.yaml && \
    echo "Namespace do auth-secrets atualizado"

sed -i "/name: evaluation-secrets/,/value:/ s|^\(\s*\)value:.*$|\1value: ${NAME_PREFIX}/service_api_key|" argo/argo_deploy.yaml && \
    echo "Namespace do evaluation-secrets (service_api_key) atualizado"
sed -i "/1\/remoteRef\/key/,/value:/ s|^\(\s*\)value:.*$|\1value: ${NAME_PREFIX}/redis_url|" argo/argo_deploy.yaml && \
    echo "Namespace do evaluation-secrets (redis_url) atualizado"
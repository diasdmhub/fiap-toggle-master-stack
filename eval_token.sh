#!/usr/bin/env bash

# Master key do microserviço de autenticação
NAME_PREFIX="$(grep '^name_prefix' terraform.tfvars | cut -d '"' -f 2)"
AWS_REGION="$(aws configure get region)"
MASTER_KEY=$(aws secretsmanager get-secret-value \
    --secret-id "$NAME_PREFIX/master_key" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text 2>&1 | jq -r '.password' 2>&1)
if [ $? -ne 0 ]; then
    echo "⚠ Erro ao recuperar o secret"
    exit 1
fi

# Port-fowarding dos microserviços internos
kubectl port-forward service/auth -n toggle --address 0.0.0.0 8001:8001 &
kubectl port-forward service/flag -n toggle --address 0.0.0.0 8002:8002 &
kubectl port-forward service/targeting -n toggle --address 0.0.0.0 8003:8003 &
sleep 5

# Criar chave de autenticação
FLAG_TOKEN=$(curl -X POST http://localhost:8001/admin/keys \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -d '{"name": "toggle-flag"}' | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')

# Atualizar o secret com o novo token
aws secretsmanager update-secret \
    --secret-id "$NAME_PREFIX/service_api_key" \
    --secret-string "{\"api_key\": \"$FLAG_TOKEN\"}" \
    --region "$AWS_REGION"
if [ $? -ne 0 ]; then
    echo "⚠ Erro ao atualizar o secret"
    exit 1
fi

# Atualizar o secret no Kubernetes
kubectl annotate externalsecret evaluation-secrets force-sync=$(date +%s) --overwrite -n toggle
kubectl get externalsecret evaluation-secrets -n toggle
kubectl rollout restart deployment/evaluation-service -n toggle
sleep 5

# Criar feature flag com a chave 
curl -X POST http://localhost:8002/flags \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $FLAG_TOKEN" \
    -d '{
            "name": "enable-feature",
            "description": "Ativa o novo recurso para os usuários",
            "is_enabled": true
        }'

# Criar uma regra de segmentação
curl -X POST http://localhost:8003/rules \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $FLAG_TOKEN" \
    -d '{
            "flag_name": "enable-feature",
            "is_enabled": true,
            "rules": {
                "type": "PERCENTAGE",
                "value": 50
            }
        }'

# Finalizar os jobs em background
kill $(jobs -p)
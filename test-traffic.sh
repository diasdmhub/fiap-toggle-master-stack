#!/usr/bin/env bash
# =============================================================================
# test_trafego.sh — Gera tráfego sintético para o ToggleMaster em toda
# a cadeia de microserviços para popular traces no Tempo, métricas no
# Prometheus e logs no Loki.
#
# Uso:
#   ./test-traffic.sh [--requests N] [--flag-name NAME] [--eval-url URL]
# =============================================================================
set -euo pipefail

# --- Parâmetros ---
REQUESTS=100
FLAG_NAME="enable-feature"
EVAL_URL=""          # Se vazio, usa o LoadBalancer do evaluation-service

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requests)  REQUESTS="$2"; shift 2 ;;
    --flag-name) FLAG_NAME="$2"; shift 2 ;;
    --eval-url)  EVAL_URL="$2"; shift 2 ;;
    *) echo "Opção desconhecida: $1"; exit 1 ;;
  esac
done

# Cores
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
# 1. Descobrir URL do evaluation-service
# =============================================================================
if [[ -z "$EVAL_URL" ]]; then
  info "Buscando LoadBalancer do evaluation-service..."
  EVAL_URL=$(kubectl get svc evaluation -n toggle \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -z "$EVAL_URL" ]]; then
    EVAL_URL=$(kubectl get svc evaluation -n toggle \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
  if [[ -z "$EVAL_URL" ]]; then
    warn "LoadBalancer não encontrado. Iniciando port-forward na porta 8004..."
    kubectl port-forward svc/evaluation -n toggle 8004:8004 &
    PF_PID=$!
    trap "kill $PF_PID 2>/dev/null" EXIT
    sleep 3
    EVAL_URL="localhost"
  fi
fi
EVAL_ENDPOINT="http://${EVAL_URL}:8004"
info "Endpoint de avaliação: $EVAL_ENDPOINT"

# Verificar health do evaluation-service
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$EVAL_ENDPOINT/health" || echo "000")
if [[ "$HTTP_CODE" != "200" ]]; then
  error "evaluation-service não respondeu ao /health (HTTP $HTTP_CODE). Verifique o cluster."
fi
info "evaluation-service saudável ✓"

# =============================================================================
# 2. Iniciar port-forwards para os serviços internos (auth, flag, targeting)
# =============================================================================
info "Abrindo port-forwards para serviços internos..."
kubectl port-forward svc/auth      -n toggle 8001:8001 &>/dev/null &
kubectl port-forward svc/flag      -n toggle 8002:8002 &>/dev/null &
kubectl port-forward svc/targeting -n toggle 8003:8003 &>/dev/null &
#INTERNAL_PF_PIDS="$!"
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
sleep 4

# =============================================================================
# 3. Obter master key do Secrets Manager
# =============================================================================
NAME_PREFIX=$(grep '^name_prefix' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "fiap-toggle")
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
info "Buscando master key (prefix=$NAME_PREFIX, região=$AWS_REGION)..."
MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${NAME_PREFIX}/master_key" \
  --region "$AWS_REGION" \
  --query 'SecretString' \
  --output text 2>/dev/null | jq -r '.password' 2>/dev/null || true)
if [[ -z "$MASTER_KEY" ]]; then
  error "Não foi possível recuperar a master key. Execute: aws configure"
fi

# =============================================================================
# 4. Criar API key (token de serviço)
# =============================================================================
info "Criando API key para os testes..."
CREATE_KEY_RESP=$(curl -sf -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d '{"name": "test-traffic-key"}' || true)
FLAG_TOKEN=$(echo "$CREATE_KEY_RESP" | jq -r '.key // empty')
if [[ -z "$FLAG_TOKEN" ]]; then
  error "Falha ao criar API key. Resposta: $CREATE_KEY_RESP"
fi
info "API key criada ✓"

# =============================================================================
# 5. Criar feature flags e regras de segmentação
# =============================================================================
create_flag() {
  local name="$1" pct="$2"
  info "Criando flag '$name' (rollout ${pct}%)..."
  curl -sf -X POST http://localhost:8002/flags \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $FLAG_TOKEN" \
    -d "{\"name\": \"$name\", \"description\": \"Flag de teste: $name\", \"is_enabled\": true}" \
    > /dev/null || warn "Flag '$name' pode já existir — continuando"

  curl -sf -X POST http://localhost:8003/rules \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $FLAG_TOKEN" \
    -d "{\"flag_name\": \"$name\", \"is_enabled\": true, \"rules\": {\"type\": \"PERCENTAGE\", \"value\": $pct}}" \
    > /dev/null || warn "Regra para '$name' pode já existir — continuando"
}

create_flag "$FLAG_NAME"       50
create_flag "dark-launch"      10
create_flag "beta-feature"     80
create_flag "disabled-feature" 0
info "Flags e regras criadas ✓"

# =============================================================================
# 6. Gerar tráfego de avaliação (principal fonte de traces)
# =============================================================================
info "Iniciando $REQUESTS avaliações contra $EVAL_ENDPOINT ..."
RESULTS_OK=0; RESULTS_ERR=0
PREFIXES=("user" "beta" "admin" "mobile" "web" "api" "bot")

for i in $(seq 1 "$REQUESTS"); do
  PREFIX="${PREFIXES[$((RANDOM % ${#PREFIXES[@]}))]}"
  USER_ID="${PREFIX}-$(printf '%04d' $i)"
  # Alterna entre as flags para diversificar os traces
  FLAGS=("$FLAG_NAME" "dark-launch" "beta-feature" "disabled-feature")
  FNAME="${FLAGS[$((RANDOM % ${#FLAGS[@]}))]}"

  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    "${EVAL_ENDPOINT}/evaluate?user_id=${USER_ID}&flag_name=${FNAME}" || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    RESULTS_OK=$((RESULTS_OK + 1))
  else
    RESULTS_ERR=$((RESULTS_ERR + 1))
  fi

  # Barra de progresso simples a cada 10 requests
  if (( i % 10 == 0 )); then
    PCT=$(( i * 100 / REQUESTS ))
    printf "\r  [%-50s] %3d%%  (ok=%-4d err=%-4d)" \
      "$(printf '█%.0s' $(seq 1 $((PCT/2))))" "$PCT" "$RESULTS_OK" "$RESULTS_ERR"
  fi
  # Pequena pausa para não saturar e gerar um fluxo mais natural nos gráficos
  sleep 0.1
done
echo ""
info "Avaliações concluídas: ✓ $RESULTS_OK OK | ✗ $RESULTS_ERR erros"

# =============================================================================
# 7. Gerar algumas requisições de erro (para exercitar error spans)
# =============================================================================
info "Gerando requisições inválidas (para testar error traces)..."
# Sem parâmetros obrigatórios
curl -sf -o /dev/null "${EVAL_ENDPOINT}/evaluate" || true
# Flag inexistente
curl -sf -o /dev/null "${EVAL_ENDPOINT}/evaluate?user_id=test&flag_name=nao-existe-XYZXYZ" || true
# Health checks de todos os serviços internos
for PORT in 8001 8002 8003; do
  curl -sf -o /dev/null "http://localhost:${PORT}/health" || true
done

# =============================================================================
# 8. Resumo
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Tráfego gerado com sucesso!"
echo ""
echo "  No Grafana, acesse:"
echo "  → Explore › Tempo     — pesquise por 'service.name = evaluation-service'"
echo "  → Explore › Prometheus — http_server_request_duration_seconds_bucket"
echo "  → Dashboards          — importe o arquivo togglemaster-dashboard.json"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

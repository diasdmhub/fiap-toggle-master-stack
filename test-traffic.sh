#!/usr/bin/env bash
# =============================================================================
# test-traffic.sh — Gerador de tráfego sintético realista para o ToggleMaster
#
# Gera requisições válidas, erros controlados (400/401/404), flags inexistentes
# e tokens inválidos. Suporta paralelismo e latências variadas para simular
# carga real e popular traces, métricas e logs nos backends de observabilidade.
#
# Uso:
#   ./test-traffic.sh [opções]
#
# Opções:
#   --requests N        Total de requisições de avaliação (padrão: 150)
#   --concurrency N     Requisições paralelas simultâneas (padrão: 5)
#   --error-rate N      % de requisições que devem gerar erros (padrão: 20)
#   --flag-name NAME    Flag principal para as avaliações (padrão: enable-feature)
#   --eval-url URL      URL base do evaluation-service (auto-detectado se omitido)
# =============================================================================
set -euo pipefail

# ─── Parâmetros ───────────────────────────────────────────────────────────────
REQUESTS=150
CONCURRENCY=5
ERROR_RATE=20          # porcentagem de requisições que geram erros intencionais
FLAG_NAME="enable-feature"
EVAL_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requests)    REQUESTS="$2";    shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --error-rate)  ERROR_RATE="$2";  shift 2 ;;
    --flag-name)   FLAG_NAME="$2";   shift 2 ;;
    --eval-url)    EVAL_URL="$2";    shift 2 ;;
    *) echo "Opção desconhecida: $1"; exit 1 ;;
  esac
done

# ─── Utilitários ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

# Arquivo temporário para acumular resultados dos workers paralelos
RESULTS_FILE=$(mktemp)
trap "rm -f '$RESULTS_FILE'; kill \$(jobs -p) 2>/dev/null || true" EXIT

# ─── Função: sleep com jitter ─────────────────────────────────────────────────
# Simula padrões de chegada variados: a maioria das requisições é rápida
# (0.05–0.3s), mas ~15% simulam clientes lentos ou retries (0.5–1.5s).
jitter_sleep() {
  local r=$(( RANDOM % 100 ))
  if   (( r < 50 )); then sleep 0.05           # 50% → rajada rápida
  elif (( r < 75 )); then sleep 0.15           # 25% → ritmo normal
  elif (( r < 90 )); then sleep 0.30           # 15% → cliente moderado
  else                    sleep "0.$(( RANDOM % 6 + 5 ))"  # 10% → cliente lento (0.5–1.0s)
  fi
}

# ─── 1. Descobrir URL do evaluation-service ───────────────────────────────────
section "1. Descobrindo endpoint do evaluation-service"
if [[ -z "$EVAL_URL" ]]; then
  EVAL_URL=$(kubectl get svc evaluation -n toggle \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -z "$EVAL_URL" ]] && EVAL_URL=$(kubectl get svc evaluation -n toggle \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -z "$EVAL_URL" ]]; then
    warn "LoadBalancer não encontrado. Iniciando port-forward na porta 8004..."
    kubectl port-forward svc/evaluation -n toggle 8004:8004 &>/dev/null &
    sleep 3
    EVAL_URL="localhost"
  fi
fi
EVAL_BASE="http://${EVAL_URL}:8004"
info "Endpoint: $EVAL_BASE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 "$EVAL_BASE/health" || echo "000")
[[ "$HTTP_CODE" != "200" ]] && error "evaluation-service /health retornou HTTP $HTTP_CODE"
info "evaluation-service saudável ✓"

# ─── 2. Port-forwards para serviços internos ──────────────────────────────────
section "2. Abrindo port-forwards para serviços internos"
kubectl port-forward svc/auth      -n toggle 8001:8001 &>/dev/null &
PF_AUTH=$!
kubectl port-forward svc/flag      -n toggle 8002:8002 &>/dev/null &
PF_FLAG=$!
kubectl port-forward svc/targeting -n toggle 8003:8003 &>/dev/null &
PF_TGT=$!
# Guarda os PIDs dos port-forwards para encerrá-los no EXIT,
# mas sem incluí-los no wait final (eles nunca terminam sozinhos).
PF_PIDS="$PF_AUTH $PF_FLAG $PF_TGT"
trap "kill $PF_PIDS 2>/dev/null || true; rm -f '$RESULTS_FILE'" EXIT
sleep 4
info "port-forwards ativos (auth:8001, flag:8002, targeting:8003)"

# ─── 3. Credenciais ───────────────────────────────────────────────────────────
section "3. Obtendo credenciais"
NAME_PREFIX=$(grep '^name_prefix' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "fiap-toggle")
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
info "Buscando master key (prefix=$NAME_PREFIX, região=$AWS_REGION)..."
MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${NAME_PREFIX}/master_key" \
  --region "$AWS_REGION" \
  --query 'SecretString' --output text 2>/dev/null | jq -r '.password' 2>/dev/null || true)
[[ -z "$MASTER_KEY" ]] && error "Não foi possível recuperar a master key. Execute: aws configure"

info "Criando API key de teste..."
RESP=$(curl -sf -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d '{"name":"test-traffic-key"}' || true)
FLAG_TOKEN=$(echo "$RESP" | jq -r '.key // empty')
[[ -z "$FLAG_TOKEN" ]] && error "Falha ao criar API key. Resposta: $RESP"
info "API key criada ✓"

# ─── 4. Criar flags e regras ──────────────────────────────────────────────────
section "4. Criando feature flags e regras de segmentação"
create_flag() {
  local name="$1" pct="$2"

  local flag_code rule_code
  flag_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8002/flags \
    -H "Content-Type: application/json" -H "Authorization: Bearer $FLAG_TOKEN" \
    -d "{\"name\":\"$name\",\"description\":\"Teste: $name\",\"is_enabled\":true}")

  rule_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8003/rules \
    -H "Content-Type: application/json" -H "Authorization: Bearer $FLAG_TOKEN" \
    -d "{\"flag_name\":\"$name\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":$pct}}")

  # 200/201 = criado agora; 409 = já existia de uma execução anterior (esperado
  # e idempotente, não é erro). Qualquer outro código é um problema de verdade.
  case "$flag_code" in
    200|201) info "  flag '$name' (${pct}%) criada ✓" ;;
    409)     info "  flag '$name' (${pct}%) já existia, reutilizando ✓" ;;
    *)       warn "  flag '$name': POST /flags retornou HTTP $flag_code (inesperado)" ;;
  esac

  case "$rule_code" in
    200|201|409) : ;; # regra já reportada junto da flag acima, nada a fazer
    *)           warn "  regra para '$name': POST /rules retornou HTTP $rule_code (inesperado)" ;;
  esac
}
create_flag "$FLAG_NAME"       50
create_flag "dark-launch"      10
create_flag "beta-feature"     80
create_flag "disabled-feature"  0

# ─── 5. Definição dos cenários de erro ────────────────────────────────────────
# Cada cenário é uma função que emite uma linha "STATUS description" para
# RESULTS_FILE ao concluir. O worker principal sorteará qual cenário executar.

# 5a. Tokens inválidos → 401 no auth-service
req_invalid_token() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "${EVAL_BASE}/evaluate?user_id=hack-001&flag_name=${FLAG_NAME}" \
    -H "Authorization: Bearer invalid-token-$(( RANDOM % 9999 ))" || echo "000")
  echo "$code invalid_token" >> "$RESULTS_FILE"
}

# 5b. Sem parâmetros obrigatórios → 400 no evaluation-service
req_missing_params() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "${EVAL_BASE}/evaluate" || echo "000")
  echo "$code missing_params" >> "$RESULTS_FILE"
}

# 5c. Apenas user_id → 400
req_missing_flag() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "${EVAL_BASE}/evaluate?user_id=user-$(( RANDOM % 999 ))" || echo "000")
  echo "$code missing_flag_param" >> "$RESULTS_FILE"
}

# 5d. Flag inexistente → avaliação retorna false (não 404, mas sem regra)
req_unknown_flag() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "${EVAL_BASE}/evaluate?user_id=user-$(( RANDOM % 999 ))&flag_name=flag-nao-existe-$(( RANDOM % 999 ))" \
    || echo "000")
  echo "$code unknown_flag" >> "$RESULTS_FILE"
}

# 5e. Recurso inexistente no flag-service → 404
req_unknown_flag_crud() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "http://localhost:8002/flags/flag-inexistente-$(( RANDOM % 999 ))" \
    -H "Authorization: Bearer $FLAG_TOKEN" || echo "000")
  echo "$code flag_not_found_404" >> "$RESULTS_FILE"
}

# 5f. Recurso inexistente no targeting-service → 404
req_unknown_rule() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "http://localhost:8003/rules/regra-inexistente-$(( RANDOM % 999 ))" \
    -H "Authorization: Bearer $FLAG_TOKEN" || echo "000")
  echo "$code rule_not_found_404" >> "$RESULTS_FILE"
}

# 5g. Método HTTP errado → 405
req_wrong_method() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 -X DELETE \
    "${EVAL_BASE}/evaluate?user_id=x&flag_name=${FLAG_NAME}" || echo "000")
  echo "$code wrong_method_405" >> "$RESULTS_FILE"
}

# 5h. Requisição válida (caminho feliz)
req_valid() {
  local prefixes=("user" "beta" "admin" "mobile" "web" "api" "bot")
  local prefix="${prefixes[$((RANDOM % ${#prefixes[@]}))]}"
  local user_id="${prefix}-$(printf '%05d' $(( RANDOM % 99999 )))"
  local flags=("$FLAG_NAME" "dark-launch" "beta-feature" "disabled-feature")
  local fname="${flags[$((RANDOM % ${#flags[@]}))]}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --connect-timeout 3 \
    "${EVAL_BASE}/evaluate?user_id=${user_id}&flag_name=${fname}" \
    || echo "000")
  echo "$code valid_eval" >> "$RESULTS_FILE"
}

# Array de tipos de erro e seus pesos (repetições = peso)
ERROR_SCENARIOS=(
  req_invalid_token
  req_invalid_token
  req_missing_params
  req_missing_flag
  req_unknown_flag
  req_unknown_flag
  req_unknown_flag_crud
  req_unknown_rule
  req_wrong_method
)

# ─── 6. Worker: executa uma requisição (válida ou erro) ───────────────────────
run_one() {
  local i="$1"
  local roll=$(( RANDOM % 100 ))

  if (( roll < ERROR_RATE )); then
    # Sorteia um cenário de erro
    local idx=$(( RANDOM % ${#ERROR_SCENARIOS[@]} ))
    "${ERROR_SCENARIOS[$idx]}"
  else
    req_valid
  fi
  jitter_sleep
}

export -f run_one req_valid req_invalid_token req_missing_params req_missing_flag \
          req_unknown_flag req_unknown_flag_crud req_unknown_rule req_wrong_method \
          jitter_sleep
export EVAL_BASE FLAG_NAME FLAG_TOKEN RESULTS_FILE ERROR_RATE
export ERROR_SCENARIOS_STR="${ERROR_SCENARIOS[*]}"

# ─── 7. Loop principal com paralelismo ────────────────────────────────────────
section "5. Gerando $REQUESTS requisições (concorrência=$CONCURRENCY, erros≈${ERROR_RATE}%)"
echo ""

# Guarda apenas os PIDs dos workers (não os dos port-forwards)
WORKER_PIDS=()

for i in $(seq 1 "$REQUESTS"); do
  # Exporta o array de cenários no contexto do subshell
  (
    ERROR_SCENARIOS=($ERROR_SCENARIOS_STR)
    run_one "$i"
  ) &
  WORKER_PIDS+=($!)

  # Limita o número de jobs paralelos ao --concurrency:
  # aguarda apenas o worker mais antigo (primeiro da fila), não os port-forwards
  if (( ${#WORKER_PIDS[@]} >= CONCURRENCY )); then
    wait "${WORKER_PIDS[0]}" 2>/dev/null || true
    WORKER_PIDS=("${WORKER_PIDS[@]:1}")   # remove o primeiro (já concluído)
  fi

  # Progresso a cada 10 requisições
  if (( i % 10 == 0 )); then
    DONE=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo 0)
    PCT=$(( i * 100 / REQUESTS ))
    printf "\r  [%-40s] %3d%%  (disparadas=%-4d concluídas=%-4d)" \
      "$(printf '█%.0s' $(seq 1 $((PCT * 40 / 100))))" "$PCT" "$i" "$DONE"
  fi
done

# Aguarda apenas os workers ainda ativos (ignora port-forwards)
if (( ${#WORKER_PIDS[@]} > 0 )); then
  wait "${WORKER_PIDS[@]}" 2>/dev/null || true
fi
echo ""

# ─── 8. Relatório final ───────────────────────────────────────────────────────
section "6. Relatório"

# Conta resultados por status HTTP
declare -A BY_STATUS
declare -A BY_SCENARIO
while IFS=' ' read -r code scenario; do
  [[ -z "$code" ]] && continue
  BY_STATUS[$code]=$(( ${BY_STATUS[$code]:-0} + 1 ))
  BY_SCENARIO[$scenario]=$(( ${BY_SCENARIO[$scenario]:-0} + 1 ))
done < "$RESULTS_FILE"

TOTAL=$(wc -l < "$RESULTS_FILE")
OK_COUNT=${BY_STATUS[200]:-0}
ERR_COUNT=$(( TOTAL - OK_COUNT ))

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
printf "  │  Total: %-5s  │  ✓ 200: %-5s  │  ✗ erros: %-5s   │\n" "$TOTAL" "$OK_COUNT" "$ERR_COUNT"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │  Por status HTTP:                                   │"
for code in $(echo "${!BY_STATUS[@]}" | tr ' ' '\n' | sort); do
  printf "  │    HTTP %-4s → %-5s requisições                    │\n" "$code" "${BY_STATUS[$code]}"
done
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │  Por cenário:                                       │"
for scen in $(echo "${!BY_SCENARIO[@]}" | tr ' ' '\n' | sort); do
  printf "  │    %-30s → %-5s          │\n" "$scen" "${BY_SCENARIO[$scen]}"
done
echo "  └─────────────────────────────────────────────────────┘"

echo ""
echo "  No Grafana:"
echo "  → APM › Service Map      — nós coloridos por taxa de erros"
echo "  → APM › Red por serviço  — pico de erros visível nos gráficos"
echo "  → Explore › Tempo        — { status = error } para ver error spans"
echo "  → Explore › Loki         — {namespace=\"toggle\"} | logfmt | level = \"error\""
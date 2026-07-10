| [↩️ Voltar](/) |
| --- |

## Script de teste [`test-traffic.sh`][scriptest]

É um gerador de tráfego sintético realista para o ToggleMaster. Gera requisições válidas, erros controlados (400/401/404), flags inexistentes e tokens inválidos. Suporta paralelismo e latências variadas para simular carga real e popular traces, métricas e logs nos backends de observabilidade.

O script tem o objetivo de popular a stack de observabilidade gerando tráfego de teste realista. Ele mistura sucessos e erros a fim de demonstrar métricas e _traces_ do Prometheus, Tempo e Loki no Grafana.

Ele realiza automaticamente:

- **Descobre o endpoint** do `evaluation-service` e valida seu estado (`/health`).
- **Abre port-forwards** internos para os microserviços `auth` (`8001`), `flag` (`8002`) e `targeting` (`8003`), usados para as chamadas administrativas de setup.
- **Obtém credenciais**: busca a master key no AWS Secrets Manager e cria uma API key de teste via `auth-service`.
- **Cria flags e regras de segmentação** de teste:
    - `enable-feature` (ou `--flag-name`) a 50%
    - `dark-launch` a 10%
    - `beta-feature` a 80%
    - `disabled-feature` a 0%
- **Gera tráfego misto em paralelo** (opção `--concurrency`), com sleep de jitter simulando clientes rápidos/lentos, dividido entre:
    - Requisições válidas de avaliação (`req_valid`, usuários/flags aleatórios)
    - Cenários de erro sorteados por peso (`--error-rate`): token inválido (401), parâmetros ausentes (400), flag/regra inexistente (404), método HTTP errado (40
5), flag desconhecida na avaliação.
- **Apresenta um relatório final** com a contagem por status HTTP e por cenário, e sugere onde observar o resultado no Grafana (Service Map, RED por serviço, trace
s com erro no Tempo, logs de erro no Loki).

### Execução

Uso:
  `./test-traffic.sh [opções]`
Opções:
  `--requests N` - Total de requisições de avaliação (_padrão: `150`_)
  `--concurrency N` - Requisições paralelas simultâneas (_padrão: `5`_)
  `--error-rate N` - % de requisições que devem gerar erros (_padrão: `20`_)
  `--flag-name NAME` - Flag principal para as avaliações (_padrão: `enable-feature`_)
  `--eval-url URL` - URL base do evaluation-service (_auto-detectado se omitido_)

| [⬆️ Top](#script-de-teste-test---traffic.sh) |
| --- |

[scriptest]: /test-traffic.sh
| [↩️ Voltar](/) |
| --- |

## Script de teste [`test-traffic.sh`][scriptest]

Trata-se de um gerador de tráfego sintético realista para o ToggleMaster. Ele gera requisições válidas, erros controlados (_400/401/404_), flags inexistentes e tokens inválidos. Ele suporta paralelismo e latências variadas para simular uma carga real e popular traces, métricas e logs nos backends de observabilidade.

Seu objetivo é gerar tráfego de teste realista para a stack de observabilidade. Ele combina sucessos e erros para demonstrar métricas e _traces_ do Prometheus, Tempo e Loki no Grafana.

Ele realiza automaticamente as seguintes ações:

- **Descobre o endpoint** do `evaluation-service` e valida seu estado (`/health`);
- **Abre port-forwards** internos para os microserviços `auth` (`8001`), `flag` (`8002`) e `targeting` (`8003`), usados para as chamadas administrativas de configuração;
- **Obtém credenciais**: busca a _master key_ no AWS Secrets Manager e cria uma chave de API de teste via `auth-service`;
- **Cria flags e regras de segmentação** de teste:
    - `enable-feature` (ou `--flag-name`) a 50%;
    - `dark-launch` a 10%;
    - `beta-feature` a 80%;
    - `disabled-feature` a 0%.
- **Gera tráfego misto em paralelo** (opção `--concurrency`), com _jitter_ de espera simulando clientes rápidos e lentos, dividido entre:
    - Requisições válidas de avaliação (`req_valid`, usuários/flags aleatórios);
    - Cenários de erro sorteados por peso (opção `--error-rate`): token inválido (401), parâmetros ausentes (400), flag ou regra inexistente (404), método HTTP incorreto (405) e flag desconhecida na avaliação.
- **Apresenta um relatório final** com a contagem por status HTTP e por cenário, e sugere onde observar o resultado no Grafana (Service Map, RED por serviço, trace
s com erro no Tempo, logs de erro no Loki).

### Execução

```
Uso:
  ./test-traffic.sh [opções]

Opções:
  --requests N - Total de requisições de avaliação (_padrão: 150_)
  --concurrency N - Requisições paralelas simultâneas (_padrão: 5_)
  --error-rate N - % de requisições que devem gerar erros (_padrão: 20_)
  --flag-name NAME - Flag principal para as avaliações (_padrão: enable-feature_)
  --eval-url URL - URL base do evaluation-service (_auto-detectado se omitido_)
```

<BR>

## Auto recuperação com o AWS Lambda

O módulo [`modules/selfheal`][selfheal] do Terraform implementa um mecanismo de auto-recuperação (_self-healing_) para os microsserviços do ToggleMaster, acionado quando o Grafana detecta um serviço com erro. A função do Lambda reinicia automaticamente o Deployment correspondente no EKS, sem intervenção humana.

### Escolha do Lambda

- Execução sob demanda com baixo custo: o self-healing é execudado apenas quando um alerta é disparado.
- Superfície de ataque mínima: não são necessárias credenciais AWS de longa duração nem de um `kubeconfig` persistido, pois gera o token EKS é gerado sob demanda via STS.
- Isolamento do plano de controle: mesmo se o próprio cluster/namespace toggle estiver degradado, continua funcional, pois roda fora do cluster via VPC config e SG dedicado.
- Simplicidade operacional: não há dependências externas (apenas `stdlib` e `boto3`, já no _runtime_), empacotamento automático via `archive_file` no `terraform apply`, e integração nativa com o API Gateway, o IAM e o DynamoDB. Tudo fica dentro do mesmo modelo de infraestrutura como código já usado no restante do projeto.
- Há _statelessness_ com estado mínimo externalizado: o _cooldown_ fica no DynamoDB com TTL automático. Dessa forma, o Lambda não precisa manter estado entre invocações, o que combina bem com o modelo de execução efêmera.

### Fluxo de execução

1. O Grafana dispara o alerta enviando um _HTTP POST_ (_contact point tipo webhook_) para o API Gateway da AWS ([`apigw.tf`][apigw]).
2. O API Gateway encaminha o _POST_ de endpoint `/selfheal` como _proxy integration_ para o Lambda ([`lambda.tf`][lambda.tf]).
3. A função no Lambda ([`handler.py`][handler.py]):
    - Valida as credenciais de autenticação.
    - Para cada alerta com status `firing`, extrai o nome do deployment do label `deployment` e verifica se está na _allowlist_ (via variável `target_deployments`).
    - Há uma histerese no DynamoDB ([`dynamo.tf`][dynamo.tf]) para evitar que o mesmo serviço não seja reiniciado repetidamente, causando oscilações.
    - Se for liberado, é gerado um token de acesso EKS e aplica um _patch_ direto com a API do Kubernetes, o que é equivalente a um `kubectl rollout restart`, restaurando também o _replica count_, caso esteja abaixo do mínimo.
4. A autorização no cluster ([`rbac.tf`][rbac.tf]) ocorre por meio da role IAM do Lambda, que é mapeada como identidade EKS e vinculada a uma _Role/RoleBinding_ Kubernetes restrita. Ela só pode realizar _get/patch_ nos Deployments explicitamente listados em `target_deployments`.

| [⬆️ Top](#script-de-teste-test---traffic.sh) |
| --- |

[scriptest]: /test-traffic.sh
[selfheal]: /modules/selfheal/
[handler.py]: /modules/selfheal/lambda_src/handler.py
[apigw]: /modules/selfheal/apigw.tf
[lambda.tf]: /modules/selfheal/lambda.tf
[dynamo.tf]: /modules/selfheal/dynamo.tf
[rbac.tf]: /modules/selfheal/rbac.tf
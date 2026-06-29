# Tech Challenge Fase 4 - Stack "ToggleMaster"

> Análise geral e implementação comentada do "desafio" da Fase 4 do curso DevOps e Arquitetura Cloud da FIAP.

<BR>

## Ambiente

A estrutura do ambiente tem algumas camadas princiais:

- **Terraform** - Provisiona toda a infraestrutura: VPC, EKS, RDS, Valkey, SQS, stack de monitoramento e políticas IAM.
- **CI/CD** - O GitHub Actions constrói as imagens, envia ao ECR, e o ArgoCD as puxa para o cluster como GitOps.
- **IAM/IRSA** - O OIDC provider autentica o GitHub Actions para push no ECR; as roles IRSA concedem permissões aos pods sem credenciais estáticas.
- **EKS cluster** - Foi dividido em dois namespaces principais:
    - No `toggle` ficam os cinco microserviços com suas responsabilidades. O evaluation-service chama o flag e o targeting internamente.
    - No `monitoring` o _OTel Collector_ é o ponto central onde todos os serviços enviam telemetria OTLP para ele, e ele roteia métricas ao Prometheus, logs ao Loki e traces ao Tempo. O Grafana consome dados deles para as dashboards.
- **AWS** - O RDS é usado pelos microserviços `auth`, `flag` e `targeting`, o ElastiCache Redis faz o cache do microserviço `evaluation`, o SQS recebe as publicações do `evaluation` e `analytics` consome. Por fim, o Secrets Manager gerencia as credenciais.

## Considerações

- A stack de monitoração tem o perfil de uma ferramenta de plataforma, não uma aplicação de negócio. Por isso ela foi adicionada como um novo módulo de monitoramento do Terraform (`/modules/mon`).
- O script de teste faz automaticamente:
    - Descobre o LoadBalancer do evaluation-service via `kubectl`
    - Abre port-forwards para os serviços internos (_`auth`, `flag`, `targeting`_)
    - Recupera a master key do AWS Secrets Manager
    - Cria 4 flags com percentuais diferentes (50%, 10%, 80%, 0%)
    - Dispara 200 avaliações por padrão com user IDs e flag names variados
    - Gera requests inválidas para criar error spans
- ⚠️ A implementaçao de APMs como Datadog ou New Relic é desconsiderada nesta fase com as seguintes considerações:
    - **Datadog**: [exige conexão com serviços terceiros (_GitHub_)][datadog_edu] para acesso educativo. Por sua vez, o GitHub, por meio de seu [pacote para estudantes][github_edu], exige informações de identificação governamentais e rastreamento biométrico altamente invasivo. Esses dados podem ser usados pelo GitHub e seus parceiros, incluindo a Datadog, sem garantias reais de privacidade, além de auxiliarem em perfilarizações comerciais e treinamentos de IA.
    - **New Relic**: o portal tem recusado conexões (_`ERR_CONNECTION_REFUSED`_) durante o desenvolvimento desta fase. Portanto, não foi possível acessar esse serviço.
    - **Portanto**, entendo que estas são ferramentas privadas de custo elevado e com acesso educacional relativamente invasivo. Elas não trazem benefícios reais aos usuários para fins educacionais. Como existem ferramentas alternativas, o **Grafana Tempo** é utilizado no projeto, pois ele já é integrado ao Grafana, não possui custos e é open-source.

[datadog_edu]: https://studentpack.datadoghq.com/
[github_edu]: https://education.github.com/pack
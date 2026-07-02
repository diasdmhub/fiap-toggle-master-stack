# Tech Challenge Fase 4 - Stack "ToggleMaster"

> Análise geral e implementação comentada do "desafio" da Fase 4 do curso DevOps e Arquitetura Cloud da FIAP.

A ToggleMaster é uma solução que permite ativar ou desativar _features_ em produção sem a necessidade de um novo _deploy_. Ela foi criada para que times de desenvolvimento possam lançar novas funcionalidades de forma segura e controlada.

Nesta fase, o projeto propõe a monitoração de todo infraestrutura e microserviços do sistema ToggleMaster ([_o mesmo da Fase 3_][fase3]). São incluídos recursos de monitoração e observabilidade e um modelo padronizado com o OpenTelemetry. Os microserviços foram padronizados de modo a permitir uma "visibilidade profunda", disponibilizando traces e spans para consulta. Assim, todo o conjunto é monitorado e observado com profundidade, além de integrado a ferramentas de monitoração, alerta e gerenciamento de incidentes.

<BR>

## Ambiente

O projeto da ToggleMaster com IaaS é composto por alguns recursos principais: os **microserviços**, a **infraestrutura _cloud_** e os **módulos do Kubernetes**. Esses recursos são integrados por meio de algumas ferramentas que também são descritas mais adiante.

O sistema ToggleMaster é segmentado em 5 microsserviços altamente integrados entre si. São eles: [`auth-service`][authserv], [`flag-service`][flagserv], [`targeting-service`][targetserv], [`evaluation-service`][evalserv] e [`analytics-service`][analyticserv], cada um com seu respectivo repositório original, disponibilizado pela FIAP.

Os microserviços são executados em um _cloud provider_, a AWS, para permitir alta flexibilidade, escalabilidade e segurança ao sistema. A infraestrutura da AWS é implementada com o Terraform, e foi segmentada em módulos a fim de automatizar e flexibilizar a criação do ambiente.

Com o ambiente AWS criado, os microsserviços, então, são executados em um cluster Kubernetes (K8s), o EKS da AWS. Diversos manifestos K8s foram criados para definir como o sistema ToggleMaster deve ser executado e escalado nesse ambiente. Também é implementado no cluster o ArgoCD, para que o _deploy_ seja automatizado e sincronizado com o repositório Git, tornando-o o ponto central de controle e manutenção do código do sistema.

<BR>

## 🏗️ Arquitetura

A arquitetura do ambiente tem algumas camadas princiais descritas abaixo.

- **Terraform** - Provisiona toda a infraestrutura: VPC, EKS, RDS, Valkey, SQS, Secrets, políticas IAM e stack de monitoramento.
- **CI/CD** - O fluxo de GitOps se dá com o GitHub Actions que constrói as imagens, envia-as ao ECR utilizando o OIDC, e o ArgoCD busca os dados para a implementação no cluster Kubernetes.
- **AWS EKS** - O cluster Kubernetes que foi dividido em dois namespaces principais:
    - No **`toggle`** ficam os cinco microserviços com suas próprias responsabilidades. O `evaluation-service` chama o `flag` e o `targeting` internamente, os quais buscam a autorização no `auth-service`. O `analytics` consome as mensagens do SQS.
    - No **`monitoring`** o _OTel Collector_ é o ponto central onde todos os serviços enviam telemetria OTLP para ele, e ele roteia métricas ao Prometheus, logs ao Loki e traces ao Tempo. O Grafana consome dados deles para as dashboards.
- **AWS SQS/RDS/Valkey/Secrets** - O **RDS** é a base de dados dos microserviços `auth`, `flag` e `targeting`, o ElastiCache Valkey/Redis faz o cache do microserviço `evaluation`, o **SQS** recebe as publicações do `evaluation` e o `analytics` as consome. Por fim, o **Secrets Manager** gerencia as credenciais.

<BR>

## 🔑 Prerequisitos

**1.** De preferência, faça um **"_fork_" deste repositório** para possibilitar a execução do CI workflow. Ele é utilizado para testar e, principalmente, para enviar as imagens dos microserviços ao AWS ECR.
> **É necessário habilitar o serviço de `Actions` no repositório.**

**2.** Copie todo o código-fonte do repositório para um ambiente de execução/desenvolvimento local. Recomenda-se **clonar o repositório com o Git**:
> **`git clone https://github.com/SUA_CONTA/FORK_DO_REPO.git && cd FORK_DO_REPO`**

**3.** O ambiente de execução/desenvolvimento local deve estar **autenticado na AWS** com o [**AWS CLI**][awscli], pois ele será utilizado em algumas configurações mais adiante.

**4.** É necessário [**instalar o Terraform**][terraform] no ambiente de execução/desenvolvimento local para implementar os serviços da AWS que serão utilizados pelo sistema ToggleMaster;

**5.** O **`kubectl`** é necessário para gerenciar o cluster Kubernetes e seus recursos. Recomenda-se instalá-lo utilizando o [**repositório oficial do Kubernetes**][kuberepo];

**6.** _(Opcional)_ O [**cliente ArgoCD CLI**][argocdcli] pode ser instalado no ambiente local para auxiliar nas configurações da ToggleMaster no cluster. No roteiro de implementação, são apresentados alguns exemplos que o utilizam. No entanto, também é possível sincronizar os manifestos da ToggleMaster diretamente na interface do ArgoCD.

<BR>

---

### [↗️ Roteiro de implementação](/roteiro/)

---

<BR>

## Considerações

🔶 A stack de monitoração tem o perfil de uma ferramenta de plataforma, não uma aplicação de negócio. Por isso ela foi adicionada como um novo módulo de monitoramento do Terraform (`/modules/mon`).

🔶 O script de teste automaticamente:

- Descobre o LoadBalancer do evaluation-service via `kubectl`
- Abre port-forwards para os serviços internos (_`auth`, `flag`, `targeting`_)
- Recupera a master key do AWS Secrets Manager
- Cria 4 flags com percentuais diferentes (50%, 10%, 80%, 0%)
- Dispara 150 avaliações por padrão com user IDs e flag names variados
- Gera requests inválidas para criar error spans

🔶 ⚠️ A implementaçao de APMs como Datadog ou New Relic não foi implementada nesta fase com as seguintes considerações:

- **Datadog**: [exige conexão com serviços terceiros (_GitHub_)][datadog_edu] para acesso educativo. Por sua vez, o GitHub, por meio de seu [pacote para estudantes][github_edu], exige informações de identificação governamentais e rastreamento biométrico **altamente invasivo**. Esses dados podem ser usados pelo GitHub e seus parceiros, incluindo a Datadog, sem garantias reais de privacidade, além de auxiliarem em perfilarizações comerciais e treinamentos de IA.
- **New Relic**: o portal tem recusado conexões (_`ERR_CONNECTION_REFUSED`_) durante o desenvolvimento desta fase. Portanto, não foi possível acessar esse serviço.
- **Portanto**, entendo que estas são ferramentas privadas de custo elevado e com acesso educacional relativamente invasivo. Elas não trazem benefícios reais aos usuários para fins educacionais. Como existem ferramentas alternativas, o **Grafana Tempo** é utilizado no projeto, pois ele já é integrado ao Grafana, não possui custos e é open-source.

[fase3]: https://github.com/diasdmhub/fiap-toggle-master-iaas
[authserv]: https://github.com/FIAP-TCs/auth-service
[flagserv]: https://github.com/FIAP-TCs/flag-service
[targetserv]: https://github.com/FIAP-TCs/targeting-service
[evalserv]: https://github.com/FIAP-TCs/evaluation-service
[analyticserv]: https://github.com/FIAP-TCs/analytics-service
[awscli]: https://aws.amazon.com/cli/
[terraform]: https://developer.hashicorp.com/terraform/install
[kuberepo]: https://kubernetes.io/docs/tasks/tools/
[argocdcli]: https://argo-cd.readthedocs.io/en/stable/cli_installation/
[datadog_edu]: https://studentpack.datadoghq.com/
[github_edu]: https://education.github.com/pack
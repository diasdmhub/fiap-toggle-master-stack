| [↩️ Voltar](/) |
| --- |

# Roteiro de Implementação

Para a implementação, similar à [fase 3 do projeto][fase3], é necessário configurar alguns dados para permitir que o ambiente seja criado de forma consistente e de acordo com suas características.

<BR>

## 1 Variáveis Terraform

O arquivo de [variáveis do Terraform][tfvars] (`terraform.tfvars`) deve ser definido com as principais variáveis do ambiente, incluindo a senha inicial do Grafana. Embora seja disponibilizado um arquivo de exemplo (`terraform.tfvars.example`) com alguns valores pré-definidos, é **altamente recomendado que as variáveis a seguir sejam definidas de acordo com o ambiente**.

> ⚠️ **Note que este arquivo contém dados sensíveis e deve ter seu acesso restrito. Ele é ignorado pelo Git.**

| Variável | Descrição | Default |
| :---: | :--- | :--- |
| `name_prefix` | Prefixo do nome dos recursos _ | _`fiap-toggle`_ |
| `aws_region` | Regiao da AWS | _`us-east-1`_ |
| `subnet_prefix` | Os 2 primeiros octetos do CIDR da VPC | _`10.12`_ |
| `db_name` | Nome do banco de dados inicial no RDS | _vazio_ |
| `db_username` | Usuário master do PostgreSQL | _vazio_ |
| `db_password` | Senha do usuário master | _vazio_ |
| `git_org` | Domínio provedor Git | _vazio_ |
| `git_repo` | Nome do repositório do provedor Git | _fiap-toggle-master-stack_ |
| `service_type` | Tipo de serviço para o ArgoCD | _ClusterIP_ |
| `grafana_pass` | Senha do usuário admin do Grafana | _vazio_ |
| `grafana_service_type` | Tipo de serviço do Grafana | _ClusterIP_ |


Copie o arquivo de exemplo e edite ele com os valores do seu ambiente.

```bash
cp terraform.tfvars.example terraform.tfvars
# [vi]/[nano] terraform.tfvars
```

<BR>

### 2. Inicialização AWS

Para a estruturação do ambiente AWS, é utilizado o **Terraform**. Ele configura todos os recursos utilizados pela ToggleMaster, como o EKS, Elasticache, DynamoDB, etc. Além de implementar os serviços, o Terraform também utiliza serviços extras da AWS para persistir o estado da infraestrutura e da configuração criada. O **S3 Bucket** é utilizado para armazenar o arquivo `terraform.tfstate`, que "mapeia" a configuração com os recursos criados no _Cloud Provider_. O Terraform também usa o **DynamoDB** para armazenar o "_state lock_" e evitar modificações concorrentes.

Esses serviços "extras" devem ser configurados antes da inicialização do Terraform, para que ele crie a persistência do estado da configuração. Por isso, o script [`init.sh`][init] está disponível para configurar o ambiente na AWS e inicializar o Terraform em seguida. Ele deve ser executado na raiz do repositório.

```bash
./init.sh
``` 

Após a inicialização do ambiente, o Terraform estará preparado para aplicar as configurações na AWS. Para isso, basta executar os comandos "Plan" e "Apply" do Terraform, conforme demonstrado abaixo.

```bash
terraform plan
terraform apply
```

> A criação dos recursos pode levar alguns minutos, principalmente por causa do cluster EKS e seus _nodes_. Ao final, será apresentada uma mensagem indicando o término da implementação, seguida dos _outputs_ gerados. Algo similar à mensagem a seguir.
> 
> ```
> Apply complete! Resources: 103 added, 0 changed, 0 destroyed.
> ```

<BR>

### 2.1 Configuração `kubectl`

Após a criação dos recursos na AWS, o cluster EKS deve estar disponível. Para acessá-lo, É necessário atualizar a configuração do `kubectl` para o acesso ao cluster. Utilize o comando abaixo para isso.

> Altere o nome do cluster caso seja diferente.

```bash
aws eks update-kubeconfig --region $(aws configure get region) --name "$(grep '^name_prefix' terraform.tfvars | cut -d '"' -f 2)-eks-cluster"
```

<BR>

### 2.2 Configuração de credenciais

Considerando a arquitetura atual do sistema ToggleMaster, algumas credenciais sensíveis só podem ser definidas após a criação da infraestrutura na AWS. Para isso, é utilizado o gerenciador de segredos da AWS (_AWS Secrets Manager_). Alguns valores são extraídos dos _outputs_ do Terraform, enquanto outros devem ser definidos manualmente. Eles são considerados sensíveis para evitar sua exposição em repositórios públicos.

⚠️ Note que os _secrets_ criados abaixo utilizam o _namespace_ igual ao prefixo do nome dos recursos utilizados no Terraform ("_fiap-toggle_", por padrão). Altere caso utilize outro nome.

#### MasterKey do microserviço Auth

É necessário definir uma chave "mestre" para o microserviço de autenticação Auth.

> **Altere o valor de exemplo, _`admin123`_, para algo mais complexo e seguro.**

```bash
aws secretsmanager create-secret \
    --name "$(grep '^name_prefix' terraform.tfvars | cut -d '"' -f 2)/master_key" \
    --description "Chave mestre para o microserviço de autenticação Auth" \
    --secret-string '{"password": "admin123"}'
```

#### Token do microserviço Evaluation

É necessário definir um _token_ para o microserviço Evaluation. No entanto, essa chave só pode ser gerada após a inicialização do microserviço Auth. Neste primeiro momento, basta criar o _secret_ com um valor aleatório. Isso é necessário para evitar falhas na inicialização dos microserviços.

> **Esse _secret_ será atualizado mais adiante.**

```bash
aws secretsmanager create-secret \
    --name "$(grep '^name_prefix' terraform.tfvars | cut -d '"' -f 2)/service_api_key" \
    --description "Chave de serviço para o microserviço Evaluation" \
    --secret-string '{"api_key": "teste"}'
```

<BR>

## 3. Build da ToggleMaster

Com o **ambiente AWS criado e os repositórios ECR disponíveis**, os microserviços da ToggleMaster podem ser enviados ao repositório de imagens ECR. As imagens dos microserviços são construídas e enviadas ao repositório automaticamente por meio de um [**Git actions workflow**][gitaction].

<BR>

### 3.1 Secrets para o build

**Antes de executar o workflow**, é necessário definir algumas variáveis sensíveis que serão utilizadas em seus passos. Essas variáveis são exclusivas para a conexão entre o GitHub e a AWS. Para isso, deve-se definir os valores a seguir devem ser definidos como "**secrets**" do repositório.

| Variável       | Descrição       |
| :------------: | :-------------- |
| `AWS_ACC_ID`   | ID da conta AWS |
| `AWS_REGION`   | Região da AWS   |
| `AWS_GIT_ROLE` | Nome da "role" da AWS para o Git Actions. _Esta role é criada pelo Terraform e pode ser consultada com `terraform output -json oidc_outputs | jq -r .git_actions_role_name`_ |

<BR>

### 3.2 Push da build

Com o _Git Actions_ ativo no repositório, **basta submeter um novo "_push_" ou "_pull request_" em qualquer arquivo dentro do diretório `build`** para que o workflow seja iniciado. Alternativamente, principalmente para o primeiro _build_, **também é possível [acionar o workflow manualmente][runflow]**.

<BR>

## 4. Configuração ArgoCD

Esta implementação usa o ArgoCD para atualizar dinamicamente a ToggleMaster no cluster EKS. O plano do Terraform já está preparado para instalar o ArgoCD e torná-lo acessível ao cluster. Entretanto, podem ser necessários alguns ajustes após a disponibilização da aplicação.

<BR>

### 4.1 (_Opcional_) Interface do ArgoCD

O ArgoCD é configurado, por padrão, para criar um serviço do tipo "_`ClusterIP`_" no K8s, a fim de evitar exposições desnecessárias e custos extras. No entanto, é possível alterar essa configuração no arquivo de [variáveis do Terraform][tfvars] (_`terraform.tfvars`_). Basta alterar de _`ClusterIP`_ para _`LoadBalancer`_.

#### ClusterIP

Com o serviço do tipo `ClusterIP`, é possível acessar a interface do ArgoCD utilizando o `port-forward` do Kubernetes, conforme o exemplo a seguir. Em seguida, a interface estará acessível no navegador com o endpoint do ambiente local e na porta encaminhada (`8080` no exemplo).

```bash
kubectl port-forward service/argocd-server -n argocd --address 0.0.0.0 8080:443
```

#### LoadBalancer

Se o serviço estiver configurado como `LoadBalancer`, o _cloud provider_ disponibilizará um _endpoint_ público para acesso à interface. É possível obtê-lo com o comando a seguir. Então, a interface estará acessível no navegador com o endpoint público da AWS.

```bash
kubectl get svc argocd-server -n argocd -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

<BR>

### 4.2 Senha inicial do ArgoCD

O usuário padrão do ArgoCD é `admin`, mas a senha é aleatória. Ela é gerada automaticamente e salva no _secret_ do K8s chamado `argocd-initial-admin-secret`. O comando a seguir usa o `kubectl` para mostrar a senha em texto claro.

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

> ⚠️ **Não se esqueça de alterar a senha após o primeiro login.**

<BR>

### 4.3 (_Opcional_) Registrar o cluster

As credenciais do cluster K8s devem ser registradas no ArgoCD, o que **só é necessário ao utilizar o ArgoCD em um cluster externo.** Se necessário, siga os passos oficiais da [documentação do ArgoCD][argodoc] para registrar o cluster.

<BR>

## 5. Configuração ToggleMaster

Com os serviços da AWS criados, o Terraform disponibilizará _outputs_ com algumas configurações que serão utilizadas pelo sistema ToggleMaster. É necessário definir essas configurações como variáveis para o ToggleMaster, como URLs de repositórios ECR, Elasticache Valkey, RDS e SQS.

<BR>

### 5.1 Aplicação personalizada no ArgoCD

Esses valores podem ser aplicados à definição do ArgoCD que implantará a ToggleMaster no cluster EKS. Para isso, o arquivo `argo_deploy.yaml.example` está disponível no diretório `argo` deste repositório. Nele, devem ser incluídos os valores corretos que serão aplicados no ambiente, conforme os _outputs_ gerados pelo Terraform.

O script `argo_update.sh` está disponível no mesmo diretório. Ele facilita o preenchimento dos valores corretos, fazendo uma cópia do exemplo e preenchendo os valores. _Também é possível editar manualmente o arquivo de exemplo, se prefirir._

```bash
./argo/argo_update.sh
```

<BR>

### 5.2 Inicialização da ToggleMaster com o ArgoCD

> **É possível incluir o sistema ToggleMaster manualmente pela interface do ArgoCD. Para isso, é necessário acessá-la conforme descrito acima.**

Ao utilizar o script acima, o manifesto `argo_deploy.yaml` será responsável por definir a aplicação personalizada no ArgoCD e sincronizará o repositório com o Kubernetes. Ele deve ser aplicado com o comando `kubectl`.

```bash
kubectl apply -f argo/argo_deploy.yaml
```

> **Esse arquivo é ignorado no Git e não deve ser publicado.**

<BR>

## 6. Validação

Nesta etapa, o sistema ToggleMaster deve estar ativo e pronto para receber mensagens. Para validar seu funcionamento, é necessário criar uma chave de autenticação com o microserviço `auth-service`, uma "feature flag" com o microserviço `flag-service` e uma regra de segmentação com o microserviço `targeting-service`.

<BR>

#### 6.1 Consulte os IPs dos serviços no cluster com o `kubectl`, conforme indicado abaixo. O resultado deve ser algo similar ao exemplo a seguir.

```bash
$ kubectl get service -n toggle
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP                               PORT(S)          AGE
analytics    ClusterIP      172.20.201.49    <none>                                    8005/TCP         86m
auth         ClusterIP      172.20.90.88     <none>                                    8001/TCP         86m
evaluation   LoadBalancer   172.20.86.71     abc614f-123.us-east-1.elb.amazonaws.com   8004:30891/TCP   86m
flag         ClusterIP      172.20.114.165   <none>                                    8002/TCP         86m
targeting    ClusterIP      172.20.93.183    <none>                                    8003/TCP         86m
```

<BR>

#### 6.2 Crie uma flag e sua regra de segmentação.

O script `eval_token.sh` facilita a criação de um token para o `evaluation-service`, a criação de uma _feature flag_ e sua regra de segmentação. Também atualiza o token e reinicializa o deployment do `evaluation-service` para que ele leia o novo secret.

```bash
./eval_token.sh
```

> Para criar o token, a flag e a segmentação, é necessário acessar os microserviços internos. O script utiliza o _port-fowarding_ para isso.

<BR>

#### 6.3 Envie mensagens para o ToggleMaster.

Neste teste, algumas mensagens são enviadas e enfileiradas no SQS. O `analytics-service` processa as mensagens e as envia para a tabela do DynamoDB. Nesse momento, é possível observar tanto o enfileiramento de mensagens no SQS quanto sua gravação no DynamoDB. Use o console da AWS para observar isso.

Na interface do ArgoCD, também é possível observar o escalonamento de pods do `analytics-service` à medida que novas mensagens são enfileiradas. Opcionalmente, é possível observar as mensagens sendo processadas no log do pod do `analytics-service`.

```bash
for i in $(seq 1000); do { curl "http://abc614f-123.us-east-1.elb.amazonaws.com:8004/evaluate?user_id=teste-$i&flag_name=enable-feature" ; } done
```

> ⚠️ **Esse comando envia muitas mensagens ao ToggleMaster, portanto pode levar um tempo, pois o serviço precisa se comunicar com a AWS. Se preferir, basta reduzir o número de mensagens enviadas para acelerar o processo.**

| [⬆️ Top](#roteiro-de-implementa%C3%A7%C3%A3o) |
| --- |

[fase3]: https://github.com/diasdmhub/fiap-toggle-master-iaas
[init]: /init.sh
[helm]: https://helm.sh/docs/intro/install
[argocdcli]: https://argo-cd.readthedocs.io/en/stable/cli_installation/
[tfvars]: /terraform.tfvars.example
[gitaction]: https://docs.github.com/en/actions/get-started/quickstart
[runflow]: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
[argodoc]: https://argo-cd.readthedocs.io/en/stable/getting_started/
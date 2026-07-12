# Evidências

> **Seguem algumas evidências da implementação do projeto.**

<BR>

### Dashboards do Grafana

Os manifestos dessas dashboards estão disponíveis no diretório `/dash` do repositório. Elas demonstram diversas métricas do sistema ToggleMaster.

![Dashboard Observabilidade](./dashboard_observabilidade.png)

![Dashboard Service Map](./dashboard_service_map.png)

<BR>

### Trace distribuído no Tempo

Esta é uma demonstração do _trace_ de requisições no Grafana Tempo.

![Trace Distribuído Tempo](./grafana_tempo_trace.png)

<BR>

### Notificação de incidente no Discord

O Discord foi escolhido como uma das plataformas de notificação devido à sua simplicidade de integração. A imagem a seguir evidencia essa integração.

![Notificação Discord](./notificacao_discord.jpg)

<BR>

### Registro da automação de Self-Healing no AWS Lambda

Com o Tempo, as requisições podem ser rastreadas rapidamente, conforme demonstrado na imagem a seguir.

#### Requisição:

```shell
# curl "http://aef8d90b5616c4bb691a9c89892d7274-2051342699.us-east-1.elb.amazonaws.com:8004/evaluate?user_id=testando-100&flag_name=enable-feature"
{"flag_name":"enable-feature","user_id":"testando-100","result":true}
```

#### Consulta:

![Notificação Discord](./self_healing_lambda_log.png)
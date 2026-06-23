# Tech Challenge Fase 4 - Stack "ToggleMaster"

> Análise geral e implementação comentada do "desafio" da Fase 4 do curso DevOps e Arquitetura Cloud da FIAP.

<BR>

## Considerações

- A stack de monitoração tem o perfil de uma ferramenta de plataforma, não uma aplicação de negócio. Por isso o novo módulo de monitoramento do Terraform (`/modules/monitoring`) foi adicionado.
- A implementaçao de APMs como Datadog ou New Relic é desconsiderada neste cenário pois são ferramentas privadas de custo elevado e com acesso educacional relativamente invasivo. O Datadog exige conexão com serviços terceiros (_GitHub_) para acesso educativo, e o portal do New Relic estava recusando conexões (_`ERR_CONNECTION_REFUSED`_) durante o desenvolvimento desta fase. Sendo assim, entendo estas ferramentas não trazem benefícios aos usuários para fins educacionais. Portanto, o Grafana Tempo é utilizado nesta, pois ele já é integrado ao Grafana, não possui custos e é open-source.
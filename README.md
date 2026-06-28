# Tech Challenge Fase 4 - Stack "ToggleMaster"

> Análise geral e implementação comentada do "desafio" da Fase 4 do curso DevOps e Arquitetura Cloud da FIAP.

<BR>

## Considerações

- A stack de monitoração tem o perfil de uma ferramenta de plataforma, não uma aplicação de negócio. Por isso ela foi adicionada como um novo módulo de monitoramento do Terraform (`/modules/mon`).
- A implementaçao de APMs como Datadog ou New Relic é desconsiderada nesta fase pois são ferramentas privadas de custo elevado e com acesso educacional relativamente invasivo. O Datadog exige conexão com serviços terceiros (_GitHub_) para acesso educativo, e o portal do New Relic estava recusando conexões (_`ERR_CONNECTION_REFUSED`_) durante o desenvolvimento desta fase. Sendo assim, entendo que essas ferramentas não trazem benefícios aos usuários para fins educacionais. Portanto, o Grafana Tempo é utilizado, pois ele já é integrado ao Grafana, não possui custos e é open-source.
- O script de teste faz automaticamente:
    - Descobre o LoadBalancer do evaluation-service via `kubectl`
    - Abre port-forwards para os serviços internos (_`auth`, `flag`, `targeting`_)
    - Recupera a master key do AWS Secrets Manager
    - Cria 4 flags com percentuais diferentes (50%, 10%, 80%, 0%)
    - Dispara 200 avaliações por padrão com user IDs e flag names variados
    - Gera requests inválidas para criar error spans
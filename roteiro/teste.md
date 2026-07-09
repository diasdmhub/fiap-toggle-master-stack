| [↩️ Voltar](/) |
| --- |

# Teste automatizado dos serviços

🔶 O [**script de teste** (`test-traffic.sh`)][scriptest] realiza automaticamente:

- Descobre o LoadBalancer do evaluation-service via `kubectl`
- Abre port-forwards para os serviços internos (_`auth`, `flag`, `targeting`_)
- Recupera a master key do AWS Secrets Manager
- Cria 4 flags com percentuais diferentes (50%, 10%, 80%, 0%)
- Dispara 150 avaliações por padrão com user IDs e flag names variados
- Gera requests inválidas para criar error spans

| [⬆️ Top](#teste-automatizado-dos-servi%C3os) |
| --- |

[scriptest]: /test-traffic.sh
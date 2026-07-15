# 09 — Segurança, Privacidade, Governança e Observabilidade

## Segurança e governança

- **Controle de acesso por perfil e por carteira** (doc 07);
- **Criptografia em trânsito e em repouso**: TLS (Railway) + Postgres criptografado; segredos via `config/credentials.yml.enc` e vault do Railway;
- **Cofre de segredos** para credenciais do Sankhya e do Claude — nunca em código, log ou frontend;
- **Logs e trilha de auditoria**: `sync_runs`, `agent_runs`, atividades com autor, transferências de carteira com autor/data;
- **Backups e testes de restauração**: backup automático do Postgres (Railway) + teste de restore documentado por trimestre;
- **Política de retenção e descarte**: dados espelhados seguem o ERP; `agent_runs` retidos por 12 meses; definir descarte de rascunhos de mensagens;
- **Controle de exportações**: exportar dados exige perfil gestor+ e é registrado;
- **Revisão periódica de acessos**: rotina mensal do administrador (lista de usuários ativos × papéis × carteiras);
- **LGPD**: minimização (só dados comerciais necessários), base legal legítimo interesse comercial, dados pessoais de contatos limitados a nome/telefone/e-mail corporativos, direito de eliminação respeitando obrigações fiscais.

## Regras de segurança da IA

Ver doc 06 (limites obrigatórios + tabela permitido/proibido). Reforços de implementação:

- Ferramentas do agente com **allowlist** — capacidade inexistente é capacidade negada;
- Validação de schema nas saídas; resposta fora do esquema → `agent_run.status = invalid_schema` + retry limitado;
- Rascunhos (mensagem/cotação) só saem do sistema por ação humana explícita;
- Isolamento entre vendedores testado automaticamente (testes de segurança, doc 10).

## Métricas técnicas (14.1)

| Grupo | Métricas |
|---|---|
| Sankhya | Disponibilidade e latência do gateway; falhas de autenticação e sincronização; registros pendentes ou duplicados |
| Claude | Chamadas, custo, tokens e latência; erros de ferramentas e respostas inválidas |
| Qualidade analítica | Acurácia das projeções (previsto × realizado) e das recompras (confirmadas/expiradas) |
| Aplicação | Erros 5xx, tempo de resposta, filas Solid Queue (jobs atrasados/falhos) |

Fontes: `sync_runs`, `agent_runs`, `projections`/`repurchase_predictions` (comparação com realizado), logs Rails. Exibição: tela de administração + logs Railway. (Ferramenta APM externa é opcional; decidir na execução se necessário.)

## Alertas (14.2)

| Alerta | Exemplo de condição |
|---|---|
| **Integração** | Sincronização atrasada (sem sucesso em 2× o intervalo esperado), token inválido, timeout recorrente |
| **Dados** | Cliente sem vendedor (sem carteira vigente), produto sem categoria ou custo ausente |
| **Conciliação** | Divergência entre faturamento do ERP e base analítica acima de tolerância |
| **IA** | Resposta fora do esquema, ferramenta indisponível, dado insuficiente recorrente, orçamento diário de tokens excedido |
| **Negócio** | Meta ausente para vendedor ativo, projeção crítica (provável < X% da meta), carteira sem atualização |

Implementação MVP: job periódico `Alerts::ScanJob` que grava em tabela `alerts` (severidade, grupo, mensagem, resolved_at) exibida ao admin/gestor; canal externo (e-mail) para severidade alta. Evoluir depois se necessário.

## Qualidade dos dados

- Toda entidade espelhada guarda `raw` e timestamp de sync — permite reprocessar sem novo fetch;
- Reconciliação noturna compara contagens/somas ERP × local e alimenta o alerta de conciliação;
- Dado crítico exibido ao usuário carrega o carimbo "atualizado em HH:MM" (padrão já usado no header).

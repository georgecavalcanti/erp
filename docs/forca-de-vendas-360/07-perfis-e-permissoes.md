# 07 — Perfis e Permissões (RBAC)

## Situação atual

Hoje o sistema tem **um único admin** (`db/seeds.rb`, `ADMIN_EMAIL`/`ADMIN_PASSWORD`) e nenhuma autorização: todo usuário logado vê tudo. Este documento define o modelo de perfis que substitui isso.

## Perfis

| Perfil | Escopo |
|---|---|
| **Vendedor** | Sua carteira, meta, clientes, atividades, prioridades e copiloto |
| **Representante** | Mesmas permissões do vendedor, limitadas à carteira contratualmente atribuída |
| **Coordenador** | Equipe sob sua gestão, planos, prioridades e desempenho |
| **Gestor comercial** | Todas as equipes, metas, políticas, critérios e forecast |
| **Administrador** | Integrações, usuários, configurações, auditoria e modelos |
| **Diretoria** | Visão consolidada de resultado, risco, margem e expansão (somente leitura) |

## Isolamento de carteira (regra de ouro)

> **Um vendedor não poderá visualizar clientes, vendas ou recomendações de outra carteira sem autorização explícita.**

## Modelo de dados (ver doc 04)

- `users.role` (enum) · `users.salesperson_id` (obrigatório para vendedor/representante) · `users.manager_id` (vínculo com coordenador).
- `wallets`: vendedor ↔ cliente com vigência (`ends_on IS NULL` = vigente), tipo de responsabilidade e região.

## Implementação

### Camada de autorização

Criar `app/models/current.rb` já existe (`Current.user`); adicionar:

1. **Policy objects** simples em `app/policies/` (sem gem, seguindo o estilo do projeto — ou Pundit se preferir na execução):
   - `authorized_salesperson_ids(user)` → ids de vendedores visíveis: o próprio (vendedor/representante), a equipe (coordenador via `manager_id`), todos (gestor/admin/diretoria).
   - `authorized_partner_ids(user)` → parceiros das carteiras vigentes dos vendedores autorizados.
2. **Escopo obrigatório nos controllers**: estender `analytics_filters.rb` para interseccionar qualquer filtro de vendedor/parceiro com o escopo autorizado (nunca confiar no filtro vindo do cliente).
3. **Escopo nas ferramentas do agente**: o `tool_registry` injeta `Current.user`; toda ferramenta filtra por `authorized_*` antes de executar. O modelo nunca decide escopo.
4. **Navegação por perfil**: `AppLayout.vue` mostra itens conforme `role` (props Inertia compartilhadas via `inertia_share`).

### Autorização explícita de exceções

Transferências/compartilhamentos de carteira são operações do gestor comercial (tela de administração de carteiras), registradas com autor e data — nunca automáticas, nunca pelo agente.

### Auditoria de acesso

- Log estruturado de cada request com `user_id` e escopo aplicado.
- `agent_runs` registra o usuário de cada execução do agente.
- Revisão periódica de acessos (rotina do administrador — doc 09).

## Matriz de acesso por recurso (resumo)

| Recurso | Vendedor/Repr. | Coordenador | Gestor | Admin | Diretoria |
|---|---|---|---|---|---|
| Cockpit / plano do dia próprios | ✅ | ✅ (da equipe) | ✅ (todos) | ✅ | 👁 consolidado |
| Cliente 360 (da carteira) | ✅ | ✅ equipe | ✅ | ✅ | 👁 |
| Copiloto Claude | ✅ | ✅ | ✅ | ✅ | — |
| Metas: ver / definir | ✅ / — | ✅ equipe / — | ✅ / ✅ | ✅ / ✅ | 👁 / — |
| Carteiras: ver / transferir | próprias / — | equipe / — | ✅ / ✅ | ✅ / ✅ | 👁 / — |
| Pesos do score e políticas | — | — | ✅ | ✅ | — |
| Usuários e integrações | — | — | — | ✅ | — |
| Auditoria (`agent_runs`, sync) | — | — | 👁 | ✅ | — |

(✅ = ler e agir · 👁 = somente leitura · — = sem acesso)

## Migração do estado atual

1. Migration adiciona `role` (default `administrador` para o admin seed atual) e vínculos.
2. Popular `wallets` a partir do vínculo vendedor↔parceiro do Sankhya (parceiro tem CODVEND) na carga inicial; a partir daí, gestão manual pelo gestor.
3. Telas existentes (Dashboard, Situação, etc.) passam a respeitar o escopo: para perfis de vendedor, tudo já filtrado pela própria carteira.

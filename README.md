# Faturamento

Painel de faturamento que importa planilhas de notas exportadas do ERP (padrão
Sankhya — "Cabeçalho da Nota") e entrega visualizações mês a mês por parceiro e
por vendedor, evolução, devoluções e controle de inadimplência.

## Stack

- **Ruby on Rails 8.1** + Ruby 3.3
- **PostgreSQL 17** (Docker isolado)
- **Vite + Inertia.js + Vue 3 + TypeScript**
- **Tailwind CSS 4** · **ECharts** (gráficos)
- Autenticação nativa do Rails 8 (login de admin)
- Importação de `.xls`/`.xlsx`/`.csv` via **roo** + **roo-xls**

## Requisitos

- Ruby 3.3, Node 20+, Docker

## Setup

```bash
# 1. Banco (Postgres isolado na porta 5433)
docker compose up -d db

# 2. Dependências
bundle install
npm install

# 3. Banco + admin
bin/rails db:prepare   # cria + migra
bin/rails db:seed      # cria o admin
```

Admin padrão (troque em produção via `ADMIN_EMAIL` / `ADMIN_PASSWORD`):

- **e-mail:** `admin@faturamento.local`
- **senha:** `faturamento123`

## Rodando

```bash
bin/dev            # sobe Rails (:3100) + Vite (:3136)
```

Acesse http://localhost:3100.

> As portas (Postgres **5433**, web **3100**, Vite **3136**) foram escolhidas
> para não conflitar com outros projetos que usam 5432/3000/3036.

## Importando uma planilha

Menu **Importações** → selecione o arquivo do ERP (`.xls`) → **Importar**.

A importação é **idempotente**: cada nota é identificada pelo `Nro. Único`, então
reenviar o mesmo período **atualiza** as notas existentes (sem duplicar) e
**preserva** os pagamentos já marcados manualmente. Linhas de total/rodapé são
ignoradas automaticamente.

## Arquitetura

```
app/
  models/         Company, Partner, Salesperson, Invoice (fato), ImportBatch
  services/
    spreadsheet_importer.rb   Lê a planilha (cabeçalho por rótulo) e faz upsert
    payment_terms_parser.rb   "V BOLETO - 30/45" -> parcelas e vencimentos
    invoice_classifier.rb     Venda vs Devolução (por tipo de operação)
    analytics.rb              Agregações (mês a mês, ranking, evolução, recebíveis)
  serializers/    InvoiceSerializer
  controllers/    dashboard, salespeople, partners, receivables, returns, imports
  frontend/
    pages/        Dashboard, Salespeople, Partners, Receivables, Returns, Imports, auth/Login
    components/   FilterBar, KpiCard, ChartCard, BaseChart, RankingReport, ...
    layouts/      AppLayout
```

### Conceitos-chave

- **Faturamento líquido** = vendas − devoluções (cada nota tem `signed_value`).
- **Vencimento** derivado do prazo de negociação; à vista = data da negociação.
- **Inadimplência** = venda **não paga** com vencimento **no passado** (derivada,
  não vem da planilha). O admin marca o que foi pago em *Inadimplência*.
- **Extensível**: toda pivotagem vive em `Analytics` e cada nota guarda a linha
  original em `invoices.raw` (jsonb) — novas visualizações não exigem reimportar.

## Deploy

Produção usa `DATABASE_URL` (ex.: Railway). Rode `bin/vite build` e as migrations.

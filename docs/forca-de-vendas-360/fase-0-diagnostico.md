# Fase 0 — Diagnóstico Técnico do Sankhya (resultado)

> Executado em 15/07/2026 contra o gateway de **produção** (`api.sankhya.com.br`), via `Sankhya::Client#execute_query` (somente leitura). Todas as tabelas necessárias estão acessíveis ao usuário de integração atual.

## 1. TOPs em uso (24 meses, CODEMP 1)

| TOP | Descrição | TIPMOV | Qtd 24m | Uso no FV360 |
|---|---|---|---|---|
| 1001 | PEDIDO DE VENDA PRIVADO | P | 32.162 | **Pedidos** (sync atual mantém) |
| 1000 | ORÇAMENTO DE VENDA | P | 31.868 | **Cotações** — insumo novo para projeção/priorização |
| 1101 | VENDA NF-E PRIVADO | V | 31.122 | **Vendas** (sync atual) |
| 1201 | DEVOLUÇÃO DE VENDA - NF PRÓPRIA | D | 947 | **Devoluções** (sync atual) |
| 1202 | DEVOLUÇÃO DE VENDA - NF TERCEIROS | D | 107 | **Devoluções** (sync atual) |
| 1010 | PEDIDO DE VENDA - GERAL | P | 2 | Marginal — monitorar |
| 1401/1402/1450/1451/1301… | Compras e pedidos de compra | C/O/E | ~4.4k | Fora do escopo comercial |
| 1195/1196/1493/1499 | Ajustes/implantação de estoque | V/C | ~190 | **Excluir** das vendas (TIPMOV=V mas não é venda) |
| 1124/1151/1157/1163/1198 | Remessas, amostras, complementar, denegada | V | ~130 | Excluir; observar 1198 (denegada) |

> Atenção: filtrar vendas **por TOP (1101)**, nunca por TIPMOV=V — ajustes de estoque e remessas também têm TIPMOV=V.

## 2. Horizonte de histórico

- `MIN(DTNEG)` geral: 14/09/2022, mas o volume real começa em **dez/2024** (go-live do ERP; 2024 tem só 171 notas com itens).
- **Backfill efetivo: dez/2024 → hoje (~19 meses)**, não os 24 idealizados. Sazonalidade anual completa só a partir de 2026.

## 3. Volumetria (dimensionamento do backfill)

| Ano | Itens (TGFITE) | Notas distintas |
|---|---|---|
| 2024 (dez) | 1.594 | 171 |
| 2025 | 534.090 | 55.444 |
| 2026 (até jul) | 425.558 | 44.376 |
| **Total** | **~961 mil** | **~100 mil** |

Paginação keyset por NUNOTA (padrão existente) em lotes na madrugada dá conta; estimar ~2h de backfill de itens.

## 4. Produtos e categorias

- **TGFPRO**: 3.249 produtos (2.637 ativos). Campos-chave: `DESCRPROD`, `CODGRUPOPROD`, `CODVOL` (unidade), `MARCA`/`CODMARCA` (pouco usados), `REFERENCIA`, `REFFORN`, `CODPARCFORN` (fornecedor), `NCM`, `USOPROD` ('R' = revenda), `ATIVO`, `DTALTER` (✔ sync incremental), `DECQTD`/`DECVLR`.
- **TGFGRU**: 30 grupos, hierárquicos por faixa de código (`ANALITICO` S/N). Ex.: 1010000000 "MERCADORIAS PARA REVENDA JATTO" → PAPEIS, SACOS PARA LIXO, DESCARTÁVEIS PLÁSTICOS, QUÍMICOS, PANOS, EPI, ACESSÓRIOS, COPA, EXPEDIENTE. Grupos 1020xxxxxxx são da linha Leão (importar todos; só 30 linhas).

## 5. Itens e margem (regra crítica validada)

Amostra real de venda 1101 (NUNOTA 125075) validada contra a capa:

- **`VLRNOTA` (capa) = Σ`VLRTOT` (itens) − Σ`VLRDESC` (itens)** → o desconto do item NÃO está embutido em `VLRTOT`.
- **Valor líquido do item = `VLRTOT − VLRDESC`**; a capa espelha em `VLRDESCTOTITEM`.
- **`CUSTO` (unitário) vem preenchido nos itens de venda** → **margem do item = (VLRTOT − VLRDESC) − QTDNEG × CUSTO**.
- `VLRCUS` espelha o preço (ignorar). Campos custom `AD_MARGEM`/`AD_VLRRENT`/`AD_RENT`/`AD_COMISS` existem mas estão **nulos** nas vendas — não usar.
- Item tem `CODVEND` próprio (vendedor por item), `PENDENTE`, `QTDENTREGUE`, `STATUSNOTA` e `DTALTER` (✔ incremental).
- TGFITE tem `CODEMP` direto (filtro sem join quando conveniente).

## 6. Custos (TGFCUS)

10.888 registros, **atualizados diariamente** (última atualização = data da consulta). Campos: `CUSGER` (gerencial), `CUSMED`, `CUSREP` (reposição), `CUSMEDICM`/`CUSSEMICM`, `DTATUAL`, por CODEMP/CODLOCAL. Histórico por data → permite custo vigente na data da venda. Fonte para custo *atual* do produto; para margem de venda passada, preferir `TGFITE.CUSTO` (congelado na venda).

## 7. Estoque (TGFEST)

1.432 linhas (1.422 produtos) na empresa 1, local padrão 10100. Campos: `ESTOQUE`, `RESERVADO`, `WMSBLOQUEADO`, `ATIVO`. Snapshot simples e barato (30 min ok).

## 8. Preços (TGFNTA/TGFTAB/TGFEXC)

- TGFNTA: cabeçalhos de tabela ("TABELA LEÃO 1", "CHEIA 5%", "MENOR 0,5%", "TABELA 5/6"…).
- TGFTAB: 585 vigências (`NUTAB`, `CODTAB`, `DTVIGOR`) — **atualizadas até a data da consulta** (preços mudam com frequência).
- TGFEXC: **27.578 itens de preço** em 564 vigências — volume pequeno, sync de 2h tranquilo.
- Resolução do preço vigente: parceiro (`TGFPAR.CODTAB`) → maior `DTVIGOR ≤ hoje` em TGFTAB → `TGFEXC.VLRVENDA`.

## 9. Parceiros (TGFPAR) — achados que mudam o plano

- 5.855 clientes ativos; **4.732 (81%) com `CODVEND`** → seed de carteiras viável; **1.123 sem vendedor** → alerta "cliente sem vendedor" já nasce com público real.
- **`LIMCRED` praticamente não é usado (8 de 5.855)** → restrição de crédito virá de **inadimplência (TGFFIN, já sincronizada) + `BLOQUEAR`/`MOTBLOQ` (9 bloqueados hoje)**, não de limite cadastral.
- **Segmentação cadastral não existe na prática**: `CODTIPPARC` = 0 para 5.852 clientes (taxonomia rica disponível no ERP — segmento, potencial, cobertura de visita — mas vazia); `AD_CURVA` (curva ABC custom) preenchida em só 5. → **O FV360 derivará segmentação/curva analiticamente da própria base**; preencher cadastro do ERP fica como recomendação ao gestor.
- Endereço: `CODCID` → TSICID (`NOMECID`, `CODMUNFIS` IBGE, `UF` código) → TSIUFS (sigla). `CGC_CPF`, `CODBAI` (bairro), `CODREG` (região), `CODROTA`, `DTULTNEGOC` disponíveis.
- `CODPARCGRUECONOMICO` existe para grupo econômico (avaliar uso na dedup de filiais que hoje é por nome).

## 10. Vendedores (TGFVEN)

- 60 cadastrados, 53 ativos: `TIPVEND` V=43 (vendedores), C=6 (compradores), G=1 (gerente), null=3.
- **`CODGER` = 0 para todos e `EMAIL` vazio para todos** → hierarquia de equipe e vínculo usuário↔vendedor serão **geridos no FV360** (telas da Sprint 3), sem seed do ERP.
- `PARTICMETA` existe (participação em meta) mas sem uso aparente.

## 11. Cotações (TOP 1000) — comportamento real (90 dias)

| STATUSNOTA | PENDENTE | Qtd | Valor |
|---|---|---|---|
| A (aguardando lib.) | S | 388 | R$ 175 mil |
| L (liberada) | S | 3.903 | R$ 9,05 mi |
| L | N | 4.191 | R$ 6,2 mi |

Interpretação: `PENDENTE='S'` = orçamento ainda não convertido em pedido (aberto); `'N'` = convertido/encerrado. Taxa de conversão aparente ~50% — insumo direto para "cotações avançadas" na projeção provável e histórico de conversão. Validar interpretação com o gestor comercial na Sprint 4.

## 12. Metas

**`TGFMET` existe e está vazia** — metas não são geridas no ERP. Confirmado: metas serão cadastradas e geridas no FV360 (Sprint 3), pelo gestor comercial.

## 13. Pendências humanas (não bloqueiam Sprints 1–2)

- [ ] Gestor comercial: confirmar interpretação de cotações (item 11) e regra de "cotação avançada".
- [ ] Gestor comercial: fornecer metas por vendedor para carga inicial (Sprint 3).
- [ ] Gestor comercial: validar carteiras derivadas do `CODVEND` (Sprint 3) e definir capacidade diária de ações.
- [ ] Responsável Sankhya: limites de rate do gateway para syncs de 10 min (nenhum limite atingido no diagnóstico; validar em produção contínua).
- [ ] Responsável Sankhya: avaliar preenchimento futuro de `CODTIPPARC`/segmento no cadastro.

## Decisões derivadas do diagnóstico (aplicar nas sprints)

1. Vendas sempre por TOP explícita (1101), nunca por TIPMOV.
2. Margem de venda: `TGFITE.CUSTO` congelado; custo atual: `TGFCUS.CUSGER`.
3. Valor líquido de item: `VLRTOT − VLRDESC` (conferir `VLRNOTA` na conciliação).
4. Backfill: dez/2024 em diante.
5. Cotações (TOP 1000) entram como nova entidade sincronizada (junto com pedidos, mesma estrutura de `orders` com `kind`).
6. Restrição de crédito = inadimplência + bloqueio cadastral (não `LIMCRED`).
7. Carteiras: seed por `CODVEND`; hierarquia e usuários geridos no FV360.
8. Segmentação/curva ABC: calculadas analiticamente na base (não do cadastro).

# 01 — Visão e Escopo

## Missão do produto

Transformar os dados operacionais da Jatto em uma sequência diária de decisões comerciais, indicando ao vendedor **o que fazer, com qual cliente, por que agir e qual impacto** a ação pode gerar.

A primeira versão não pretende substituir o ERP nem construir um CRM completo. O foco é um **cockpit que conduza o vendedor à meta**, detectando recompras, clientes em risco, quedas de consumo, oportunidades de cross-sell e negociações com maior probabilidade de fechamento.

## Perguntas respondidas diariamente

1. Quanto já vendi e qual é minha margem?
2. Quanto falta para atingir a meta?
3. Mantendo o ritmo atual, onde vou chegar?
4. Quais componentes sustentam ou ameaçam minha projeção?
5. Quais clientes devo priorizar hoje?
6. Quais recompras, cotações ou expansões podem fechar o gap?
7. Que abordagem devo utilizar com cada cliente?

## Princípios de experiência

- **Mobile-first**: operação simples pelo celular e pelo computador.
- **Ação antes de relatório**: toda análise relevante deve gerar uma recomendação executável.
- **Explicabilidade**: cada prioridade deve apresentar motivos, dados e impacto potencial.
- **Controle humano**: ações comerciais sensíveis exigem aprovação do usuário.
- **Resiliência**: os dados e indicadores básicos permanecem acessíveis mesmo se o Claude estiver temporariamente indisponível.

## Objetivos estratégicos

| Objetivo | Resultado operacional esperado |
|---|---|
| Visão 360 da carteira | Consolidar vendas, margem, frequência, mix, crédito, estoque e relacionamento por cliente |
| Condução à meta | Decompor o gap em ações possíveis dentro dos dias úteis restantes |
| Previsibilidade | Projetar cenários conservador, provável e potencial com componentes rastreáveis |
| Retenção | Detectar atraso de recompra, queda de consumo e risco de inatividade |
| Expansão | Identificar categorias ausentes, produtos complementares e potencial não capturado |
| Produtividade | Priorizar um número executável de ações diárias e reduzir o tempo de preparação |
| Aprendizado | Comparar previsão, recomendação, ação e resultado para recalibrar os modelos |

## Escopo do MVP

### Incluído

- Integração Sankhya, metas, cockpit, projeção e gap
- Recompra, risco, queda, cross-sell e priorização
- Cliente 360, plano diário e copiloto Claude
- Registro de atividades, dashboard do gestor e auditoria
- Feedback das recomendações e receita influenciada

### Não incluído inicialmente

- Emissão definitiva de pedidos
- Aprovação de preços e descontos
- Comissionamento e cobrança
- Roteirização avançada e e-commerce B2B
- Substituição do Sankhya ou do RD Station

## Critérios de aceite do MVP

1. O faturamento exibido coincide com o Sankhya.
2. Cancelamentos e devoluções são considerados corretamente.
3. Cada vendedor visualiza somente sua carteira.
4. A meta está vinculada ao vendedor e ao período corretos.
5. A projeção apresenta componentes rastreáveis e nível de confiança.
6. A recompra indica data, valor e confiança.
7. A prioridade apresenta motivo, potencial e restrições.
8. O plano diário respeita a capacidade comercial.
9. O Claude utiliza apenas ferramentas autorizadas e não inventa dados.
10. O gestor acompanha a equipe e os desvios.
11. O sistema registra a ação e o resultado da recomendação.
12. A aplicação funciona adequadamente no celular.
13. A indisponibilidade do Claude não impede a consulta dos dados.
14. Falhas temporárias do Sankhya não apagam a base sincronizada.

## Resultado esperado na prática

Exemplo de orientação ao vendedor:

> "Você atingiu 64% da meta e deveria estar em 69% neste momento. Sua projeção provável é de 93%, deixando um gap estimado de R$ 12.600. Foram identificados oito clientes capazes de cobrir esse valor: três recompras atrasadas, duas cotações avançadas e três oportunidades de expansão de mix."

Plano diário ilustrativo:

| Prioridade | Cliente | Motivo | Potencial | Ação |
|---|---|---|---|---|
| 1 | Empresa Alfa | Recompra atrasada e alta regularidade | R$ 5.800 | Ligar e confirmar reposição |
| 2 | Empresa Beta | Cotação avançada sem retorno | R$ 4.300 | Retomar negociação |
| 3 | Empresa Gama | Categoria complementar ausente | R$ 3.700 | Apresentar descartáveis |
| 4 | Empresa Delta | Queda de consumo de 31% | R$ 2.900 | Diagnosticar perda de volume |

A plataforma deixará de ser apenas um sistema de consulta e se tornará um **gestor digital da carteira**: acompanha continuamente o vendedor, recalcula a rota e transforma o gap da meta em um plano executável.

# Contexto de `docs/`

Este diretório contém a documentação durável do projeto.
## Fontes por responsabilidade

- [`vision.md`](vision.md) — autoridade para produto, UX, escopo e decisões
  confirmadas. Hipóteses abertas permanecem aqui até serem decididas.
- [`ui-architecture.md`](ui-architecture.md) — arquitetura-alvo da janela,
  estado visual e fronteiras da UI; não é um inventário exato dos nomes atuais
  no código.
- [`technical-plan.md`](technical-plan.md) — estado implementado,
  recomendações técnicas, riscos, validação e sequência de trabalho. Não fecha
  decisões de produto que `vision.md` mantém abertas.
- [`research/CONTEXT.md`](research/CONTEXT.md) — método, briefs, relatórios e
  síntese da pesquisa técnica.
- [`reference/CONTEXT.md`](reference/CONTEXT.md) — registos históricos que
  preservam evidência sem competir com as fontes atuais.

Novos documentos só devem ser adicionados quando tiverem uma responsabilidade
própria, como uma decisão arquitetural, uma especificação de comportamento ou
uma investigação técnica. Um índice, instrução de pasta ou fronteira local
deve ficar no `CONTEXT.md` mais próximo.

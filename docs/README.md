# Documentação

Este diretório contém a documentação durável do projeto. O `README.md` na raiz
é o ponto de entrada.

## Documentos

- [Visão e plano atual](vision.md)
- [Plano técnico inicial](technical-plan.md)
- [Arquitetura de UI](ui-architecture.md)
- [Plano de pesquisa técnica](research/README.md)

## Como usar os documentos

- [`vision.md`](vision.md) é a fonte de verdade para produto, UX, escopo e
  decisões confirmadas pelo Bernardo. As hipóteses abertas permanecem aí até
  serem decididas.
- [`ui-architecture.md`](ui-architecture.md) define a estrutura da janela, o
  estado visual e as fronteiras da UI. Descreve a arquitetura-alvo e não é um
  inventário exato dos nomes atuais no código.
- [`technical-plan.md`](technical-plan.md) regista o estado implementado, as
  recomendações técnicas, os riscos, a validação e a sequência de trabalho.
  Não substitui `vision.md` nem fecha decisões que este mantenha abertas.
- [`research/README.md`](research/README.md) explica o processo da pesquisa;
  [`research/synthesis.md`](research/synthesis.md) e os reports são evidência e
  recomendações condicionais, não decisões de produto.
- [`provisional/`](provisional/) contém registos de trabalho e validação
  histórica. Serve para preservar evidência, mas não é fonte de verdade.

Novos documentos só devem ser adicionados quando tiverem uma responsabilidade própria, como uma decisão arquitetural, uma especificação de comportamento ou uma investigação técnica.

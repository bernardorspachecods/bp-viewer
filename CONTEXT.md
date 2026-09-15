# Contexto do repositório

Este ficheiro orienta a repo-mãe `bp-viewer`.
## Estrutura

- [`Package.swift`](Package.swift) — manifesto, produtos, targets e dependências
  Swift.
- [`Sources/CONTEXT.md`](Sources/CONTEXT.md) — fronteiras dos targets Swift e
  respetivos contextos locais.
- [`Tests/CONTEXT.md`](Tests/CONTEXT.md) — testes do package e relação com os
  runners executáveis.
- [`Fixtures/CONTEXT.md`](Fixtures/CONTEXT.md) — corpora controlados para
  validação manual.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — mapa da documentação durável; as
  autoridades específicas ficam dentro dessa pasta.
- [`scripts/CONTEXT.md`](scripts/CONTEXT.md) — launchers locais de build e
  desenvolvimento.
- [`Resources/CONTEXT.md`](Resources/CONTEXT.md) — recursos do bundle macOS.
- [`AGENTS.md`](AGENTS.md) — regra específica para fechar rondas que alterem a
  app.

`.build/`, `.swiftpm/` e `DerivedData/` são artefactos ou estado gerado; não são
entradas de desenvolvimento nem devem receber contexto durável.

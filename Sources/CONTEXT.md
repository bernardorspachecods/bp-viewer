# Contexto de `Sources/`

Este diretório contém os targets Swift definidos em [Package.swift](../Package.swift).

- [`BPViewerCore/`](BPViewerCore/CONTEXT.md) — modelos e lógica partilhável
  para filesystem, tabs, Markdown, LaTeX e merge/edição.
- [`BPViewerApp/`](BPViewerApp/CONTEXT.md) — app macOS SwiftUI/AppKit e a
  coordenação do estado da sessão.
- `BPViewerContractRunner/` — contratos executáveis do adapter Markdown e da
  cadeia LaTeX/process runner.
- `BPViewerFoundationRunner/` — contratos executáveis das fundações de
  filesystem, árvore, tabs, persistência e edição/merge.
- `BPViewerTabPrototype/` e `BPViewerWindowTabPrototype/` — protótipos
  isolados de comportamento de tabs; não são a app principal.

Os runners e protótipos não devem criar uma segunda implementação da app:
extraem ou exercitam seams do core quando isso for possível. O estado atual e a
arquitetura estão em [`docs/current-state.md`](../docs/current-state.md),
[`docs/technical/architecture.md`](../docs/technical/architecture.md) e
[`docs/technical/ui-architecture.md`](../docs/technical/ui-architecture.md).

# Contexto de `BPViewerCore`

`BPViewerCore` concentra lógica sem UI que pode ser exercitada pelos runners e
consumida pela app macOS. É a fronteira para manter parsing, resolução,
filesystem, estado puro e processos separados de SwiftUI/AppKit.

Áreas principais:

- `FileSystemFoundation.swift` — tipos de documento, incluindo imagens, e scanner lazy/recursivo.
- `SessionModels.swift` — modelos puros de tabs, preview, edição, posições de
  leitura e estado persistido.
- `DocumentDiff.swift` — modos e baselines de comparação, providers de disco/Git
  e motor puro de diff reutilizável por Markdown, JSON e futuros editores.
- `DocumentTabSession.swift` — invariantes de abertura, seleção, fecho e
  reordenação de tabs.
- `WorkspaceSessionCoordinator.swift` — persistência de workspace, estado
  global, roots/autorizações LaTeX e snapshots.
- `DocumentOpenCoordinator.swift` — resolução de URLs, tipos suportados e
  contexto/root LaTeX sem ações de UI.
- `JSONAdapter.swift` — validação e formatação determinística de JSON para
  preview.
- `CSVAdapter.swift` — parsing e geração de HTML estático para preview CSV.
- `TextSearch.swift` — correspondência textual normalizada e navegação circular
  reutilizável pela pesquisa da app.
- `MarkdownAdapter.swift`, `MarkdownEditing.swift`, `MarkdownMerge.swift`,
  `MarkdownPreviewLink.swift` e `MathMLRenderer.swift` — renderização,
  edição/merge e resolução de links Markdown.
- `LatexAdapter.swift`, `LatexRootDiscovery.swift`, `LatexRenderCache.swift` e
  `LatexTabContextPersistence.swift` — descoberta de root, execução/cache,
  persistência de contexto e preview LaTeX/PDF.

Contratos públicos e comportamento devem continuar alinhados com o
[estado atual](../../docs/current-state.md) e a
[arquitetura técnica](../../docs/technical/architecture.md). Alterações neste
módulo devem ser verificadas pelos runners relevantes antes de depender da UI.

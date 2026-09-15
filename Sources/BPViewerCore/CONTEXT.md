# Contexto de `BPViewerCore`

`BPViewerCore` concentra lógica sem UI que pode ser exercitada pelos runners e
consumida pela app macOS. É a fronteira para manter parsing, resolução,
filesystem, estado puro e processos separados de SwiftUI/AppKit.

Áreas principais:

- `FileSystemFoundation.swift` — tipos de documento, scanner lazy/recursivo e
  estado de tabs.
- `MarkdownAdapter.swift`, `MarkdownEditing.swift`, `MarkdownMerge.swift`,
  `MarkdownPreviewLink.swift` e `MathMLRenderer.swift` — renderização,
  edição/merge e resolução de links Markdown.
- `LatexAdapter.swift`, `LatexRootDiscovery.swift`, `LatexRenderCache.swift` e
  `LatexTabContextPersistence.swift` — descoberta de root, execução/cache,
  persistência de contexto e preview LaTeX/PDF.

Contratos públicos e comportamento devem continuar alinhados com o
[plano técnico](../../docs/technical-plan.md). Alterações neste módulo devem
ser verificadas pelos runners relevantes antes de depender da UI.

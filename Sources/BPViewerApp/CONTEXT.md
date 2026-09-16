# Contexto de `BPViewerApp`

Este target contém a superfície macOS e a coordenação de apresentação do
`bp-viewer`. `AppModel` mantém o estado observável, recebe intents e aplica
eventos dos módulos de sessão; as views SwiftUI/AppKit apresentam a árvore,
tabs, preview Markdown/JSON/PDF/DOCX, definições e snapshots.

- `AppModel.swift` e `Models.swift` — estado publicado, intents e extensões
  específicas da UI; a sessão/persistência vive em `BPViewerCore`.
- `ActiveDocumentWatcher.swift` — adaptação AppKit/Darwin para eventos de
  alterações em ficheiros ativos e dependências.
- `WorkspaceTreeSession.swift`, `DocumentRenderCoordinator.swift` e
  `DocumentEditCoordinator.swift` — seams de filesystem, renderização e
  edição usados pelo coordenador da sessão.
- `RootView.swift`, `WorkspaceView.swift`, `SidebarView.swift` e
  `DocumentOutlineView.swift` — composição da janela e navegação.
- `MarkdownPreviewView.swift`, `MarkdownWebPreview.swift`,
  `SourceEditorView.swift`, `JSONPreviewView.swift`, `PDFPreviewView.swift` e
  `DocxPreviewView.swift` — superfícies de preview, editor partilhado e
  integração com WebKit/PDFKit.
- `DesignSystem.swift`, `SettingsView.swift` e `SnapshotSupport.swift` —
  tokens/controles, preferências e snapshots flutuantes.

Lógica que não precisa de frameworks de UI deve permanecer em
[`BPViewerCore`](../BPViewerCore/CONTEXT.md). O comportamento atual está em
[`docs/current-state.md`](../../docs/current-state.md) e as fronteiras da UI
em [`docs/technical/ui-architecture.md`](../../docs/technical/ui-architecture.md).

# Contexto de `BPViewerApp`

Este target contém a superfície macOS e a coordenação de apresentação do
`bp-viewer`. `AppModel` mantém o estado observável, recebe intents e aplica
eventos dos módulos de sessão; as views SwiftUI/AppKit apresentam a árvore,
tabs, preview Markdown/JSON/PDF/DOCX/imagens, definições e snapshots.

- `AppModel.swift` e `Models.swift` — estado publicado, intents e extensões
  específicas da UI; a sessão/persistência vive em `BPViewerCore`.
- `ActiveDocumentWatcher.swift` — adaptação AppKit/Darwin para eventos de
  alterações em ficheiros ativos e dependências.
- `WorkspaceTreeSession.swift`, `DocumentRenderCoordinator.swift`,
  `DocumentEditCoordinator.swift` e `DocumentDiffCoordinator.swift` — seams de
  filesystem, renderização, edição, baselines e gravação usados pelo
  coordenador da sessão.
- `RootView.swift`, `WorkspaceView.swift`, `SidebarView.swift` e
  `DocumentOutlineView.swift` — composição da janela e navegação.
- `MarkdownPreviewView.swift`, `MarkdownWebPreview.swift`,
  `SourceEditorView.swift`, `JSONPreviewView.swift`, `CSVPreviewView.swift`, `PDFPreviewView.swift`,
  `ImagePreviewView.swift` e `DocxPreviewView.swift` — superfícies de preview, editor partilhado e
  integração com WebKit/PDFKit. `SourceEditorView` também fornece o gutter
  reutilizável de linhas e as decorações Git-like do diff.
- `FindSupport.swift` — adapters de foco para que a pesquisa comum acompanhe o
  preview ou editor source que tem o foco.
- `WindowCloseGuard.swift` — intercepta o fecho da janela para proteger sessões
  com alterações não guardadas.
- `DesignSystem.swift`, `SettingsView.swift` e `SnapshotSupport.swift` —
  tokens/controles, preferências e snapshots flutuantes.

Lógica que não precisa de frameworks de UI deve permanecer em
[`BPViewerCore`](../BPViewerCore/CONTEXT.md). O comportamento atual está em
[`docs/current-state.md`](../../docs/current-state.md) e as fronteiras da UI
em [`docs/technical/ui-architecture.md`](../../docs/technical/ui-architecture.md).

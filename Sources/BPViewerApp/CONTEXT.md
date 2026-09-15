# Contexto de `BPViewerApp`

Este target contém a superfície macOS e a coordenação de sessão do `bp-viewer`.
`AppModel` liga filesystem, tabs, watchers, persistência e renderização; as
views SwiftUI/AppKit apresentam a árvore, tabs, preview Markdown/PDF,
definições e snapshots.

- `AppModel.swift`, `AppState.swift` e `Models.swift` — estado da sessão,
  persistência e modelos específicos da UI.
- `RootView.swift`, `WorkspaceView.swift`, `SidebarView.swift` e
  `DocumentOutlineView.swift` — composição da janela e navegação.
- `MarkdownPreviewView.swift` e `PDFPreviewView.swift` — superfícies de
  preview e integração com WebKit/PDFKit.
- `DesignSystem.swift`, `SettingsView.swift` e `SnapshotSupport.swift` —
  tokens/controles, preferências e snapshots flutuantes.

Lógica que não precisa de frameworks de UI deve permanecer em
[`BPViewerCore`](../BPViewerCore/CONTEXT.md). Requisitos de comportamento e
fronteiras da UI estão em [`docs/ui-architecture.md`](../../docs/ui-architecture.md).

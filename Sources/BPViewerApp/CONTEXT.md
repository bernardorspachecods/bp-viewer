# `BPViewerApp` context

This target contains the macOS interface and presentation coordination for
`bp-viewer`. `AppModel` maintains observable state, receives intents, and applies
events from session modules; SwiftUI/AppKit views present the tree, tabs,
Markdown/JSON/PDF/DOCX/image previews, settings, and snapshots.

- `AppModel.swift` and `Models.swift` — published state, intents, and UI-specific extensions; session and persistence logic lives in `BPViewerCore`.
- `ActiveDocumentWatcher.swift` — AppKit/Darwin adapter for changes to active files and dependencies.
- `CodexReplyCaptureController.swift` — global shortcut to capture a completed Codex CLI response, save it in Documents, and open a Markdown preview.
- `WorkspaceTreeSession.swift`, `DocumentRenderCoordinator.swift`,
  `DocumentEditCoordinator.swift`, and `DocumentDiffCoordinator.swift` —
  filesystem, rendering, editing, baseline, and saving seams used by the
  session coordinator.
- `RootView.swift`, `WorkspaceView.swift`, `SidebarView.swift`, and
  `DocumentOutlineView.swift` — window composition and navigation.
- `WorkspaceWindowManager.swift` — native macOS tabs, per-workspace models,
  grouping, persisted order, and restoration.
- `MarkdownPreviewView.swift`, `MarkdownWebPreview.swift`,
  `SourceEditorView.swift`, `JSONPreviewView.swift`, `CSVPreviewView.swift`, `PDFPreviewView.swift`,
  `ImagePreviewView.swift`, and `DocxPreviewView.swift` — preview surfaces,
  shared editor, and WebKit/PDFKit integration. `SourceEditorView` also
  provides the reusable line gutter and Git-like diff decorations.
- `FindSupport.swift` — focus adapters that direct common search to the focused
  preview or source editor.
- `WindowCloseGuard.swift` — intercepts window closing to protect sessions
  with unsaved changes.
- `DesignSystem.swift`, `SettingsView.swift`, and `SnapshotSupport.swift` —
  tokens and controls, preferences, and floating snapshots.

Logic that does not need UI frameworks should remain in
[`BPViewerCore`](../BPViewerCore/CONTEXT.md). O comportamento atual está em
[`docs/current-state.md`](../../docs/current-state.md); UI boundaries are
documented in [`docs/technical/ui-architecture.md`](../../docs/technical/ui-architecture.md).

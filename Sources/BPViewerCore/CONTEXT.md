# `BPViewerCore` context

`BPViewerCore` contains UI-independent logic that can be exercised by the
runners and consumed by the macOS app. It keeps parsing, resolution, filesystem
operations, pure state, and processes separate from SwiftUI/AppKit.

Main areas:

- `FileSystemFoundation.swift` — document types, including images, and a lazy, recursive scanner.
- `SessionModels.swift` — pure models for tabs, previews, editing, reading
  positions, and persisted state.
- `DocumentDiff.swift` — comparison modes and baselines, disk/Git providers, and
  a pure diff engine reusable by Markdown, JSON, and future editors.
- `DocumentTabSession.swift` — invariants for opening, selecting, closing, and
  reordering tabs.
- `WorkspaceSessionCoordinator.swift` — workspace persistence, global state,
  LaTeX roots and permissions, and snapshots.
- `DocumentOpenCoordinator.swift` — URL resolution, supported types, and LaTeX
  context/root without UI actions.
- `JSONAdapter.swift` — validation and deterministic JSON formatting for
  previews.
- `CSVAdapter.swift` — parsing and static HTML generation for CSV previews.
- `TextSearch.swift` — normalized text matching and circular navigation
  reusable by app search.
- `MarkdownAdapter.swift`, `MarkdownEditing.swift`, `MarkdownMerge.swift`,
  `MarkdownPreviewLink.swift`, and `MathMLRenderer.swift` — rendering,
  editing/merge, and Markdown link resolution.
- `LatexAdapter.swift`, `LatexRootDiscovery.swift`, `LatexRenderCache.swift`, and
  `LatexTabContextPersistence.swift` — root discovery, execution/cache,
  context persistence, and LaTeX/PDF previews.

Public contracts and behavior should remain aligned with the
[current state](../../docs/current-state.md) and
[technical architecture](../../docs/technical/architecture.md). Changes to this
module should be checked with the relevant runners before relying on the UI.

# `Sources/` context

This directory contains the Swift targets defined in [Package.swift](../Package.swift).

- [`BPViewerCore/`](BPViewerCore/CONTEXT.md) — shared models and logic for the filesystem, sessions and tabs, persistence, document opening, Markdown, LaTeX, and editing and merge.
- [`BPViewerApp/`](BPViewerApp/CONTEXT.md) — the macOS SwiftUI/AppKit app and session state coordination.
- `BPViewerContractRunner/` — executable contracts for the Markdown adapter and LaTeX/process runner pipeline.
- `BPViewerFoundationRunner/` — executable contracts for filesystem, tree, tabs, persistence, and editing and merge foundations.
- `BPViewerTabPrototype/` and `BPViewerWindowTabPrototype/` — isolated prototypes of tab behavior; they are not the main app.

The runners and prototypes should not create a second implementation of the app:
extract or exercise core seams where possible. The current state and
architecture are documented in [`docs/current-state.md`](../docs/current-state.md),
[`docs/technical/architecture.md`](../docs/technical/architecture.md) e
[`docs/technical/ui-architecture.md`](../docs/technical/ui-architecture.md).

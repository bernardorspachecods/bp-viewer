---
description: "UI-independent Viewer logic: filesystem scanning, session and tab models, document opening, Markdown, LaTeX, JSON and CSV adapters, diffs, and editing merges."
---

# BPViewerCore

## Member inventory

<!-- BKF:GENERATED-MEMBER-INVENTORY:START -->
| What it is | Document |
| --- | --- |
<!-- BKF:GENERATED-MEMBER-INVENTORY:END -->

## Artifact references

- [FileSystemFoundation.swift](/Sources/BPViewerCore/FileSystemFoundation.swift) defines document types and recursive filesystem scanning.
- [WorkspaceSessionCoordinator.swift](/Sources/BPViewerCore/WorkspaceSessionCoordinator.swift) coordinates workspace state, persistence, permissions, and snapshots.
- [DocumentOpenCoordinator.swift](/Sources/BPViewerCore/DocumentOpenCoordinator.swift) resolves URLs, supported types, and LaTeX context.
- [MarkdownAdapter.swift](/Sources/BPViewerCore/MarkdownAdapter.swift) renders Markdown previews.
- [LatexAdapter.swift](/Sources/BPViewerCore/LatexAdapter.swift) runs LaTeX preview compilation.
- [JSONAdapter.swift](/Sources/BPViewerCore/JSONAdapter.swift) validates and formats JSON previews.
- [CSVAdapter.swift](/Sources/BPViewerCore/CSVAdapter.swift) parses CSV and generates preview HTML.
- [DocumentDiff.swift](/Sources/BPViewerCore/DocumentDiff.swift) provides diff modes, baselines, providers, and comparison logic.

Keep public contracts aligned with [current app behavior](/docs/current-state.md). Runners exercise this module before relying on UI behavior.

---
bkf_version: "0.1"
description: "Entry map for the Viewer repository: the macOS app source, current behavior and architecture documents, manual fixtures, local build scripts, and archived research."
---

# Viewer repository

## Task routes

| Task | Start here |
| --- | --- |
| Change user-visible app behavior | [Current app state](/docs/current-state.md) |
| Change how the app is built or organized | [Technical architecture](/docs/technical/architecture.md) |
| Change window composition or UI interactions | [UI architecture](/docs/technical/ui-architecture.md) |
| Check a preview manually | [Fixture validation index](/Fixtures/MarkdownValidation/validation.md) |
| Follow the repository's work-round rules | [Agent instructions](/AGENTS.md) |

## Member inventory

<!-- BKF:GENERATED-MEMBER-INVENTORY:START -->
| What it is | Document |
| --- | --- |
| Agent rules for this repository: the `scripts/restart-app.sh` step that ends a work round changing app use, and nothing beyond it. | [AGENTS.md](/AGENTS.md) |
| Manual validation fixtures for Markdown, link, and LaTeX previews: small input files, a local SVG, and a LaTeX project; these corpora contain no personal documents. | [MAP.md](/Fixtures/MAP.md) |
| Swift targets of the Viewer package: the shared core, macOS app, executable contract runners, and isolated tab prototypes; runners and prototypes exercise core seams rather than copy app logic. | [MAP.md](/Sources/MAP.md) |
| Current and historical Viewer documentation: observable app behavior and technical architecture, plus the research archive under docs/reference/, which is not a source for current behavior. | [MAP.md](/docs/MAP.md) |
<!-- BKF:GENERATED-MEMBER-INVENTORY:END -->

## Artifact references

- [Package.swift](/Package.swift) defines the Swift package products, targets, and dependencies.
- [restart-app.sh](/scripts/restart-app.sh) closes local app instances, builds the debug app, and opens it.
- [dev-run.sh](/scripts/dev-run.sh) rebuilds and restarts the app when `Sources/` changes.
- [build-app.sh](/scripts/build-app.sh) builds the local `.app` bundle and copies required resources.
- [install-app.sh](/scripts/install-app.sh) builds the release app and installs it in `/Applications` or `BP_VIEWER_INSTALL_DIR`.
- [BPViewer-Info.plist](/Resources/BPViewer-Info.plist) supplies macOS app bundle metadata.
- [BPViewer.icns](/Resources/BPViewer.icns) is the app icon.
- [BPViewer-logo.svg](/Resources/BPViewer-logo.svg) is the vector app logo.
- [MarkdownAdapterTests.swift](/Tests/BPViewerAppTests/MarkdownAdapterTests.swift) contains package tests for the Markdown adapter.

`.build/`, `.swiftpm/`, and `DerivedData/` hold generated build or package state, not durable context.

`Resources/` holds no secrets, project data, or build artifacts.

---
description: "Swift targets of the Viewer package: the shared core, macOS app, executable contract runners, and isolated tab prototypes; runners and prototypes exercise core seams rather than copy app logic."
---

# Swift package targets

## Task routes

| Task | Start here |
| --- | --- |
| Change behavior spanning Core and App | [Technical architecture](/docs/technical/architecture.md) |

## Runner guidance

`BPViewerContractRunner` covers the Markdown adapter and the LaTeX/process
pipeline. `BPViewerFoundationRunner` covers filesystem, tree, tabs, persistence,
and editing and merge foundations. They provide deterministic validation;
tests should not duplicate runner logic. The runners exist because the local
toolchain lacks the `Testing` module.

`BPViewerTabPrototype` and `BPViewerWindowTabPrototype` are isolated tab
prototypes. They exercise tab behavior independently of the app target.

## Member inventory

<!-- BKF:GENERATED-MEMBER-INVENTORY:START -->
| What it is | Document |
| --- | --- |
| The macOS SwiftUI and AppKit layer of Viewer: window composition, AppModel coordination, document surfaces and editors, and reply capture; logic that needs no UI framework belongs in Core. | [MAP.md](/Sources/BPViewerApp/MAP.md) |
| UI-independent Viewer logic: filesystem scanning, session and tab models, document opening, Markdown, LaTeX, JSON and CSV adapters, diffs, and editing merges. | [MAP.md](/Sources/BPViewerCore/MAP.md) |
<!-- BKF:GENERATED-MEMBER-INVENTORY:END -->


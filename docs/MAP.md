---
description: "Current and historical Viewer documentation: observable app behavior and technical architecture, plus the research archive under docs/reference/, which is not a source for current behavior."
---

# Viewer documentation

## Task routes

| Task | Start here |
| --- | --- |
| Find what the app does | [Current app state](/docs/current-state.md) |
| Understand why a technical option was considered | [Research synthesis](/docs/reference/research/synthesis.md) |

## Member inventory

<!-- BKF:GENERATED-MEMBER-INVENTORY:START -->
| What it is | Document |
| --- | --- |
| Observable behavior of the current Viewer app from the user's side (windows and tabs, file types, editing, LaTeX and PDF, shortcuts, persisted settings); module boundaries and view composition are in the technical documents. | [current-state.md](/docs/current-state.md) |
| Archive of the research that preceded the app: four evidence reports and their synthesis, dated 2026-09-09, recording rejected alternatives and open decisions; not a source for current behavior. | [MAP.md](/docs/reference/research/MAP.md) |
| Current technical architecture of the Swift code: module boundaries, coordinators, rendering, filesystem updates, persistence, and security controls; it does not describe user-visible behavior or window composition. | [architecture.md](/docs/technical/architecture.md) |
| Current UI architecture: window composition, the state `AppModel` publishes, and what each document surface presents; module and rendering boundaries are in `architecture.md`. | [ui-architecture.md](/docs/technical/ui-architecture.md) |
<!-- BKF:GENERATED-MEMBER-INVENTORY:END -->

Current documentation records behavior and architecture, not plans or validation checklists. `Sources/` is authoritative when an implementation detail differs. The research archive contains historical reports and synthesis, not current behavior; add only clearly broken-link fixes or historical errata to archived records.

# Repository context

This file provides orientation for the `bp-viewer` parent repository.
## Structure

- [`Package.swift`](Package.swift) — Swift manifest, products, targets, and dependencies.
- [`Sources/CONTEXT.md`](Sources/CONTEXT.md) — Swift target boundaries and their local contexts.
- [`Tests/CONTEXT.md`](Tests/CONTEXT.md) — package tests and how they relate to the executable runners.
- [`Fixtures/CONTEXT.md`](Fixtures/CONTEXT.md) — controlled corpora for manual validation.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — map of durable documentation; authoritative details are kept in that directory.
- [`scripts/CONTEXT.md`](scripts/CONTEXT.md) — local build and development launchers.
- [`Resources/CONTEXT.md`](Resources/CONTEXT.md) — macOS bundle resources.
- [`PLAN.md`](PLAN.md) — approved plan for a LaTeX editor equivalent to the Markdown editor.
- [`AGENTS.md`](AGENTS.md) — app-specific instructions for closing a work round.

`.build/`, `.swiftpm/`, and `DerivedData/` contain generated artifacts or state. They are not development inputs and should not contain durable context.

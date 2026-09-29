# `Tests/` context

This directory contains Swift Package tests. The current
`BPViewerAppTests` target checks the core through `MarkdownAdapterTests.swift`.

The executable runners in [`Sources/`](../Sources/CONTEXT.md) provide
deterministic validation when the local toolchain does not provide the
`Testing` module. Do not duplicate runner logic in these tests without a clear
integration reason.

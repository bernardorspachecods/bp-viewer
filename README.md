# Viewer

Local viewer for academic projects written in Markdown, LaTeX, JSON, CSV, Word,
PDF, and image formats on macOS.

The `Viewer` opens a local folder, watches source files for changes, and displays
the rendered or formatted result. Markdown files can be edited in source mode
or in a split view with a live preview. PDF files can be read directly in the app.

## Requirements

- macOS compatible with the platform specified in `Package.swift`;
- a Swift toolchain compatible with `Package.swift`;
- a local LaTeX installation to open `.tex` projects.

## Run locally

```bash
swift run BPViewer
```

For development, use the launcher that watches `Sources/` and rebuilds the app
when the code changes:

```bash
./scripts/dev-run.sh
```

To build a local `.app` bundle:

```bash
./scripts/build-app.sh
```

To close older instances, rebuild, and open a new instance:

```bash
./scripts/restart-app.sh
```

The bundle does not include TeX Live; the app uses the Mac's local LaTeX installation.

## Quick validation

The runners validate the core logic without requiring window interaction:

```bash
swift run BPViewerContractRunner
swift run BPViewerFoundationRunner
```

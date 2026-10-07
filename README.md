<p align="center">
  <img src="Resources/BPViewer-logo.svg" alt="Viewer open-pages logo" width="112">
</p>

<h1 align="center">Viewer</h1>

<p align="center">
  A distraction-free place to read and edit your project files.
</p>

<br>

## Stay with the work

Viewer keeps project files, previews, and editors together in a quiet native
workspace. Open multiple workspaces, switch between them, and keep each
document close at hand.

- Organize workspaces by local project folder and open files in document tabs.
- Move between workspaces and files while keeping their tabs and view state.
- Read PDFs and preview Markdown, LaTeX, JSON, CSV, Word documents, and images.
- Edit Markdown and LaTeX in source or split view with a live preview.
- Follow supported links between files and search within the active document.

## Run Viewer from source

Viewer is shared as source code. Clone the repository and start it with Swift
Package Manager:

```sh
git clone https://github.com/bernardorspachecods/bp-viewer.git
cd bp-viewer
swift run BPViewer
```

For development, `./scripts/dev-run.sh` watches `Sources/` and rebuilds when
code changes. `./scripts/build-app.sh` creates a local `.app` bundle in `.build/`.
No prebuilt app download is included.

## What you need

- macOS 26 or later;
- Swift 6.2 or a compatible toolchain;
- a local LaTeX installation to compile `.tex` projects.

The LaTeX toolchain is installed separately and is not included with Viewer.

## Core checks

The contract runners exercise core behavior without opening a window:

```sh
swift run BPViewerContractRunner
swift run BPViewerFoundationRunner
```

To include your own LaTeX project in the contract run, set
`BP_VIEWER_LATEX_CORPUS` to its folder. The project must contain `main.tex`:

```sh
BP_VIEWER_LATEX_CORPUS=/path/to/project swift run BPViewerContractRunner
```

## License

MIT. See [LICENSE](LICENSE).

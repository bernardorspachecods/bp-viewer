---
bkf: document
description: "Current technical architecture of the Swift code: module boundaries, coordinators, rendering, filesystem updates, persistence, and security controls; it does not describe user-visible behavior or window composition."
tags: [architecture, swift]
---

# Current technical architecture

## Module organization

```text
BPViewerApp
├── AppModel                  UI intents and session coordination
├── ActiveDocumentWatcher     active file event adapter
├── WorkspaceTreeSession      lazy tree, filters, and workspace watchers
├── DocumentRenderCoordinator rendering and cancellation by tab
├── DocumentEditCoordinator  document sessions, conflicts, and saving
├── DocumentDiffCoordinator  disk/Git baselines and diff composition
├── RootView / WorkspaceView  window composition
├── WorkspaceWindowManager    native tabs and per-workspace models
├── SidebarView               workspace tree and navigation
├── MarkdownPreviewView       preview composition and Markdown editing
├── MarkdownWebPreview        WebKit, JavaScript, and Markdown navigation bridge
├── SourceEditorView          AppKit editor, gutter, and decorations shared
│                             by Markdown, JSON, and diff
├── JSONPreviewView           numbered raw JSON preview
├── CSVPreviewView            tabular CSV preview
├── LatexPreviewView          LaTeX editing and source/PDF split view
├── LatexSyncTeXLookup        PDF double-click → source
├── PDFPreviewView            PDF preview and shared PDF surface
├── ImagePreviewView          native raster image preview
├── DocxPreviewView           Word preview through HTML/WebKit
├── SettingsView              app preferences
└── SnapshotSupport           snapshot selection and windows

BPViewerCore
├── FileSystemFoundation      nodes and scanner
├── SessionModels             pure session and persistence models
├── DocumentTabSession        tab invariants and transitions
├── WorkspaceSessionCoordinator workspace persistence and session
├── DocumentOpenCoordinator   document resolution and LaTeX context
├── MarkdownAdapter            Markdown → HTML
├── MarkdownEditing / Merge   Markdown editing and merge
├── DocumentDiff              pure diff between two text sources
├── CSVAdapter                 parsing and static HTML for CSV preview
├── MarkdownPreviewLink       link resolution
├── MathMLRenderer            TeX mathematics → MathML
├── LatexRootDiscovery        root discovery
├── LatexAdapter               LaTeX compilation, overrides, and diagnostics
├── LatexSyntaxHighlighter     LaTeX source tokens and palette
├── LatexRenderCache           result cache
└── LatexTabContextPersistence LaTeX chapter context
```

`BPViewerApp` contains macOS integration and observable state. `BPViewerCore`
contains UI-independent logic used by the app and executable runners. The
`BPViewerContractRunner` and `BPViewerFoundationRunner` targets exercise this
shared logic.

## Coordination

`AppModel`, isolated on the `MainActor`, is the effective coordinator for a
workspace's presentation. `WorkspaceWindowManager` keeps one model instance per
native tab and shares the persistence coordinator among them. The model
maintains observable tab state and routes intents to session modules and
specialized coordinators. `DocumentTabSession` maintains tab invariants;
`WorkspaceSessionCoordinator` handles persistence and per-workspace state;
`DocumentOpenCoordinator` resolves URLs and LaTeX context; `ActiveDocumentWatcher`
adapts Darwin events for the UI. `WorkspaceTreeSession` encapsulates lazy
scanning, filtering, expansion, and tree watchers; `DocumentRenderCoordinator`
encapsulates generations, cancellation, and rendering; `DocumentEditCoordinator`
encapsulates undo/redo, validation, explicit saving, and conflicts;
`DocumentDiffCoordinator` selects and retrieves baselines without exposing Git
to the UI. The Core's `DocumentDiffEngine` compares in-memory sources and
returns a result independent of Markdown or JSON. These modules return values
and events without directly mutating `AppModel`.

The main flow is:

```text
UI action
  → AppModel
    → workspace session / render coordinator / edit coordinator
        → scanner / watcher / adapter / process runner
        → DocumentTab and SwiftUI state
        → Markdown, JSON, CSV, PDF, or Quick Look preview
```

## Filesystem and updates

- `FileSystemScanner` creates `FileNode` values with absolute and relative paths,
  a type, and loaded children.
- The tree starts at the top level and loads children when a folder is expanded.
  Searching or disabling the compatibility filter may require a full index.
- Directory watchers update the tree. Watchers for active files and dependencies
  invalidate the preview. During editing, an external change is reconciled as a
  conflict; it does not trigger Markdown autosave.
- Each render uses a generation. Cancelled or obsolete results do not replace
  the tab's latest state.

## Rendering

`SwiftMarkdownAdapter` uses `swift-markdown` to produce custom HTML. It escapes
text and attributes, controls URL schemes, embeds local images, collects
dependencies, and creates an outline and editable blocks.

Local images are embedded as `data:` URLs because WebKit did not reliably load
relative local resources from the in-memory HTML document used by
`WKWebView.loadHTMLString`; their filesystem paths remain dependencies for the
watcher.

`LocalLatexAdapter` resolves the root, prepares a temporary workspace (or an
overlay when there is a contextual draft), runs the compiler through
`ProcessRunner`, collects dependencies, validates the generated PDF, and returns
SyncTeX data when available. The cache is keyed by root, dependencies,
compiler, and configuration; draft previews are not cached.

Supported images are read as bytes and validated through ImageIO before being
passed to the native surface. The preview does not alter the original file.

## Persistence and artifacts

- `AppState` is a `Codable` model with a schema version in `SessionModels.swift`.
- `AppStateStore` stores JSON state in `UserDefaults`; access is encapsulated by
  `WorkspaceSessionCoordinator`.
- Global state stores the theme, sidebar, default zoom levels, and `shell escape`.
- The ordered list of open workspaces and the active workspace are stored in the
  app state to restore native tabs at launch.
- Per-document state stores zoom, outline, and reading position.
- Per-workspace state stores tabs, expansion, scroll, filter, root selection,
  external permissions, and snapshot records.
- Transient diff state exists only in the in-memory session; HTML, PDFs, logs,
  and raw content are not persisted as session state.
- Snapshot PNG files are stored outside the repository, in Application Support.

## Security boundaries

- Markdown HTML uses a local Content Security Policy and does not enable content
  scripts.
- The app does not write build artifacts into the user's source folder.
- LaTeX dependency paths are resolved and filtered before compilation.
- Dependencies outside the root require explicit approval and are watched after
  authorization.
- `shell escape` is disabled by default and is an explicit app preference.

## Known limits

- Although `ProcessRunner` checks cancellation and sends termination signals,
  long compilations may still require reliable process cancellation.
- Draft overlays must handle complex relative paths, `\\input`, `\\include`,
  `\\graphicspath`, and bibliography correctly.
- Some engines or distributions may not provide SyncTeX or may produce
  incomplete maps.
- Large projects and external dependencies may make live preview expensive.
- The following areas were recorded as untested at the first foundation-test
  round and have not been re-verified: SwiftUI rendering and AppKit event
  delivery; `AppModel` asynchronous tasks, `UserDefaults` isolation, watcher
  callbacks, and render-generation cancellation; actual `Task` scheduling and
  generation guards in `AppModel`; permission-denied directories, symlink
  policy, concurrent renames, and large filesystem performance; and keyboard
  shortcuts, tab clicks, `WKWebView`, lazy expansion, and external file refresh.
- The standard `swift test` target was also recorded as unavailable in that
  environment because the toolchain lacked the Swift `Testing` module; it has
  not been re-verified.
- Markdown math coverage is limited to the common renderer surface currently
  implemented: `frac`, `sqrt`, subscript, superscript, Greek symbols, and basic
  operators. It does not validate arbitrary LaTeX macros, environments,
  alignment, labels/references, or custom commands.

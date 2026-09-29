# Current UI architecture

## Window composition

```text
RootView
└── WorkspaceView
    ├── Topbar
    ├── SidebarView
    │   ├── folder header
    │   ├── search and filter
    │   └── file tree
    ├── tab bar
    └── document surface
        ├── MarkdownPreviewView
        ├── JSONPreviewView
        ├── CSVPreviewView
        ├── LatexPreviewView
        ├── PDFPreviewView
        ├── ImagePreviewView
        └── DocxPreviewView
```

`DocumentOutlineView`, `DocumentDiffView`, `SettingsView`, and the error,
root selection, permission, and workspace-switch overlays are presented by the
app layer. Snapshots use a separate AppKit window.

## UI state

`WorkspaceWindowManager` manages native macOS tabs and keeps an `AppModel` for
each workspace window/tab. `AppModel` is the main `ObservableObject` for each
workspace and publishes its root, tree, tabs, active tab, search, search target,
filter, expansion, sidebar, zoom, theme, search state, LaTeX selection requests,
and snapshot capture. Tab sessions, persistence, and document resolution live
in Core; `WorkspaceTreeSession` maintains the tree. Render, edit, and diff
baseline requests are handled by `DocumentRenderCoordinator`,
`DocumentEditCoordinator`, and `DocumentDiffCoordinator`, respectively; they
return events or values that `AppModel` applies.

`CodexReplyCaptureController` registers `⇧⌘E` as a global shortcut, sends
`Ctrl+O` to the Codex CLI in the active terminal window, confirms a clipboard
change, and opens a new in-memory Markdown tab with the response. Sending
keystrokes requires macOS Accessibility permission, as does Terminal
automation in Prompt Wiz. macOS presents the permission prompt at most once per
session if permission is not already active. `scripts/build-app.sh` uses the
existing Apple Development identity in the Keychain to preserve the signing
identity across rebuilds; it does not create certificates.

The main models are:

- `DocumentTab` — file identity, type, context, preview state, current artifact,
  outline, zoom, reading position, dependencies, and error.
- `SourceEditSession` — source/split mode, base and current source, saving,
  undo/redo history, and external conflicts.
- `DocumentDiff` — reusable, format-independent result with lines/hunks, line
  numbers, and selected reference.
- `AppState`, `WorkspaceState`, and `DocumentState` — state persisted in Core;
  `WorkspaceSessionCoordinator` manages reads and writes.
- `PreviewStatus` — `idle`, `updating`, `ready`, `stale`, `failed`,
  `unavailable`, `cancelled`, and `timeout`.

## Surfaces

### Sidebar

`SidebarView` displays the open root, search, compatibility filter, indexing
state, and lazy tree. Selecting a file asks `AppModel` to open or focus the
corresponding tab.

Expanded branches are flattened into visible rows before they are passed to
`LazyVStack`, so scrolling does not need to build a recursive view containing
all descendants.

The header collapses all folders; on each first-level folder, the same command
appears on hover and clears only that folder's branch.

The context menu uses `WorkspaceFileOperations` to rename folders/files,
duplicate items, and move items to the Trash while keeping open tabs synced with
their new paths. Files are draggable by path, and folders accept
`dropDestination`, which moves items only within the workspace root. Two drop
zones at the sides of the list also represent the open root, allowing a file to
be moved back to the root without relying on empty space at the end of the tree.

### Tabs

The tab bar shows the file name and context, preview state, and close actions.
The `+` button creates a transient in-memory Markdown tab; the file location is
chosen only in the save panel. `DocumentTabSession` in Core maintains ordering,
uniqueness, and the active tab. Transient tabs are not included in workspace
persistence.

### Markdown

`MarkdownPreviewView` composes the HTML, search, outline, zoom, rendering state,
and errors. The shared search bar lives on the tab surface and follows focus
between the source editor and preview in split view. `MarkdownWebPreview`
contains the `WKWebView`, JavaScript, navigation, and reading position.
`SourceEditorView` contains the AppKit editor shared by Markdown and JSON.
Double-clicking opens the Markdown source editor, whose syntax highlighting uses
a palette for light and dark themes. The toolbar switches between the full
editor and split view, which keeps the source on the left and live preview on
the right. The outline is resizable per file and restores that document's saved
width.

The toolbar opens `DocumentDiffView`, which keeps the read-only reference on the
left and the actual editor on the right. It can compare against disk or `HEAD`;
when closed, it restores the previous mode. Both editors share vertical
scrolling and use the same per-line height map to keep corresponding lines
aligned as either column scrolls.

### PDF

`PDFPreviewView` displays local PDFs and LaTeX artifacts in `PDFView`, and
controls zoom, search, outline, reading position, printing, and link navigation.
The shared search routes operations to PDFKit.

### Images

`ImagePreviewView` displays PNG, JPG/JPEG, WebP, and HEIC/HEIF in a read-only
canvas with a card, border, and shadow; automatic fit-to-window; scrolling for
enlarged images; shared tab zoom; refresh; and snapshot capture. Changes to the
active file trigger a new read through `DocumentRenderCoordinator`.

### LaTeX

`LatexPreviewView` composes the editing toolbar, `NSTextView` editor, diff, and
`PDFPreviewView` in split view. Double-clicking the PDF sends the page and
coordinates to `LatexSyncTeXLookup`, which resolves the file and line and moves
the cursor. Source editing remains available when SyncTeX is missing. When
SyncTeX returns a line from the generated `.bbl`, `AppModel` uses the saved `.bbl`
contents to find the entry key and open the `.bib` file.

`SourceEditorView` applies the `LatexSyntaxColorPalette`. The PDF routes local
links to the `AppModel` router and external links to the browser.

### JSON

`JSONPreviewView` displays validated JSON in a selectable, monospaced,
read-only raw surface. It preserves source lines exactly, including empty ones,
and provides line numbers, zoom, and snapshot capture. Double-clicking switches
to a monospaced raw editor with undo/redo, explicit saving for valid JSON only,
validation before saving, and external conflict resolution; there is no split
view. Preview and editor use the same search bar, with focus determining the
search target. Diff uses the same `DocumentDiffView` as Markdown; the shared
AppKit editor provides the line gutter and Git-like decorations on the right.
Invalid JSON on exit opens a confirmation to continue editing or discard.

### CSV

`CSVPreviewView` displays data in a selectable HTML table with a header, row
numbers, horizontal scrolling, zoom, search, and snapshot capture. Double-click
edits existing cells; `Enter` confirms, `Esc` cancels or confirms the cell in
the draft, and `Save` or `⌘S` saves the file. `Undo`/`Redo` and `⌘Z`/`⇧⌘Z` work
on the draft without saving. Rows and columns cannot be created or removed.

### Word

`DocxPreviewView` converts rich `.docx` content to local HTML and displays it in
a `WKWebView` with a canvas, white page, and magnification linked to the app's
zoom. Shared search routes queries to WebKit.

### Visual system and preferences

`DesignSystem.swift` contains tokens, toolbar buttons, badges, empty states, and
reusable controls. `SettingsView` changes the theme, default zoom levels, and
`shell escape` mode through `AppModel`.

## Window-level interactions

`RootView` routes commands to open a folder, refresh the preview, toggle the
theme/sidebar, show search, control zoom, select tabs, and capture snapshots.
`WorkspaceWindowManager` creates and groups windows as native tabs, restores
workspace order, and routes global commands to the active window. `AppModel` also
handles opening from Finder, drag and drop, document shortcuts, and confirmation
when closing a native tab with changes.

Views do not run scanners, compilers, or persistence directly; they send actions
to `AppModel` and render the state it publishes.

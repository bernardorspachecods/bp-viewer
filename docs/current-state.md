# Current app state

`bp-viewer` is a native macOS app for opening a local folder, browsing Markdown,
LaTeX, JSON, CSV, and PDF files, and displaying rendered or formatted results.

## Window and navigation

- The window uses native macOS tabs for workspaces. Each native tab represents
  a folder and has its own top bar, sidebar, tree, and document tab bar.
- The sidebar opens a folder as the root, displays a tree of folders and files,
  and ignores hidden files.
- Right-clicking a folder lets you copy its path, rename it, or move it to the
  Trash. The file menu also lets you rename, duplicate, or move a file to the
  Trash. Files and folders can be moved by dragging them to a folder in the tree;
  the app asks for confirmation before moving them. Open tabs follow renames and
  moves; items with unsaved changes cannot be moved to the Trash.
- The tree loads the first level and expands folders on demand. Dragging files
  to the sides of the list moves them to the open root, even when there is no
  empty space below the items. Name or path search looks only for folders
  directly inside the root, scrolls automatically to the first match, and
  highlights it without filtering the tree or searching descendants.
- The header can collapse all folders and clear expansion records; the same
  action is available on hover for each first-level folder.
- By default, the compatibility filter shows Markdown, LaTeX, JSON, CSV, Word,
  PDF, and images. It can be disabled to show all files.
- The tree preserves expansion, scroll position, and filter state per workspace.
- The folder button, native `+`, and `⇧⌘T` open a new native workspace tab via
  the folder picker. Already open workspaces are focused instead of duplicated;
  switching workspaces does not close tabs or ask for confirmation.
- Files with extensions `.md`, `.markdown`, `.tex`, `.latex`, `.bib`, `.json`,
  `.csv`, `.docx`, `.pdf`, `.png`, `.jpg`, `.jpeg`, `.webp`, `.heic`, and `.heif`
  can be opened in tabs. Word documents are converted locally to rich HTML and
  displayed on a page with a background and responsive zoom. Images are shown
  in a read-only preview with a frame/canvas, fit-to-window, zoom, manual
  refresh, automatic updates when the file changes, and snapshot capture.
- The Word preview participates in search for the active tab. Other files open
  in the macOS default app.

## Markdown

- `SwiftMarkdownAdapter` converts content to safe HTML for display in a
  `WKWebView`.
- The preview shows headings with an outline, lists, tables, code blocks, links,
  images, and common TeX mathematics converted to MathML.
- Existing local images are embedded in the HTML and remain monitored as
  dependencies.
- Markdown links to Markdown and LaTeX open or focus tabs; links to other files
  use macOS; external links open in the browser.
- The preview keeps the last result if an update fails and displays the
  diagnostic.
- Double-clicking the preview opens the Markdown source editor. The editor has
  syntax highlighting adapted to light and dark themes, explicit saving,
  undo/redo, `⌘B`, `⌘I`, and `⌘K` shortcuts, external change detection, and
  conflict resolution. The editor enables macOS spell correction. For inline
  word completion, it uses the on-device Apple Foundation model when available
  for the current language. Otherwise, for languages without native macOS
  inline predictions, it uses completions from the local dictionary. The
  suggestion appears in gray; `Space` accepts the word followed by a space,
  while `Tab` accepts only the word. For languages with native predictions,
  macOS continues to provide them. In list lines with `-`, `*`, or `+` markers,
  Return continues the list; in ordered lists with `.` or `)`, it increments the
  number. Return on an empty line removes the marker and ends the list.
- The editor can fill the whole surface or use split view, with Markdown source
  on the left and a live preview on the right.
- Markdown changes remain in the draft while the editor is open. `Save` and
  `Esc` explicitly save and exit editing, while `Discard Changes` restores the
  saved version and keeps the editor open. External changes during editing open
  the conflict panel without saving automatically.
- In the shared action bar, a saved document does not show the `Saved` state or
  `Discard Changes`; the `Save` button stays visible but disabled.
- During editing, the toolbar provides a diff with two modes: `Version saved on
  disk`, which compares the current draft with the file contents, and `Git diff`,
  which compares the draft with `HEAD`. The left column is read-only and the
  right column is the actual editor; edits on the right continue to update the
  live Markdown preview. Both columns share vertical scrolling to keep lines
  aligned. The diff preserves draft `undo/redo` and does not keep a separate list
  of historical versions.
- In `Git diff` mode, `Discard Git Changes` appears beside `Current Draft` when
  the file is tracked and has a `HEAD` version. A single confirmation restores
  the whole file to `HEAD`, discarding staged, unstaged, and current draft
  changes; the app then keeps the editor open and returns to source mode.
- `⌘F` opens a shared search bar for previews and source editors. Search is
  limited to the active tab, ignores case and accents, supports next/previous
  with Enter/Shift+Enter, and closes with Esc. In split view, it searches the
  panel with focus.

## LaTeX and PDF

- Existing PDF files can be opened directly in tabs and displayed with the same
  PDFKit surface used by the LaTeX preview.
- When a LaTeX file is opened, the app looks for roots inside the workspace. A
  single root is selected automatically; zero or multiple roots open a picker.
- Root selection is saved per workspace. An opened chapter remains the context
  for the root tab instead of creating a second preview tab.
- `latexmk` is used when available; `pdflatex`, `xelatex`, and `lualatex` are
  used according to the installation and document contents.
- Compilation runs in a temporary workspace and produces PDF bytes for the
  `PDFView` surface.
- Dependencies outside the workspace require authorization. `shell escape`
  mode is configurable and disabled by default.
- The preview displays compilation errors, lets you expand and copy the
  diagnostic, and preserves the previous PDF when the current compilation fails.
- The PDF supports an outline, search, copy, printing, app-handled links, zoom,
  and restoration of reading position.
- Double-clicking a LaTeX PDF opens the contextual source (or the root) with
  line numbers and attempts to position the cursor through SyncTeX; without a
  map, it opens the editor without moving the cursor.
- `.bib` files opened from the tree use the project's LaTeX root and open as
  contextual source in the same editor; citations can open the corresponding
  entry directly in the references file. Double-clicking a printed reference
  in the PDF uses the generated `.bbl` SyncTeX map to open that entry in the
  `.bib`; double-clicking the bibliography title opens the start of the `.bib`.
- The LaTeX editor highlights commands, comments, environments, arguments, and
  mathematics, with a monospaced fallback. The toolbar offers source/split
  view, Undo/Redo, Save, Discard Changes, Disk Diff, and Git Diff. The source
  editor enables spell correction, system inline predictions, and native macOS
  completions, while keeping quote, dash, and text substitutions disabled.
- In split view, the edited source stays on the left and the PDF on the right.
  Changes are compiled after a two-second debounce in a temporary workspace,
  preserving the last valid PDF during errors.
- Contextual source can be saved independently of the compilation result.
  External changes to the source open a conflict; changes to other dependencies
  only trigger recompilation and preserve the draft. Diffs and Git discard apply
  to the contextual file.

## JSON

- `.json` files are validated and displayed in a monospaced, read-only raw
  surface that preserves the file's exact lines, including empty lines. The
  surface shows line numbers.
- Double-clicking opens a monospaced raw editor with undo/redo, explicit saving
  for valid JSON only, and external conflict resolution. It has no split view.
  The editor enables spell correction, system inline predictions, and native
  macOS completions, while keeping quote, dash, and text substitutions disabled.
- The JSON editor provides `Version saved on disk` and `Git diff` modes, with a
  read-only reference version on the left and the editable raw editor on the
  right, both with line numbers. Added lines on the right have a `+` marker and
  green highlight, as in a Git diff. Files outside Git or without a `HEAD`
  version show an explanatory state while keeping disk comparison available.
- In `Git diff` mode, `Discard Git Changes` behaves like the destructive action
  in the Markdown editor: one confirmation restores staged, unstaged, and draft
  changes to `HEAD`, keeps the editor open, and exits diff mode.
- The JSON preview supports text selection/copy, zoom, snapshots, and automatic
  updates when the file changes.
- The JSON preview and raw editor use the app's shared search bar.
- Invalid JSON drafts can remain open in the editor, but are not saved until
  they become valid again; the editor shows the “Unsaved” state.
- When exiting the JSON editor with invalid content, the app lets you continue
  editing or discard changes; the save option appears only for valid JSON.
- The JSON editor bar provides `Discard Changes` to restore the saved version
  without exiting edit mode.
- When closing a document tab with unsaved changes, the app lets you continue
  editing, save, or discard changes. When closing a native workspace tab, a
  single confirmation lets you save all, discard all, or cancel.
- Invalid JSON keeps the last valid preview, if one exists, and shows the
  validation diagnostic.

## CSV

- `.csv` files are read and displayed in a read-only table that supports quoted
  fields, escaped quotes, multiline rows, and automatic detection of comma,
  semicolon, or tab delimiters.
- The CSV preview displays a spreadsheet-like grid with column letters, row
  numbers, an active cell, and keyboard navigation. Double-clicking edits a
  cell; `Enter` or `Esc` confirms the cell in the draft without saving the file,
  leaving `Save` and `Discard Changes` available.
- The CSV editing bar provides `Undo` and `Redo`; `⌘Z` undoes and `⇧⌘Z` redoes
  draft changes without saving the file automatically.
- The CSV preview participates in search, zoom, snapshots, and automatic updates
  when the file changes.
- `⌘S` saves changes while preserving the detected delimiter and quoting only
  when needed. External changes while a draft exists show a conflict with
  options to keep the draft or use the external version.

## Tabs, preferences, and snapshots

- Each file has at most one tab. Tabs can be selected, reordered, closed
  individually, closed to the right, or closed except for the selected tab.
- `⌘W` closes the active document tab in the key window; it does not close the
  workspace.
- The `+` button at the end of the bar creates a new in-memory Markdown tab
  without a default path; the first `Save` opens a panel to choose the `.md` file.
- The global `⇧⌘E` shortcut, when a Terminal, iTerm2, Ghostty, WezTerm,
  Alacritty, Kitty, or Warp window is active, sends `Ctrl+O` to the Codex CLI.
  After confirming a new response in the clipboard, Viewer saves it as Markdown
  in `~/Downloads/Codex Responses` and opens the saved document in a tab. The
  folder is created if needed. Files are named `Codex Reply.md` and receive a
  numeric suffix when that name already exists.
  The shortcut opens the saved file in the last focused Viewer window when that
  window is open. If it is minimized, Viewer opens a standalone capture window
  for the file with its sidebar hidden and leaves the workspace minimized.
  Closing the last window leaves Viewer running so its global shortcut stays
  available; quitting Viewer ends the shortcut until the app is launched again.
  Sending keystrokes requires macOS Accessibility permission; after granting it,
  you may need to quit and reopen Viewer for the change to take effect.
- Tabs, active tab, LaTeX context, theme, sidebar width and visibility, per-file
  outline width and visibility, default zoom levels, filter, expansion, and
  reading positions are persisted.
- The app restores all existing native workspace tabs in their previous order,
  focuses the last active one, and removes references to folders or tabs that
  no longer exist.
- You can select an area of the preview, including content loaded through
  autoscroll, and open the selection in a floating window.
- Snapshots are saved as PNG files in Application Support and remain available
  across restarts until closed by the user.

## Main code entry points

- [`Sources/BPViewerApp/CONTEXT.md`](../Sources/BPViewerApp/CONTEXT.md) — window
  composition and session coordination.
- [`Sources/BPViewerCore/CONTEXT.md`](../Sources/BPViewerCore/CONTEXT.md) —
  shared filesystem, Markdown, LaTeX, tabs, and editing logic.
- [`docs/technical/architecture.md`](technical/architecture.md) — implemented
  technical boundaries.
- [`docs/technical/ui-architecture.md`](technical/ui-architecture.md) — current
  UI composition and state.

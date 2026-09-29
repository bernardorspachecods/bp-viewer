# Plan: LaTeX editor equivalent to the Markdown editor

## Status

Approved for implementation. The user has already given the go-ahead.

## Objective

Give the LaTeX editor the same source editing workflow as Markdown: double-click
the preview, source/split view, live preview, Undo/Redo, Save, Discard Changes,
external conflicts, Disk Diff, Git Diff, search, and navigation between preview
and source.

The LaTeX preview will continue to use PDFKit. In this context, “live preview”
means recompiling asynchronously after approximately two seconds without
changes, while preserving the last valid PDF if compilation is running or fails.

## Product decisions

- Editing starts with a double-click on the LaTeX PDF.
- If the tab has a contextual file, that file is the source being edited;
  otherwise, edit the main root file.
- The preview always compiles the main root, incorporating the contextual
  source draft.
- The initial live preview debounce is approximately two seconds.
- Obsolete compilations are cancelled or ignored; they must never replace a PDF
  produced from a newer draft.
- SyncTeX is generated when possible, and a double-click places the cursor at
  the corresponding line and column. If no map is available, the editor uses a
  safe position fallback.
- Internal anchors and references remain navigable in the PDF. External links
  open in the browser, and links to supported files go through the app router.
- The source can be saved even if compilation fails. The last valid PDF remains
  visible and the compilation diagnostic is displayed.
- An external change to the edited source opens the conflict panel. An external
  change to another dependency only triggers recompilation and preserves the
  draft.
- Disk Diff and Git Diff always compare the file actually being edited, which
  is not necessarily the root represented by the tab.
- `Discard Git Changes` restores only the edited file to `HEAD` in a single
  confirmation and recompiles the project from its root.
- LaTeX source uses syntax highlighting for commands, comments, environments,
  arguments, and mathematics, with a monospaced fallback.

## Technical design

### Shared source session

The session currently called `MarkdownEditSession` is already used by Markdown
and JSON. It should be extended into a common source session to avoid a second,
parallel LaTeX implementation. The session owns the base and current source,
Undo/Redo, save state, conflicts, and source/split/diff mode.

Markdown keeps its structural merge, which understands Markdown blocks; LaTeX
uses a text merge suited to TeX source. The UI and diff should not know about
these differences.

### Compilation with a draft

`LocalLatexAdapter` should accept an in-memory override for the edited file. The
adapter prepares a temporary overlay with stable relative paths, compiles the
root in that overlay, leaves the original project untouched, and returns:

- a valid PDF;
- dependencies observed by the recorder;
- compilation diagnostics;
- enough SyncTeX data to map a PDF position to source.

The existing pipeline for roots, engines, bibliography, external permissions,
shell escape, timeouts, and caching remains in place. Draft previews must not
pollute the persistent cache of saved previews.

### Tab state and coordination

`DocumentTab` will also represent the LaTeX session and contextual source URL.
`presentationMode` and `DocumentDiffCoordinator` must stop assuming that the
source is always `tab.url`.

`AppModel` coordinates the lifecycle: entry via double-click, source/split,
changes, debounce, saving, discarding, conflicts, diffs, and rerendering. The
watcher observes the edited source, the root, local dependencies, and authorized
external dependencies.

### UI

The LaTeX editor reuses the toolbar, action bar, diff view, gutter, search, and
AppKit editor already used by Markdown. The split view shows the source on the
left and the PDF on the right. The PDF provides callbacks for double-clicks
with position and link routing.

## Implementation slices

Each slice starts with a focused test, proceeds through a minimal implementation,
and ends with the relevant tests and manual validation.

1. Generalize the source session and presentation modes for LaTeX.
2. Add the editable contextual URL and Disk/Git baselines based on that URL.
3. Add temporary overrides to the LaTeX adapter, preserving includes, images,
   and bibliography without changing the user's folder.
4. Generate and interpret SyncTeX, including a fallback when the tool or map is
   unavailable.
5. Add LaTeX syntax highlighting to `SourceEditorView`.
6. Connect the PDF to double-click entry, the source editor, and split view.
7. Implement live preview with debounce, cancellation/generations, and the last
   valid PDF.
8. Implement Save, Esc, Discard Changes, external conflicts, and dependency
   changes.
9. Connect Disk Diff, Git Diff, and Discard Git Changes to the contextual
   source.
10. Connect internal, external, and file links to the defined behavior.
11. Update the current state, technical architecture, UI architecture, and
    fixtures after the behavior is implemented and validated.

## Tests

Pure contracts live in `BPViewerCore` and are exercised by the existing tests
and runners. The test-first sequence covers:

- source/split/diff transitions and Undo/Redo history;
- a `main.tex` root with an included chapter edited through an override;
- ensuring live preview does not write to the original project;
- preserving the previous PDF after failed compilation;
- dependencies and bibliography with a contextual source;
- SyncTeX parsing/mapping and fallback;
- diff baselines for the contextual file;
- conflicts in the edited source and recompilation after an external dependency
  changes;
- PDF link routing;
- observable `AppModel` and toolbar transitions.

Manual fixtures should include a multi-file document, an image, cross-references,
a bibliography, a compilation error, and successive external changes.

## Completion criteria

- Double-clicking the PDF enters the correct source and uses SyncTeX when
  available.
- Source and PDF work in split view.
- Changes update the PDF after the debounce, without replacing newer results
  with obsolete ones.
- Undo/Redo, Save, Esc, and Discard Changes have the same meaning as in Markdown.
- Disk Diff and Git Diff show the correct contextual file.
- External conflicts protect the draft and let the user choose a version.
- Compilation errors preserve the last valid PDF and still allow the source to
  be saved.
- Internal, external, and local links follow the defined rules.
- Tests, runners, build, `git diff --check`, and manual validation pass.
- After each round that changes the app, `./scripts/restart-app.sh` completes
  the build and opens the latest version.

## Out of scope

- A full multi-file editor with several sources editable at once.
- Automatic semantic formatting of LaTeX.
- Auto-save or collaboration.
- Compilation on every keystroke without debounce.
- Guaranteed SyncTeX support when the local LaTeX installation does not produce
  it.

## Risks

- Long compilations may require actual process cancellation in addition to the
  generation protection already used by the coordinator.
- The temporary overlay must handle complex relative paths, `\\input`,
  `\\include`, `\\graphicspath`, and bibliography correctly.
- Some engines or distributions may not provide SyncTeX or may produce
  incomplete maps.
- Large projects and external dependencies may make live preview expensive.

## References

- [`docs/current-state.md`](docs/current-state.md)
- [`docs/technical/architecture.md`](docs/technical/architecture.md)
- [`docs/technical/ui-architecture.md`](docs/technical/ui-architecture.md)
- [`Sources/BPViewerCore/CONTEXT.md`](Sources/BPViewerCore/CONTEXT.md)
- [`Sources/BPViewerApp/CONTEXT.md`](Sources/BPViewerApp/CONTEXT.md)

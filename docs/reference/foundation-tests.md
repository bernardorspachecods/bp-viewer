# PROVISIONAL — Foundation test coverage

Status: `historical_record`

Este ficheiro preserva o registo da primeira integração dos testes de
fundação. Os números e commits abaixo são evidência histórica dessa ronda; a
cobertura atual deixou de ser mantida neste registo; o comportamento atual está
em [`current-state.md`](../current-state.md).

## Objective

Add executable automatic coverage for the app foundations: filesystem scanner,
lazy tree loading, filtering/search, tab state and persistence-related behavior.

## Context

The Markdown adapter already has an executable contract runner. This work is
intentionally separate from Markdown rendering and focuses on pure seams that
can run with the current macOS CommandLineTools toolchain.

## Scope

- inspect the repository documentation and current implementation;
- expose the smallest justified pure foundation seams through `BPViewerCore`;
- add a focused executable contract runner using temporary fixtures;
- cover scanner behavior, lazy-tree-compatible filtering, tab uniqueness/selection
  and persistence-shaped restoration;
- record evidence, limitations and recommended next steps.

## Non-goals

- changing Markdown adapter behavior;
- redesigning the UI or preview;
- implementing LaTeX;
- changing product decisions or canonical documentation;
- push or integration into `main`.

## Initial status

The work was performed on the isolated branch
`agent/foundation-tests`.

## Work performed

- Moved the pure `DocumentKind`, `FileNode` and `FileSystemScanner` seam into
  `BPViewerCore`, preserving the app's existing behavior while making it
  executable without importing the UI target.
- Added `TabSessionState` to `BPViewerCore` for tab uniqueness, ordering,
  selection, close behavior and persistence-shaped restoration.
- Refactored `AppModel` to use that tab state for opening, selecting, closing,
  restoring and persisting tabs; preview content remains owned by
  `DocumentTab`.
- Added `BPViewerFoundationRunner`, which creates temporary fixtures and emits
  explicit `PASS`/`FAIL` lines.
- Did not alter Markdown adapter behavior or its existing contract runner.

## Files changed

- `Package.swift` — added the `BPViewerFoundationRunner` executable target.
- `Sources/BPViewerCore/FileSystemFoundation.swift` — pure filesystem models,
  scanner and tab-session seam.
- `Sources/BPViewerApp/AppModel.swift` — delegates tab state transitions to
  `TabSessionState`.
- `Sources/BPViewerApp/Models.swift` — keeps UI-only models in the app target.
- `Sources/BPViewerApp/SidebarView.swift` — imports the shared `FileNode` type.
- `Sources/BPViewerApp/FileSystemScanner.swift` — removed after extraction.
- `Sources/BPViewerFoundationRunner/main.swift` — foundation contracts.

## Executed validation

All commands were run in the isolated worktree with the current
CommandLineTools toolchain:

```text
swift build
Build complete! (1.88s)

swift run BPViewerFoundationRunner
Foundation contracts: 31 passed, 0 failed

swift run BPViewerContractRunner
11 Markdown contracts passed

git diff --check
passed
```

The foundation runner covers:

- deterministic folder-first sorting and hidden-file omission;
- lazy top-level and child scans;
- full recursive scan behavior;
- compatible-only filtering, including unknown lazy folders;
- case-insensitive, trimmed path search and ancestor preservation;
- missing-root non-crash behavior;
- tab insertion and duplicate prevention;
- selection and invalid-selection behavior;
- active-tab selection after close;
- close-to-right and close-others behavior;
- restoration that removes missing/duplicate paths and chooses a valid fallback;
- stable persisted paths.

`swift test` was also attempted and remains unavailable in this environment:

```text
error: no such module 'Testing'
```

That failure belongs to the pre-existing `BPViewerAppTests` target and is a
toolchain limitation, not a failure of the executable runners.

## Findings and limitations

- The runner proves the pure scanner and tab-state behavior used by the app,
  but it does not prove SwiftUI rendering or AppKit event delivery.
- `AppModel` lifecycle behavior is only indirectly covered through the pure
  `TabSessionState` seam. There is no automated test yet for its asynchronous
  tasks, `UserDefaults` isolation, watcher callbacks, or render-generation
  cancellation.
- Lazy loading is tested at the scanner contract boundary. The actual
  `Task` scheduling and generation guards in `AppModel` still require an
  integration test or manual test harness.
- Permission-denied directories, symlink policy, concurrent renames and large
  filesystem performance remain unverified.
- The test target still imports Swift `Testing`; it should either be run with
  a full Xcode toolchain or migrated to a supported test framework later.

## Recommended next steps

1. Review this isolated diff and integrate it only after checking the
   `AppModel` tab transitions against the current UI manually.
2. Add an injectable `UserDefaults`/filesystem gateway seam before testing
   persistence and watcher behavior directly; avoid using the user's defaults
   in tests.
3. Add macOS UI/integration tests for keyboard shortcuts, tab clicks,
   `WKWebView`, lazy expansion and external file refresh.
4. Re-run both executable runners and the standard test target in the full
   Xcode environment.

> PROVISIONAL — reviewed by the primary agent; retained as an evidence record,
> not as a product decision document.

## Historical primary review after initial integration

The primary agent reviewed the isolated diff before integration and found no
critical issue. The commit was integrated into `main` as `1932d32`.

The following commands were re-run after integration:

```text
swift build                                      PASS
swift run BPViewerFoundationRunner               36 passed, 0 failed
swift run BPViewerContractRunner                 11 passed
git diff --check HEAD^ HEAD                      PASS
swift test                                       BLOCKED: no such module 'Testing'
```

The executable runners are sufficient to proceed to the real UI test round,
with the integration gaps listed above remaining explicit. The standard test
target is still a follow-up toolchain/framework task rather than evidence that
the production build is failing.

# Research report: desktop and filesystem

Access date: 2026-09-09  
Scope: macOS desktop shell, local access, change watching, processes, contracts, and tests.  
No changes were made to the repository, code, or prototype.

## 1. Executive summary

The minimum viable architecture should clearly separate:

1. shell and permissions;
2. filesystem gateway;
3. watcher;
4. render coordinator;
5. adapters;
6. preview surface.

The watcher choice must not turn events into absolute truth. On macOS, FSEvents may coalesce or drop events, or signal only that a hierarchy needs to be rescanned. A fresh filesystem snapshot should always be the source of truth.

The conditional recommendation is:

- native SwiftUI/AppKit shell if macOS integration, persistent permissions, and fewer layers are priorities;
- Tauri 2 if reusable web UI and a local Rust core are priorities, provided additional native code for persistent permissions and macOS integration is acceptable;
- Electron 44 if productivity in the web ecosystem and compatibility with Node tools are priorities, accepting a larger bundle and Chromium/Node update cycle;
- Flutter remains plausible but offers no clear advantage for this macOS-first MVP with a WebView-based preview.

There is not enough primary comparative evidence to state concrete memory, startup, or performance figures for these options.

## 2. Question and supported decision

The research examined:

- how to open and browse local folders;
- how to preserve access after restart;
- how to watch for renames, removals, atomic writes, and rapid changes;
- how to react to coalesced or dropped events;
- how to discover and monitor dependencies;
- how to launch, cancel, and supervise external processes;
- how the shell, adapters, and preview communicate;
- packaging and maintenance costs of the main options.

The research supports an architecture with independent contracts, but does not settle the framework or adapter strategy.

## 3. Scope and assumptions

Included:

- macOS;
- local projects with subfolders;
- reading source files without editing them;
- external changes, including atomic replacement;
- local compilers or tools;
- HTML, PDF, or other artifact previews, without choosing a format.

Out of scope:

- Markdown parser;
- LaTeX strategy;
- detailed WebView and PDF security;
- Windows/Linux;
- Finder replacement;
- prototype or implementation.

The project folder is assumed to contain many files, but not necessarily millions, and the app is not required to support network volumes in the MVP.

## 4. Evaluation criteria

- integration with native selection and permission APIs;
- offline operation;
- consistency when events are incomplete;
- updates after external changes;
- dependency support;
- render cancellation and isolation;
- runtime and packaging cost;
- dependency maintenance;
- macOS compatibility;
- ability to keep adapters independent of the shell.


## 5. Claim matrix

| Claim | Importance | Status | Evidence | Limitations |
|---|---:|---|---|---|
| C1. `NSOpenPanel`/SwiftUI can select folders and macOS grants access to the selected resource. | High | Supported | E1 | Persistent access requires additional handling. |
| C2. Security-scoped bookmarks are Apple's mechanism for preserving access between launches. | High | Supported | E2 | Requires entitlements and correct `start/stopAccessing` management. |
| C3. FSEvents can coalesce changes and requires a rescan when it reports `MustScanSubDirs`. | High | Supported | E3, E4 | Detailed behavior should be tested on the target macOS version. |
| C4. Lost or dropped events require rescanning the full observed hierarchy. | High | Supported | E4 | A rescan may be expensive on large trees. |
| C5. Correct initialization starts the watcher before the first scan. | High | Supported | E3 | This is a consistency rule, not a low-latency guarantee. |
| C6. `NSFilePresenter` is not sufficient to detect every external write. | High | Supported | E5 | It covers only changes coordinated by `NSFileCoordinator`. |
| C7. `Process` can run and monitor subprocesses; in a sandbox, children inherit the sandbox. | High | Supported | E6 | The actual LaTeX process tree needs local testing. |
| C8. Tauri 2 separates a Rust core with system access from system WebViews; on macOS it uses WKWebView. | High | Supported | E7 | The WebKit version depends on macOS updates. |
| C9. Tauri's fs plugin provides recursive watching and debounce. | High | Supported | E8 | Actual macOS semantics should be validated against MVP scenarios. |
| C10. Tauri's dialog plugin adds scopes at runtime but documents that they do not persist after restart. | High | Supported | E9 | Custom native bookmark integration may be required. |
| C11. Tauri's shell plugin supports spawn, stdout/stderr, and kill with configurable permissions. | High | Supported | E10 | `kill` alone does not prove that descendants have terminated. |
| C12. Electron 44 includes Chromium 152, Node 24.18.1, and V8 15.2; it requires macOS 13+. | Medium | Supported | E11 | The stable version changes rapidly. |
| C13. Electron separates main and renderer processes and requires IPC for native APIs. | High | Supported | E12 | The IPC surface must be explicitly limited. |
| C14. `fs.watch` uses FSEvents for directories on macOS, but has limited semantics and possible network filesystem issues. | High | Supported | E13 | The documentation consulted is for Node 26, not exactly the Node embedded in Electron 44. |
| C15. Chokidar 5 normalizes events, supports atomic writes, and provides `awaitWriteFinish`. | High | Supported | E14 | It is ESM-only and requires Node 20; content still needs revalidation. |
| C16. `notify` 8.2.0 provides an FSEvents backend on macOS and separate debouncers. | Medium | Supported | E15 | Network filesystems remain limited. |
| C17. Watchman provides recrawl, settle, clocks, and incremental queries, but adds an external service. | Medium | Supported | E16 | Its operational documentation includes old pages. |
| C18. Flutter 3.47.2 supports macOS desktop and the official `file_selector` plugin selects directories. | Medium | Supported | E17 | macOS integration, sandboxing, and native appearance require additional work. |
| C19. There is not enough comparable primary benchmarking to declare a winner for memory or startup. | High | Not established | Q1–Q10 | Resolve through local measurement, not documentation. |

## 6. Investigated alternatives

### Native SwiftUI/AppKit shell

Capabilities:

- `NSOpenPanel` for selecting directories;
- security-scoped bookmarks for persistent access;
- direct FSEvents access;
- `FileManager` for enumeration;
- `Process` for external tools;
- Uniform Type Identifiers and `Info.plist` for file associations;
- direct integration with menus, drag and drop, and the macOS lifecycle.

Costs:

- UI and infrastructure in Swift;
- greater direct responsibility for bridging to the preview;
- event streams and permissions must be modeled explicitly;
- changes to Apple APIs require maintenance.

### Tauri 2

Capabilities:

- web frontend;
- Rust core;
- WKWebView provided by macOS;
- official plugins for filesystem, dialogs, and shell;
- asynchronous IPC between frontend and core;
- small bundle because it does not include a full browser.

Costs:

- introduces Rust and a plugin layer;
- scopes and permissions are configurable but must be understood;
- the dialog plugin documents nonpersistent scopes;
- the security-scoped access API documented by the fs plugin is effectively iOS-specific, leaving macOS integration to be validated;
- Tauri documents that development does not fully reproduce App Sandbox conditions for distribution.

### Electron 44

Capabilities:

- web frontend and app-controlled Chromium;
- embedded Node.js;
- mature APIs for dialogs, IPC, subprocesses, and filesystem;
- Chokidar can normalize watching and atomic writes;
- process utilities for isolating heavy or fragile work.

Costs:

- Chromium, Node, and V8 are bundled;
- frequent release cycle;
- larger distribution bundle;
- main/renderer/preload increase the architectural surface;
- persistent integration with the macOS sandbox is more sensitive, especially for the Mac App Store.

### Flutter

Capabilities:

- desktop app compiled for macOS;
- official plugin for selecting directories;
- option to use native Swift/Objective-C code;
- distribution via `.app` or the App Store.

Costs:

- it is not naturally a WebKit UI;
- matching the macOS appearance requires adaptation;
- permissions and native integration are still needed;
- it showed no specific advantage over SwiftUI/Tauri for this workflow.

### Watchman as an external service

It is technically strong for large or highly active trees, with:

- incremental state;
- clocks;
- settle periods;
- recovery through recrawl;
- queries from an earlier position.

However, it requires distributing, starting, supervising, and diagnosing another process. For a personal app, reserve it for cases where tests show that direct FSEvents or `notify`/Chokidar are insufficient.

## 7. Evidence-based comparison

| Criterion | SwiftUI/AppKit | Tauri 2 | Electron 44 | Flutter |
|---|---|---|---|---|
| macOS integration | Most direct | Good, with bridging as needed | Good, through Electron/Node APIs | Good, but often through plugins/native code |
| Persistent permissions | Best direct support through Apple bookmarks | Risk area; needs validation/bridge | Documented support mainly for MAS bookmarks | Requires Xcode/entitlements configuration |
| Local filesystem | `FileManager`/FSEvents | Rust or plugins | Node/Chokidar | Dart/plugin/native |
| External processes | `Process` | Shell plugin/Rust | Node utility process/child process | Dart/native |
| Web-based preview | Requires explicit WKWebView | Natural | Natural | Requires an additional component |
| Bundle | No additional web runtime | Small relative to Electron, according to vendor docs | Large; embeds Chromium/Node | Includes Flutter engine |
| Dependencies | Xcode/Apple SDK | Rust + Node frontend | Node/npm + Electron | Flutter/Dart + Xcode |
| Update cycle | OS APIs | Tauri + Rust + OS WebKit | Frequent Chromium/Node releases | Flutter SDK/plugins |
| Operational complexity | High initially, low at runtime | Medium | Medium/high | Medium |
| Confidence for this MVP | High | Medium/high, conditional | Medium/high | Medium |

The table is not a score and does not settle the decision. It summarizes suitability inferred from documented capabilities.

## 8. Evidence

### E1 — folder selection

Apple documentation states that `NSOpenPanel` can select directories and that when a user selects a folder, macOS extends the sandbox to its contents recursively.

Sources: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) and [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel).

Establishes:

- native folder selection;
- access to items inside the selected folder during the session.

Does not establish:

- that access survives a restart;
- that every subfolder is accessible given POSIX, ACL, or TCC restrictions.

### E2 — persistent access

Apple documents security-scoped bookmarks for preserving the user's intent between launches. The bookmark must be resolved, updated if stale, activated with `startAccessingSecurityScopedResource`, and released with `stopAccessingSecurityScopedResource`.

Sources: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) and [NSURL bookmarks](https://developer.apple.com/documentation/foundation/nsurl).

Establishes:

- official mechanism for reopening a selected folder;
- need to handle stale bookmarks;
- cost of managing resources/kernel.

### E3 — coalescing and snapshot

Apple's FSEvents documentation states that events may be coalesced hierarchically, signaled by `MustScanSubDirs`, and recommends combining notifications with a snapshot of the hierarchy.

Source: [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html).

Establishes:

- an event indicates that something changed;
- the snapshot should be compared with the current state;
- the watcher should start before the initial scan.

### E4 — dropped events and changed root

Current FSEvents flag documentation specifies `MustScanSubDirs`, `UserDropped`, `KernelDropped`, and `RootChanged`. Dropped events require a full scan; `WatchRoot` can detect a renamed or removed root.

Sources: [FSEventStreamEventFlags](https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags), [MustScanSubDirs](https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags/kfseventstreameventflagmustscansubdirs), and [WatchRoot](https://developer.apple.com/documentation/coreservices/kfseventstreamcreateflagwatchroot).

Establishes:

- need for a defensive rescan;
- need to represent a moved/deleted root as an explicit state;
- inability to rely on individual notifications alone.

### E5 — `NSFilePresenter` limitation

Apple documents that `NSFilePresenter` receives notifications only for changes made through `NSFileCoordinator`, not low-level writes.

Source: [NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter).

Establishes:

- it is not suitable as the sole watcher for changes made by LLMs, editors, or arbitrary scripts.

### E6 — native subprocesses

`Process` can launch and observe state, capture termination, and send interrupt/terminate signals. In App Sandbox, child processes inherit the parent process's sandbox.

Sources: [Process](https://developer.apple.com/documentation/foundation/process), [Process.run](https://developer.apple.com/documentation/foundation/process/run%28_%3Aarguments%3Aterminationhandler%3A%29), and [terminationHandler](https://developer.apple.com/documentation/foundation/process/terminationhandler).

Establishes:

- a sufficient basis for a local runner;
- need to distinguish normal exit, failure, and cancellation;
- relevance of entitlements for sandboxed distribution.

### E7 — Tauri architecture

Tauri documents a Rust core with system access and separate WebViews; on macOS it uses the system WKWebView. The WebView is not included in the final executable.

Sources: [Tauri Process Model](https://v2.tauri.app/concept/process-model/), [Tauri IPC](https://v2.tauri.app/concept/inter-process-communication/), and [Tauri App Size](https://v2.tauri.app/concept/size/).

Version checked: the release listing showed Tauri 2.11.5 as latest in July 2026; [official releases](https://github.com/tauri-apps/tauri/releases).

Establishes:

- suitable separation for keeping filesystem/processes outside the UI;
- dependency on the macOS WebKit version;
- potential for a smaller bundle.

Does not establish:

- concrete memory use or startup time;
- that all plugins meet macOS sandbox requirements.

### E8 — watching in Tauri

The fs plugin documents `watch`, `watchImmediate`, configurable debounce, and optional recursive watching.

Fonte: [Tauri File System plugin](https://v2.tauri.app/plugin/file-system/).

Establishes:

- an API sufficient for an initial watcher;
- debounce availability;
- explicit recursion option.

Does not establish:

- specific guarantees for atomic replacement;
- complete recovery after dropped FSEvents events.

### E9 — scopes and persistence in Tauri

The dialog plugin documents that selected paths are added to scopes at runtime, but that this change is not persisted after restart. The fs plugin documents `startAccessingSecurityScopedResource` as an iOS-specific operation and a no-op on other platforms.

Sources: [Tauri Dialog plugin](https://v2.tauri.app/reference/javascript/dialog/) and [Tauri FS reference](https://v2.tauri.app/reference/javascript/fs/).

Establishes:

- a material risk for “open a folder and reopen it later” in a sandboxed app;
- need for a native bridge or validation in a distributed build.

### E10 — processes in Tauri

The shell plugin provides `execute`, `spawn`, stdout, stderr, close/error events, and `kill`. Permissions must declare allowed programs and arguments.

Sources: [Tauri Shell plugin](https://v2.tauri.app/plugin/shell/) and [Shell JavaScript reference](https://v2.tauri.app/reference/javascript/shell/).

Establishes:

- functional support for local compilers;
- option to restrict executables and arguments;
- need to decide whether tools will be installed by the user or bundled.

### E11 — current Electron

Electron 44.0.0 was released on 2026-08-25 and includes Chromium 152.0.7977.54, Node 24.18.1, and V8 15.2. Electron 44 requires macOS 13 or later. The official policy supports the three most recent stable versions.

Sources: [Electron 44](https://www.electronjs.org/blog/electron-44-0), [Electron v44 release](https://releases.electronjs.org/release/v44.0.0), [release schedule](https://releases.electronjs.org/schedule), and [breaking changes](https://www.electronjs.org/docs/latest/breaking-changes).

### E12 — processes and IPC in Electron

Electron separates the main and renderer processes; native and filesystem APIs should be exposed through preload/IPC. `utilityProcess` can run isolated work with stdout/stderr and `kill`.

Sources: [Electron Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model), [Electron IPC](https://www.electronjs.org/docs/latest/tutorial/ipc), and [utilityProcess](https://www.electronjs.org/docs/latest/api/utility-process).

### E13 — Node `fs.watch`

Node documentation specifies that on macOS, `fs.watch` uses kqueue for files and FSEvents for directories. The API provides only `rename`/`change` events, may be unreliable on some filesystems, and is not recommended as an absolute guarantee on network filesystems.

Fonte: [Node.js `fs.watch`](https://nodejs.org/api/fs.html#fswatchfilename-options-listener).

### E14 — Chokidar

Version 5.0.0 documents:

- event normalization;
- atomic write support;
- `awaitWriteFinish`;
- `add`, `change`, `unlink`, and error events;
- minimum dependency on Node 20 and ESM-only packaging.

Source: [Chokidar package documentation](https://www.npmjs.com/package/chokidar).

This improves ergonomics but does not make the watcher a source of truth: content should be reopened and validated after an event.

### E15 — Rust `notify`

`notify` 8.2.0 documents FSEvents as the default macOS backend, kqueue as an alternative, polling, and separate debouncers. It also documents network filesystem limitations.

Sources: [notify 8.2.0](https://docs.rs/notify/latest/notify/) and the [official repository](https://github.com/notify-rs/notify).

### E16 — Watchman

Watchman 2026.08.10.00 was the latest release observed on 2026-08-10. The documentation describes:

- `watch-project`;
- clocks;
- `since`;
- settle period;
- recrawl after loss of synchronization;
- persistent per-user service.

Sources: [Watchman releases](https://github.com/facebook/watchman/releases), [watch-project](https://facebook.github.io/watchman/docs/cmd/watch-project), [clockspec](https://facebook.github.io/watchman/docs/clockspec), and [triggers](https://facebook.github.io/watchman/docs/cmd/trigger).

### E17 — Flutter

Current Flutter documentation reflects Flutter 3.47.2. macOS desktop is supported, and the official `file_selector` supports directory selection and requires entitlements for access to selected files.

Sources: [Flutter release notes](https://docs.flutter.dev/release/release-notes), [desktop support](https://docs.flutter.dev/platform-integration/desktop), [macOS building](https://docs.flutter.dev/platform-integration/macos/building), and [file_selector](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector).

## 9. Contracts between components

The contracts below are architectural recommendations, not product decisions.

### `ProjectSession`

Responsible for:

- currently open root;
- URL/bookmark and access state;
- `available`, `permissionLost`, `rootMoved`, and `closed` states;
- mapping between relative paths and current resources.

The API should prefer paths relative to the root and opaque identifiers. A filesystem identifier may help during a session, but Apple documents that it does not persist across restarts.

Source: [fileResourceIdentifier](https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey).

### `FileSystemGateway`

Should expose:

- open a folder;
- list immediate children;
- enumerate subtrees;
- read bytes/text;
- retrieve metadata;
- resolve relative paths;
- check existence and type;
- return permission, removal, or race errors.

The visual tree should support lazy loading. `FileManager` supports both shallow and deep enumeration.

Sources: [FileManager](https://developer.apple.com/documentation/foundation/filemanager) and [contentsOfDirectory](https://developer.apple.com/documentation/foundation/filemanager/contentsofdirectory%28at%3Aincludingpropertiesforkeys%3Aoptions%3A%29).

### `FileWatcher`

Input:

- root;
- recursive mode;
- exclusion policy;
- session token.

Output:

```text
ChangeBatch {
  sessionID
  sequence
  paths[]
  kinds: created | modified | removed | renamed
  rescanScope: none | directory | subtree | root
  permissionState
}
```

Rules:

- events may be duplicated;
- paths may no longer exist;
- `rescanScope != none` invalidates incremental conclusions;
- a root change must be represented explicitly;
- the watcher should not deliver “new content” directly; it should only invalidate snapshots.

### `DependencyIndex`

After rendering, the adapter may return:

```text
DependencyManifest {
  documentID
  dependencies[]
  unresolvedReferences[]
  generation
}
```

For dependencies inside the root, the root watcher is usually sufficient. For dependencies outside the root, choose whether to:

- request additional access;
- watch another root;
- mark the dependency as unobservable;
- revalidate on demand.

This decision depends on the adapters and remains open.

### `RenderCoordinator`

Contrato:

```text
render(documentID, sourceRevision, dependencyRevision) -> CancellableRender
```

Recommended behavior:

- at most one active render per document;
- new changes increment a generation;
- the previous render may be cancelled;
- if not cancelled, its result is discarded;
- only the latest generation may update the preview;
- changes during compilation leave a new render pending;
- temporary outputs stay outside the project folder;
- failures produce structured errors, not just raw text.

### `ProcessRunner`

Should accept:

- identified executable;
- separate arguments, never a shell command string;
- working directory;
- environment;
- temporary directory;
- separate stdout/stderr capture;
- optional timeout;
- cancellation;
- final state: success, failed, cancelled, launchFailed.

The contract should distinguish “process ended” from “valid artifact produced.”

### `PreviewSink`

Recebe:

```text
PreviewUpdate {
  documentID
  generation
  artifact
  diagnostics[]
}
```

The sink rejects updates from old generations. The artifact type remains abstract: the adapter may choose HTML, PDF, or another format.

### Shell–UI communication

A UI should receive:

- file tree;
- selection changes;
- access state;
- progress;
- diagnostics;
- approved preview.

The UI should not:

- read arbitrary paths;
- launch compilers directly;
- decide that an event represents final content;
- replace the shell's permission mechanism.

## 10. Debounce, queues, and race conditions

Recommended workflow:

1. start the watcher;
2. create the initial snapshot;
3. open the folder in the tree;
4. group nearby changes when events arrive;
5. rescan affected directories;
6. calculate affected documents through the dependency index;
7. increment the generation;
8. wait according to the chosen stability policy;
9. cancel or allow the previous render to finish;
10. publish only a result whose generation is still current.

A single fixed debounce window should not be assumed to be universally correct. Validate it for:

- small files replaced atomically;
- files written in chunks;
- slow compilation;
- many successive changes;
- dependency changes.

Correctness depends more on generation validation and rescanning than on the exact debounce value.

## 11. Conflicts and refutations

### “Watching the open file is enough”

Refuted. A document may depend on images, includes, bibliography, macros, or other files. The contract must allow the adapter to declare dependencies.

### “FSEvents delivers every event exactly once”

Refuted. Apple documents coalescing, dropped events, and the need to rescan.

### “`NSFilePresenter` handles external updates”

Refuted for this use case. It does not cover low-level changes that do not go through `NSFileCoordinator`.

### “Chokidar eliminates the atomic-write problem”

Partially refuted. Chokidar provides specific handling, but the app still needs to reopen the file, confirm its state, and handle changes during rendering.

### “Watchman is automatically better”

Not established. Watchman offers more infrastructure, but adds a daemon, additional state, and distribution cost. Prefer it only if tests justify it.

### “Tauri is automatically the lightest option”

Partially supported only for bundle size. Tauri documentation says it does not include the WebView and that a minimal app can be small; there is no comparable benchmark here for `bp-viewer` memory use, startup, or performance.

### “Electron is impractical because it is heavy”

Not established as a runtime claim. Electron documentation confirms that Chromium/Node are embedded and apps tend to take more disk space, but does not prove that the experience is unsuitable for this personal app.

## 12. Conditional recommendation

The preferred option for further investigation is a native SwiftUI/AppKit shell when:

- macOS is the only relevant platform;
- persistent permissions are a priority;
- the app should behave like a Mac app;
- the cost of implementing the native UI layer is acceptable.

Tauri 2 is a strong alternative when:

- web UI is an important advantage;
- a Rust core is acceptable;
- validating or implementing macOS integration for bookmarks and sandboxing is acceptable;
- distribution size matters.

Electron 44 is suitable when:

- the team wants to stay with TypeScript/Node;
- closer integration with web tools is worth the bundle size;
- tracking Chromium, Node, and frequent releases is acceptable;
- macOS 13+ is an acceptable minimum target.

Flutter has an advantage only if a compiled UI and future cross-platform support are priorities. The evidence shows no specific advantage for a macOS-first MVP with a possible WebView preview.

Confidence: medium.  
This conclusion is an inference about suitability, not a benchmark or final decision.

## 13. Implications for the MVP

- The watcher should invalidate and trigger a rescan; it should not be responsible for determining final content.
- The open root needs an explicit permission state.
- Persistent paths should be represented by bookmarks or an equivalent, not only as strings.
- The tree should support shallow enumeration and incremental loading.
- Rendering should be versioned by generation.
- An old compilation result must never replace a newer preview.
- Dependencies declared by an adapter should be able to invalidate the open document.
- Temporary artifacts and logs should stay outside the user's folder.
- The adapter contract should not assume HTML, PDF, or another format.
- Sandboxed distribution should be tested separately from development execution.

## 14. Filesystem tests before finalizing the architecture

| Test | Expected result |
|---|---|
| Open a folder with a deep tree and many files | UI remains responsive; the tree can load progressively. |
| Open an empty folder | Valid state; “empty” is not confused with “no permission.” |
| Create a Markdown/LaTeX file | Entry appears without restarting the app. |
| Remove a file | Entry disappears; if selected, the preview enters an explicit unavailable state. |
| Rename a file | Tree updates; selection is preserved only if identity can be confirmed. |
| Rename a parent directory | Relative paths and selection are recalculated correctly. |
| Atomically replace the open file | Final content is read; the app does not get stuck on the temporary file or an empty state. |
| Write the same file in chunks | The app does not repeatedly render incomplete states or, if it does, never publishes stale state. |
| Make several changes during compilation | At most one preview is published for the latest generation. |
| Cancel compilation | Process and relevant descendants terminate or are diagnosed; temporary artifacts are cleaned. |
| Change an included dependency | The open document is invalidated and rendered again. |
| Add/remove a dependency | Index updates and old references no longer trigger renders. |
| Force event coalescing | Rescan reconstructs the correct state. |
| Trigger `UserDropped`/`KernelDropped`, if possible | Full rescan runs without relying on a partial path list. |
| Remove or move the observed root | State becomes `rootMoved`/`unavailable`, without a crash. |
| Reopen after renaming the root | Bookmark or chosen mechanism finds the current root, or requests reselection. |
| Make a subfolder unreadable | Error is localized; the rest of the tree remains usable where possible. |
| Restore permissions | After reauthorization, the tree and watcher are restored. |
| Restart the app | The selected folder reopens without reselection, if that is the chosen policy. |
| Stale bookmark | It is detected, recreated, and persisted again. |
| Files with Unicode and long names | Identity, reading, and sorting remain correct. |
| Case-insensitive filesystem | Case-only renames do not corrupt the tree. |
| Symlinks and cycles | The chosen follow/show/ignore policy is consistent and causes no infinite recursion. |
| Crash during compilation | No output is left inside the project and no permanent locks remain. |
| Optional network/SMB volume | Behavior is diagnosed as supported, degraded, or out of MVP; it is not assumed. |

## 15. Gaps and next tests

Only local testing can resolve:

- actual memory use and startup time;
- enumeration cost in folders similar to the theses;
- exact semantics of Tauri fs watch on macOS;
- permission persistence in signed and sandboxed builds;
- termination of the entire LaTeX process tree;
- behavior with tools installed through MacTeX/Homebrew;
- WebKit stability on the chosen minimum macOS version;
- suitable debounce and stability values;
- actual cost of maintaining a dependency index.

Web research could not resolve these points without a prototype or local installation.

## 16. Source ledger

| Source | Status | Version/date | Use |
|---|---|---|---|
| Apple App Sandbox | Used | Current docs, consulted 2026-09-09 | Folder selection and bookmarks |
| Apple NSOpenPanel | Used | Current docs | Native dialog |
| Apple FSEvents API/reference | Used | Current docs | Flags and lifecycle |
| Apple FSEvents Programming Guide | Used with caveat | Archived guide, stable content | Coalescing, snapshots, startup order |
| Apple NSFilePresenter | Used | Current docs | Refuting an incomplete mechanism |
| Apple Foundation Process | Used | Current docs | Subprocesses |
| Apple FileManager | Used | Current docs | Enumeration |
| Tauri v2 docs | Used | Current docs; concepts updated in 2026 | Core, IPC, fs, shell |
| Tauri releases | Used | 2.11.5 observed in 2026-07 | Version check |
| Electron 44 docs/releases | Used | 44.0.0, 2026-08-25 | Runtime and compatibility |
| Node.js fs docs | Used with caveat | Node 26.8.1 docs | `fs.watch` semantics |
| Chokidar package docs | Used | 5.0.0 | Normalization and atomic writes |
| Rust notify | Used | 8.2.0 | Rust alternative |
| Watchman | Used with caveat | 2026.08.10.00 | Alternative for large trees |
| Flutter docs/file_selector | Used | Docs reflect 3.47.2 | Additional alternative |
| Blogs, snippets, Stack Overflow, and rankings | Rejected | — | Not sufficient primary evidence |
| Non-reproducible benchmarks | Rejected | — | Conditions incompatible with `bp-viewer` |
| Vendor marketing | Limited | — | Used only to describe a vendor's own architecture, not superiority |

## 17. Research log

| ID | Research path | Result |
|---|---|---|
| Q1 | Apple App Sandbox, NSOpenPanel, security-scoped bookmarks | Confirmed folder selection and conditional persistence |
| Q2 | Apple FSEvents and current flags | Confirmed coalescing, dropped events, and root changes |
| Q3 | Apple FileManager and NSFilePresenter | Confirmed snapshot/enumeration and coordination limitations |
| Q4 | Apple Foundation Process | Confirmed execution and termination |
| Q5 | Tauri process model, fs, dialog, and shell | Confirmed capabilities and persistent-scope gap |
| Q6 | Tauri releases/distribution | Confirmed version and operational costs |
| Q7 | Electron release schedule, process model, IPC, and dialog | Confirmed runtime, compatibility, and contracts |
| Q8 | Node `fs.watch` and Chokidar | Confirmed limitations and event normalization |
| Q9 | Rust notify and Watchman | Compared an embedded watcher with an external service |
| Q10 | Flutter desktop/macOS/file_selector | Evaluated an additional alternative |

## 18. Reason for stopping

The research provides enough evidence to:

- compare shells;
- define independent contracts;
- establish minimum watcher semantics;
- specify tests before finalizing the architecture.

The remaining relevant questions are empirical — sandbox permissions, performance, process cancellation, and debounce — and require local testing. Further web research would likely repeat vendor documentation without reducing these uncertainties.

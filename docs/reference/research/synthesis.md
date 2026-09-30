# Technical synthesis for human decision-making

This synthesis brings together the four research reports prepared for `bp-viewer`. It does not independently revalidate the primary sources cited in the reports or replace testing on a Mac with Bernardo's actual documents. Where a conclusion depends on a specific detail, the relevant section of the original report is cited.

**Usage status:** this is a record of evidence and comparisons, not the product's
source of truth. The current MVP has adopted native SwiftUI/AppKit for personal
use on macOS. The alternatives below remain useful context for technical
decisions that are still open, but they do not describe the app's current state.

## 1. Executive summary

The four reports provide a sound basis for a prototype, but do not automatically
select a final stack. The strongest decision at this point concerns the app's
contracts and invariants, not SwiftUI, Tauri, Electron, PDF, HTML, MacTeX,
Tectonic, `remark`, or another candidate.

### What can already guide the MVP

- The user's open folder, permissions, and root state should be modeled explicitly. A path string alone cannot represent persistent access on macOS.
- Treat the watcher as an invalidation signal. The source of truth is a fresh filesystem snapshot/rescan; events may be coalesced, duplicated, dropped, or indicate a root change.
- Adapters should declare dependencies. A Markdown file may depend on images and other documents; a LaTeX file may depend on `.tex`, `.bib`, `.sty`, `.cls`, images, fonts, and helper tools.
- Version renders by generation. An older render must never replace the preview for the latest change, even if it finishes later.
- Keep compilation and temporary artifacts outside the user's source folder. Processes need timeouts, cancellation, log capture, and structured diagnostics.
- Treat Markdown/HTML as untrusted content: use allowlist sanitization, disable content JavaScript, apply CSP, confine resources to the authorized root, and intercept navigation.
- Treat LaTeX as execution of potentially dangerous tools: disable shell escape by default, use a temporary workspace, set resource limits, and do not automatically install packages in the initial workflow.

### Decisions that remain with the user

- Whether the LaTeX preview should prioritize visual fidelity to the compiled PDF or HTML navigation and semantics.
- Whether the first target is a personal prototype that depends on tools installed on the Mac, or a distributable sandboxed app.
- Shell comparisons remain context; the current MVP has already chosen native SwiftUI/AppKit. Reconsider this only if distribution requirements or local tests change.
- Which Markdown dialect, mathematics, links outside the root, external links, and LaTeX engines are part of real usage.

**Overall status:** the reports offer conditional recommendations with varying confidence; no final technical decision has been approved.

## 2. Current state: what the four reports do and do not establish

### Findings reported by the agents

The reports describe the following as documented capabilities, linked to their claim and evidence matrices:

- CommonMark is the clearest syntactic baseline; GFM adds tables, footnotes, task lists, strikethrough, and autolinks, among other features. Neither standard provides academic bibliographies, includes, or semantic cross-chapter references ([Markdown → HTML](reports/markdown-html.md), sections 5–8).
- `cmark-gfm`, `markdown-it`, `micromark`, `remark`/`unified`, `swift-markdown`, and `markdown-rs` address different parts of the problem. `remark`/`unified` offers an extensible AST pipeline; `cmark-gfm` offers a small native core; the other options have their own combinations of extensions, rendering, and integration ([Markdown → HTML](reports/markdown-html.md), section 6).
- A traditional TeX distribution with `latexmk` handles multiple passes, included files, graphics, and bibliographies. Tectonic offers an executable/bundle, cache, and offline options, but differs in engine, bundle, and Biber support. TeX4ht, lwarp, and LaTeXML convert to HTML through approaches distinct from the original PDF ([LaTeX → preview](reports/latex-preview.md), sections 5–9).
- On macOS, folder selection, security-scoped bookmarks, FSEvents, and `Process` have dedicated APIs. FSEvents can coalesce or drop events; `NSFilePresenter` does not cover every low-level write ([desktop and filesystem](reports/desktop-filesystem.md), sections 5 and 8).
- `WKWebView` and PDFKit provide suitable reading surfaces, but HTML and PDF can pose navigation, resource, or action risks. App Sandbox and notarization reduce certain risks and impose restrictions, but do not make content or compilers trustworthy ([preview, security, and distribution](reports/preview-security-distribution.md), sections 5–10).

### Technical inferences supported by the reports

- A contract-based architecture — session, filesystem, watcher, dependency index, render coordinator, process runner, and preview sink — reduces coupling among the shell, adapters, and artifact format. This is the central recommendation in [desktop and filesystem](reports/desktop-filesystem.md), sections 9–10.
- Prerendering outside the WebView clarifies the separation between reading/resolution, parsing, sanitization, and presentation. It does not remove the need to control HTML, URLs, resources, and CSP ([Markdown → HTML](reports/markdown-html.md), section 7; [preview, security, and distribution](reports/preview-security-distribution.md), section 7).
- PDF is the most direct reference if “preview” means checking the composition produced by LaTeX. HTML may be better for structure, search, and accessibility, but introduces a compatibility boundary that must be accepted and measured ([LaTeX → preview](reports/latex-preview.md), sections 7, 15, and 16).

### What the reports do not establish

- They do not establish a winner for memory, startup, speed, or maintenance among SwiftUI/AppKit, Tauri, Electron, and Flutter. The desktop report rejects uncontrolled comparative benchmarks (claim C19).
- They do not establish that a Markdown pipeline reproduces Bernardo's actual documents or that KaTeX or MathJax covers the mathematics he uses.
- They do not establish that MacTeX, BasicTeX, or any external TeX installation can be used in a sandboxed app distributed through the Mac App Store. The security report identifies this as a material incompatibility to test.
- They do not establish Tectonic's compatibility with the real thesis, including its engine, fonts, paths, packages, bibliography, and Biber.
- They do not establish general visual equivalence among PDF, TeX4ht, lwarp, and LaTeXML.
- They do not establish the right debounce, write-stability, timeout, output-limit, or memory values.
- They do not establish how `WKWebView` and PDFKit actually behave with every path, symlink, redirect, annotation, and action on the chosen minimum macOS version.

### How to read the conclusions

The four documents are research-agent reports. Their primary sources, observed versions, limitations, and stopping rationale are preserved in the original reports. In this synthesis:

- **Reported fact** means a capability or limitation the agent tied to documentation/evidence in the report; it does not mean that it was revalidated for this task.
- **Technical inference** means a suitability conclusion derived from the facts, subject to the described limitations.
- **Conditional recommendation** means a direction that is valid only under certain priorities or test results.
- **Bernardo's decision** means a product, usage, risk, or distribution choice that the agent should not make.

## 3. Actionable decisions without personal preference: contracts, invariants, tests, and guardrails for the MVP

These do not choose a technology. They record the rules the reports suggested
for the workflow described at the time.

### 3.1 Minimum contracts between components

**Reported fact:** [desktop and filesystem](reports/desktop-filesystem.md), section 9, proposes independent contracts. The table below is an operational consolidation of those contracts.

| Contract | Should represent | Must not assume |
|---|---|---|
| `ProjectSession` | open root, bookmark/reference, `available`, `permissionLost`, `rootMoved`, or `closed` state, and mapping from IDs to relative paths | that a text path remains authorized after restart |
| `FileSystemGateway` | list, enumerate, read, retrieve metadata, resolve relative paths, and distinguish missing, removed, racing, and permission states | that the UI can read any arbitrary path |
| `FileWatcher` | batches with session, sequence, observed paths, change types, and `rescanScope` | that an event contains final content or is complete |
| `DependencyIndex` | per-document manifest, dependencies, unresolved references, and generation | that all helpers appear in the tree or are inside the root |
| `RenderCoordinator` | render by document and revision, cancellation, generation, and queue | that two renders of the same document can publish freely |
| `ProcessRunner` | identified executable, separate arguments, environment, temporary directory, stdout/stderr, timeout, cancellation, and final state | that “process ended” means “valid artifact exists” |
| `PreviewSink` | artifact, document, generation, and diagnostics; rejection of old generations | that the artifact is always HTML or always PDF |

**Invariant:** the UI receives results approved by the shell/coordinator; it does not start compilers, treat an event as final content, or read arbitrary paths.

### 3.2 Filesystem and update invariants

**Conditional recommendation common to the reports:**

1. Start the watcher before the first scan.
2. Keep a current snapshot of the observed hierarchy.
3. Group nearby events, but rescan whenever an event indicates coalescing, loss, root change, or uncertain scope.
4. Reopen and validate content after events; do not trust only the received path.
5. Represent removal, rename, moved root, and lost permission as explicit states.
6. Determine affected documents from the `DependencyIndex`, not just the selected file.
7. Increment a generation when a relevant change is recognized.
8. Publish only a result whose generation is still current.

**Minimum tests:** incremental write; atomic rename; several rapid changes; changes to an image, `.bib`, `.sty`, `.cls`, or include; dependency removal/rename; coalesced or dropped events; moved/removed root; stale bookmark; restart; symlinks, Unicode, spaces, and case-only rename.

### 3.3 Compilation and artifact invariants

- Compile in a temporary workspace per project/root, outside the source folder.
- Pass separate arguments to the process; never construct a shell command string from content.
- Capture stdout, stderr, logs, and, when available, the recorder/dependency file.
- Enforce timeouts, output limits, and cancellation; check that relevant child processes terminate.
- Serialize compilation per root and prevent concurrent writes to the same output.
- Distinguish success, success with warnings, partial PDF, fatal error, timeout, cancellation, missing dependency, missing tool, and input prompt.
- Keep the last valid preview only if the UX policy calls for it, mark it stale, and do not present it as the current result.
- Do not install packages automatically in the base workflow without an explicit decision; runtime installation reduces initial effort but harms offline predictability.

### 3.4 Preview and content guardrails

**Conditional recommendation with high confidence in the security report:**

- treat Markdown/HTML, images, SVG, and PDF as potentially hostile content;
- disable content JavaScript in `WKWebView` by default;
- sanitize HTML after transformations that could introduce unsafe content, using a small, versioned allowlist;
- apply CSP as defense in depth and do not expose an unnecessary native bridge;
- block `script`, `on*` handlers, `iframe`, `object`, `embed`, forms, `base`, and unvalidated HTML/SVG/CSS;
- resolve resources inside the authorized canonical root, with an explicit policy for `..`, absolute paths, and symlinks;
- intercept navigation, redirects, new windows, and downloads;
- do not load external links inside the preview; if that option exists, require an explicit action;
- block or confirm PDF actions; do not treat them as mere rendering;
- keep the web data store nonpersistent if the preview does not need web state;
- do not grant a network entitlement if the MVP does not need network access.

**Important limitation:** these guardrails are defense-in-depth inferences from the reports. They do not guarantee security against bugs in WebKit, PDFKit, compilers, parsers, or libraries.

### 3.5 Cross-cutting acceptance criteria

The MVP should consider a workflow validated only after it demonstrates the following with a representative fixture:

- open an authorized root and restore it according to the chosen policy;
- reflect external changes without publishing incomplete or stale state;
- locate dependencies even if they are hidden by the tree filter;
- avoid writing compilation artifacts into the source folder;
- show structured errors without automatically losing the last valid preview, if that UX is chosen;
- block scripts, dangerous schemes, root escapes, and unconfirmed external actions;
- cancel or invalidate a slow render without allowing an old generation to win;
- work offline during use, given the dependencies made available in advance.

## 4. Technical decision matrix

“Status” describes what the reports currently support; it does not mean an
approved decision. In the shell row, “open” refers only to the report
comparison; the current plan already records SwiftUI/AppKit as the personal
MVP choice.

| Decision | Real alternatives | Evidence in reports | Trade-offs | Impact | Status |
|---|---|---|---|---|---|
| Decision | Real alternatives | Evidence in reports | Trade-offs | Impact | Status |
|---|---|---|---|---|---|
| Desktop shell | SwiftUI/AppKit; Tauri 2; Electron 44; Flutter | [desktop](reports/desktop-filesystem.md), sections 6–7 and 12 | Native favors permissions and integration; Tauri separates Rust core and web UI; Electron favors Node/web at the cost of bundle size and releases; Flutter showed no specific advantage | Affects UI, IPC, permissions, packaging, and adapters | **Open; requires opinion and local tests** |
| Folder persistence | security-scoped bookmarks; shell-mediated equivalent; select on every launch | [desktop](reports/desktop-filesystem.md), E1–E2; [security](reports/preview-security-distribution.md), E12–E14 | Bookmarks preserve intent but may become stale and require `start/stop`; Tauri plugins do not demonstrate sufficient macOS persistence | Affects tab restoration, access, and sandboxed distribution | **Contract required; mechanism open** |
| Watcher semantics | direct FSEvents; framework watcher; `notify`; Chokidar; Watchman | [desktop](reports/desktop-filesystem.md), E3–E5 and E8–E16 | APIs/abstractions vary in ergonomics; Watchman is more robust but adds a daemon; none eliminates snapshots and rescans | Affects updates, CPU, installation, and recovery | **Invariant settled; implementation open** |
| Source of truth for changes | events; snapshot/rescan | FSEvents may coalesce, drop, or request `MustScanSubDirs` ([desktop](reports/desktop-filesystem.md), E3–E4) | A snapshot may be expensive; events alone are incomplete | Affects tree correctness and invalidation | **Snapshot/rescan conditionally required** |
| Dependency model | open file only; adapter manifest; broad rescan | [desktop](reports/desktop-filesystem.md), sections 9–10; [Markdown](reports/markdown-html.md), C12–C14; [LaTeX](reports/latex-preview.md), C7–C11 | A manifest takes work, but watching only the open file misses images/includes/bibliography | Affects correct renders and scan cost | **Manifest recommended; details open** |
| Render coordination | serial queue; limited concurrency; cancellation; generation-based discard | [desktop](reports/desktop-filesystem.md), sections 9–10; [LaTeX](reports/latex-preview.md), section 12 | Serialization protects outputs; concurrency may reduce wait but increases contention and risk | Affects UX, CPU, and preview integrity | **Generation and rejection of old results settled; limits open** |
| Markdown foundation | `remark`/`unified`; `cmark-gfm`/`swift-markdown`; `markdown-it`; `micromark`; `markdown-rs` | [Markdown](reports/markdown-html.md), sections 5–7 and 10 | AST/extensibility versus runtime/dependencies; custom renderer versus less integration work | Affects dialect, links, mathematics, sanitization, and maintenance | **Open; depends on runtime and corpus** |
| Markdown mathematics | KaTeX; MathJax; no initial math; custom renderer | [Markdown](reports/markdown-html.md), C9–C10 and section 7 | KaTeX is static/predictable HTML but does not support `\\label`, `\\ref`, `\\eqref`; MathJax covers more but is heavier/asynchronous | Affects fidelity and security pipeline | **Open; real fixture required** |
| LaTeX output | PDF; HTML; PDF+HTML hybrid | [LaTeX](reports/latex-preview.md), sections 7, 15–16 | PDF maximizes fidelity; HTML favors structure/search/accessibility; hybrid duplicates pipelines and failure modes | Affects the meaning of “preview,” viewer, and cost | **Bernardo's usage decision** |
| LaTeX engine/distribution | TeX Live/MacTeX + `latexmk`; MiKTeX; Tectonic; BasicTeX | [LaTeX](reports/latex-preview.md), sections 6, 8, 16; [security](reports/preview-security-distribution.md), sections 6–10 | Traditional TeX is broader; Tectonic simplifies installation but differs in engine/cache/Biber; MiKTeX may install over the network | Affects compatibility, offline use, size, and support | **Open; real corpus and distribution tests required** |
| LaTeX root | manual choice; heuristic discovery; persisted configuration | [LaTeX](reports/latex-preview.md), section 9; overview, “LaTeX” | A standalone chapter usually does not compile; heuristics may find zero or multiple candidates | Affects opening UX and dependencies | **Prompting for a choice is planned; algorithm open** |
| LaTeX wrapper | `latexmk`; Tectonic watch; app watcher/coordinator | [LaTeX](reports/latex-preview.md), C6–C8 and sections 12–13 | External watch does not resolve roots, debounce, generations, cancellation, or concurrency | Affects simplicity and diagnostics | **App remains responsible; tool open** |
| HTML surface | static `WKWebView`; app-owned scheme; native text; Quick Look | [security](reports/preview-security-distribution.md), sections 6–7; [Markdown](reports/markdown-html.md), section 7 | `loadFileURL` is simple; an app-owned scheme offers more control but requires logic; Quick Look offers less control | Affects security, resources, and CSS | **`WKWebView` conditionally favored; configuration open** |
| PDF surface | PDFKit; Quick Look; external Preview | [LaTeX](reports/latex-preview.md), C16; [security](reports/preview-security-distribution.md), C9–C11 | PDFKit offers control and search; Quick Look is simple; external Preview breaks the flow | Affects reading, actions, and isolation | **PDFKit is a conditional recommendation; not approved** |
| Local links and resources | allow within root; deny outside; ask for additional authorization | [Markdown](reports/markdown-html.md), C12 and section 7; [security](reports/preview-security-distribution.md), sections 7.2–7.3 | Allowing increases compatibility; denying reduces exposure; extra authorization complicates UX/permissions | Affects images, links, and security | **Product policy open; canonical root is a guardrail** |
| External links | block; open after explicit action; load in preview | [security](reports/preview-security-distribution.md), section 7.3 | Blocking maximizes containment; external browser preserves utility but moves risk; loading in WebView increases exposure | Affects reading and network access | **Conditional recommendation: do not load automatically** |
| LaTeX security | shell escape off; restricted allowlist; full escape | [LaTeX](reports/latex-preview.md), C18; [security](reports/preview-security-distribution.md), C16–C17 | Off breaks dependent documents; restricted lowers risk but does not make input trusted; full escape conflicts with an initial defensive posture | Affects compatibility and threat exposure | **Off by default; exceptions require a decision/test** |
| Compilation workspace | source directory; isolated temp; helper/XPC | [LaTeX](reports/latex-preview.md), sections 11 and 14; [security](reports/preview-security-distribution.md), sections 7.5 and 10 | Source directory is simple but exposes sources; temp reduces harm; XPC improves separation but adds complexity | Affects security, cleanup, and sandboxing | **Temp outside root is a guardrail; degree of isolation open** |
| Distribution | local prototype with external TeX; app outside App Store; sandboxed App Store app with bundled helpers | [security](reports/preview-security-distribution.md), C18–C21 and section 10 | External TeX reduces bundle size but conflicts with sandboxing; bundling controls versions but increases size, signing, licensing, and maintenance | May redefine the entire LaTeX architecture | **Bernardo's distribution decision** |
| Offline use | bundled dependencies/full cache; runtime installation; optional network | [Markdown](reports/markdown-html.md), scope and C6–C7; [LaTeX](reports/latex-preview.md), C3–C5; [security](reports/preview-security-distribution.md), C18 | Full cache is predictable; runtime installation is convenient but needs network; Tectonic `--only-cached` fails with an incomplete cache | Affects first launch and failures | **Offline use is a principle; composition open** |
| Licensing | use external tools; redistribute a TeX subset; redistribute JS/Rust stack | Ledgers in all four reports, especially [LaTeX](reports/latex-preview.md), sections 14 and 21, and [security](reports/preview-security-distribution.md), E18 | External tools reduce the app's inventory; bundled tools require inventory and signing each component | Affects distribution and maintenance | **Legal/packaging review pending** |

## 5. Decisions that depend on Bernardo's preferences and personal use

The questions below are deliberately simple. Each option has a concrete consequence; recommendations are conditional, not decisions made in this synthesis.

### 5.1 What does “LaTeX preview” mean for the primary use case?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **Check the thesis's visual layout** — PDF | If the daily question is “did the thesis compile and does it look right?”, start with PDF using the thesis-compatible engine | Greater fidelity; less semantic HTML; requires PDFKit and a policy for PDF actions |
| **Navigate/search the structure** — HTML | If headings, links, search, and accessibility matter more than visual equivalence, test TeX4ht/make4ht, lwarp, and/or LaTeXML | More transformation and incompatibility; visual equivalence is not guaranteed |
| **Need both** — PDF + HTML | Only if both are real needs from the outset and there is capacity for two pipelines | Duplicates compilation, diagnostics, caches, validation, and security surfaces |

**Bernardo's decision:** which of these tasks justifies the first version?

### 5.2 Is the first goal a local personal prototype or a distributable app?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **Personal prototype on the current Mac** | Validate early with tools already installed, while recording accepted risks | May depend on external MacTeX/BasicTeX; does not prove sandbox compatibility or general distribution |
| **App outside the App Store, signed/notarized** | Evaluate after a prototype, keeping executables and licenses under control | More operational freedom, but every executable and helper needs signing/notarization and inventory |
| **Mac App Store/App Sandbox** | Treat distribution as a requirement from the first compilation test | External TeX is not straightforward; may require bundled helpers/XPC, bookmarks, and substantial distribution work |

**Bernardo's decision:** should distribution cost constrain the MVP or can it wait?

### 5.3 Which priority should determine the desktop shell?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **SwiftUI/AppKit** | If macOS integration, bookmarks, and Mac app behavior are priorities | Less bridging for permissions/processes; UI and infrastructure stay in Swift |
| **Tauri 2** | If web UI and a Rust core matter and there is capacity for a custom macOS bridge | Natural WebView and potentially smaller bundle; persistent scopes on macOS need validation/implementation |
| **Electron** | If TypeScript/Node and web tools substantially reduce development risk | Strong IPC and tooling; larger bundle and more frequent Chromium/Node updates |
| **Flutter** | If future cross-platform support outweighs the native WebKit preview option | Compiled UI; no specific benefit was demonstrated for this macOS-first MVP |

**Bernardo's decision:** which cost is most acceptable: Swift/native, Rust/bridge, Electron bundle, or Flutter?

### 5.4 Which Markdown dialect and academic features are actually needed?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **CommonMark + GFM + common mathematics** | If chapters use structure, tables, footnotes, and formulas without advanced LaTeX semantics | Allows a more limited pipeline to start; does not generally provide bibliography, includes, or `\\label`/`\\ref` |
| **Markdown with an AST and custom academic extensions** | If cross-chapter links, references, composition, and diagnostics are part of the real workflow | Favors `remark`/`unified` or an equivalent AST; increases maintenance and custom contracts |
| **Markdown as an approximation of LaTeX** | If documents depend on mathematical/bibliographic references and LaTeX-like composition | May make LaTeX/PDF the primary path; KaTeX probably will not cover every case |

**Bernardo's decision:** which three real Markdown files should be supported first?

### 5.5 Should dependencies outside the root folder work?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **Deny access outside the root** | If containment and predictability are priorities | Simple, safe policy; some existing projects will no longer compile/render |
| **Ask for additional authorization** | If there are legitimate dependencies outside the root and Bernardo accepts an explicit choice | Preserves control; requires multiple scopes/bookmarks, an additional watcher, and permission UX |
| **Allow automatically** | Only if convenience clearly outweighs the threat | Greater compatibility, but conflicts with the authorized-root posture and increases accidental exfiltration/writes |

**Bernardo's decision:** are projects self-contained, or is it normal for them to share resources outside the open folder?

### 5.6 How should external links work?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **Block** | If the preview must remain offline and strictly local | Greater containment; web links are no longer useful |
| **Open externally after an explicit action** | If bibliographic/web links are useful but must not load in the WebView | Preserves utility with a visible choice; moves network risk to the browser |
| **Load in the preview** | Only if interactivity/network access is a real requirement | Requires a much broader CSP/network policy and increases attack surface |

**Bernardo's decision:** are external links part of the reading task or only a convenience?

### 5.7 How compatible must LaTeX compilation be?

| Option | Conditional recommendation | Consequence |
|---|---|---|
| **Compatibility with the thesis's current environment** | If the thesis already compiles with a known engine/distribution | Better chance of fidelity; external dependencies and local configuration become central |
| **Controlled/portable environment** | If reproducibility, offline use, and distribution matter more | Consider Tectonic or bundled TeX, but validate the engine, Biber, fonts, paths, and licenses |
| **Broad compatibility with arbitrary TeX projects** | Only if higher costs are acceptable | Approaches full TeX Live/MacTeX; increases bundle size, execution surface, and support needs |

**Bernardo's decision:** does the app need to open his thesis, or be a general tool for LaTeX projects?

## 6. Conflicts and incompatibilities among reports

### 6.1 Flexible HTML versus security and simplicity

The Markdown report favors `remark`/`unified` when JavaScript is acceptable, due to its AST, link transformations, mathematics, and sanitization. The security report favors `WKWebView` with static HTML and JavaScript disabled. These positions are not necessarily contradictory: JavaScript can run in the local prerendering process and be excluded from content delivered to the WebView. Packaging/runtime choices and a compatibility pipeline still need validation.

### 6.2 Native `cmark-gfm` versus a rich `remark` AST

`cmark-gfm` or `swift-markdown` reduce dependencies and favor native integration, but require a custom renderer for links, anchors, mathematics, and resource policies. `remark`/`unified` reduces this transformation work, but increases the package surface, the importance of plugin order, and the need for pinning. The report does not measure actual cost on Bernardo's corpus; the choice depends on the shell, acceptable runtime, and required extensions.

### 6.3 Faithful PDF versus navigable HTML

The LaTeX report does not treat PDF and HTML as equivalent. PDF better preserves the original engine's output; HTML offers advantages in structure, search, and accessibility. Choosing HTML because it is easier to embed in a WebView may fail the primary task of checking a thesis. Choosing PDF may sacrifice semantics and navigation flexibility. This is a usage decision, not a purely technical conclusion.

### 6.4 External TeX versus App Sandbox/Mac App Store

The LaTeX report recommends first validating a traditional pipeline and allows Tectonic as an operational alternative. The security report warns that permission to access a user-selected file does not simply authorize running external programs outside the app, container, or app group in a sandboxed app. Thus, “use the installed MacTeX” may be acceptable for a personal prototype but should not automatically become the architecture for sandboxed distribution.

### 6.5 Tool watch mode versus the app watcher

`latexmk` and Tectonic have watch modes; Tauri, Chokidar, and `notify` provide watch abstractions. The reports do not establish that these replace the `bp-viewer` coordinator: root discovery, dependencies, debounce, snapshot/rescan, generations, cancellation, and protection against stale results are still needed.

### 6.6 Simple Tectonic versus comprehensive TeX Live

Tectonic reduces installation effort and can use a cache, but relies primarily on XeTeX, may need compatible external Biber, and may differ from traditional paths/configuration. TeX Live/MacTeX is more comprehensive but large and difficult to package/constrain. Release 0.17.0 fixed a specific macOS ARM64 issue reported against 0.16.x; this calls for testing specific versions, not concluding that Tectonic is generally unsuitable or safe.

### 6.7 Sanitization, CSP, and disabled JavaScript are not substitutes

The security report records distinct limitations: DOMPurify is not a complete CSS sanitizer or HTTP leak blocker; CSP is defense in depth; disabling JavaScript does not prevent all passive requests; a separate WebKit process reduces impact but does not eliminate bugs. The policy needs to combine these layers.

### 6.8 Observed versions and integration

The Markdown report found version mismatches between `rehype-katex`/KaTeX and `rehype-mathjax`/MathJax. This does not prove final incompatibility, but it prevents assuming that “latest” works. The desktop and LaTeX reports also contain snapshots of different versions and local installations. Treat all of these as dated observations, with pinning and local testing before making a decision.

## 7. Proposed validation/prototyping order, prioritized by risk

This order prioritizes risks that could invalidate the entire architecture, not implementation convenience. It is a work proposal, not a product decision.

### 0. Define the validation scenario

Before writing code, Bernardo should temporarily choose: a real thesis/corpus or representative fixtures; minimum macOS version; personal prototype or sandboxed distribution; and whether the LaTeX goal is PDF or HTML. Without these choices, results have no shared criteria.

### 1. Validate the real LaTeX pipeline — highest risk

Using copies of the documents and outputs in a temporary directory:

- identify the root, `\\input`/`\\include`, images, `.bib`, `.sty`, `.cls`, fonts, and tools;
- test the thesis's current engine with the existing TeX Live/MacTeX installation and `latexmk` if available;
- test classic bibliography and BibLaTeX/Biber if used;
- test paths with spaces/Unicode, errors, missing packages/images, and interactive prompts;
- test recompilation after changes and confirm nothing is written to the source folder;
- test with shell escape disabled and record exactly what stops working.

**Exit criterion:** the pipeline compiles the priority corpus with manageable diagnostics, or it is documented that the thesis requires a capability that is not yet supported.

### 2. Validate the distribution/compiler conflict

Separately test local development execution, a signed/notarized app if relevant, and sandboxing. Check root access, passing bookmarks to a helper, running external compilers, sandbox inheritance, XPC/helper behavior, signing, and dependencies.

**Exit criterion:** it is clear whether the MVP accepts external TeX as a personal-use risk or needs bundled executables. If the Mac App Store is a requirement, this step cannot be deferred.

### 3. Validate the filesystem, dependencies, and concurrency

Build contract fixtures independently of the final UI:

- initial snapshot with the watcher already active;
- incremental write and atomic rename;
- bursts of changes and coalesced/dropped events;
- changes/removals of images, includes, and bibliography;
- moved root, lost permissions, and stale bookmark;
- slow render that finishes after a newer generation;
- cancellation and process tree behavior.

**Exit criterion:** snapshots/rescans, dependency manifest, and generation-based rejection always produce the correct state in the tested scenarios.

### 4. Validate HTML and PDF containment

Before accepting a specific parser, test `WKWebView`/PDFKit on the minimum macOS version with scripts, handlers, `iframe`, SVG, dangerous URLs, external images, `..`, symlinks, absolute paths, redirects, downloads, attachments, and PDF actions.

**Exit criterion:** each attempt is blocked, explicitly allowed, or diagnosed according to the chosen policy; do not assume the API enforces the policy by itself.

### 5. Compare Markdown pipelines against the real corpus

Use the fixture suggested by the Markdown report: headings, tables, footnotes, code, images, links, anchors, common mathematics, `\\label`/`\\ref`/`\\eqref`, macros, and errors. Compare `remark`/`unified`, `cmark-gfm`/`swift-markdown`, `markdown-it`, `micromark`, and/or `markdown-rs` only where they are candidates for the chosen shell.

**Exit criterion:** the supported dialect, limitations, and math renderer are documented with input/output examples and diagnostics.

### 6. Validate the shell, permissions, and UX restoration

Only after the preceding risks have been addressed, compare shells using the same session: open a folder, lazy tree, tabs, restart, bookmark, selection, WebView/PDF, error messages, and updates.

**Exit criterion:** the shell decision is based on the workflow and local tests, not bundle size or abstract preference.

### 7. Validate LaTeX-to-HTML alternatives only if HTML is chosen

Compare TeX4ht/make4ht, lwarp, and LaTeXML with the thesis/fixtures, including bibliography, cross-references, images, MathML, CSS, splitting, and diagnostics. Do not treat lists of supported packages as proof of general fidelity.

### 8. Validate packaging and maintenance

Pin versions; repeat offline builds; check `rehype-katex`/KaTeX and `rehype-mathjax`/MathJax compatibility; inventory licenses; test Apple Silicon, signing, notarization, and actual size. Only then turn a conditional recommendation into an approved technical decision.

## 8. Open questions for continued product discussion

1. Is the primary use case Bernardo's single thesis or several heterogeneous projects?
2. Must the first version support LaTeX that already depends on `biber`, TikZ/PGFPlots, system fonts, shell escape, or external tools?
3. What is the minimum acceptable macOS version?
4. Should the root folder be self-contained by contract?
5. Should users be able to grant access to dependencies outside the root, and should that access persist?
6. Should a selected LaTeX chapter always compile the root, or should there be an option to compile the selected file alone when possible?
7. How should the app choose among zero, one, or several candidate roots, and where should it persist the choice?
8. Should the last valid preview remain available after an error? How should it be marked and for how long?
9. What does “up to date” mean when an image or include changes during compilation?
10. What is the symlink policy: ignore, show without following, or follow within an allowlist?
11. Should `.md#heading` links open/focus tabs, and how should links to missing files be handled?
12. Is MathJax needed for the actual math references, or does KaTeX cover the priority corpus?
13. Are footnotes enough, or does Bernardo need bibliographies/semantic citations in Markdown?
14. Should document-provided CSS be allowed, restricted, or removed?
15. Should external links be blocked or opened in the browser after confirmation?
16. Does the MVP need notarization/distribution or only run on the development Mac?
17. Must the app work without any network after installation, including TeX packages/fonts?
18. What update time is acceptable for a small, medium, and large chapter?
19. What should happen if compilation exceeds its timeout or consumes excessive resources?
20. Does the future editor change any viewer contract now, beyond the planned architectural separation?

## 9. Claims that still require local validation

The following points appear in the reports as gaps or proposed tests. They are not facts already confirmed for `bp-viewer`.

### Corpus and rendering

- Which Markdown parser correctly renders the real files, including raw HTML, tables, footnotes, images, anchors, Unicode, and code blocks.
- Whether real documents need includes, bibliography, semantic references, or conventions beyond CommonMark/GFM.
- Whether KaTeX covers the mathematics in use, especially `\\label`, `\\ref`, `\\eqref`, environments, macros, and errors.
- Whether MathJax works with the resolved version at an acceptable speed and complexity.
- Concrete compatibility among `remark`/`rehype`, KaTeX/MathJax, sanitization, and the generated HTML.
- TeX4ht/make4ht, lwarp, and LaTeXML fidelity for the real thesis, if LaTeX HTML is considered.

### LaTeX and processes

- Which root should be discovered for each project, including zero or multiple candidates.
- Whether TeX Live/MacTeX, BasicTeX, MiKTeX, or Tectonic compile the corpus with the expected engine.
- Compatibility with BibTeX, BibLaTeX, Biber, MakeIndex/Xindy, TikZ/PGFPlots, fonts, and converters.
- Effects of disabled/restricted shell escape and the need for helper tools.
- Offline behavior with a complete/incomplete Tectonic cache and no automatic installation.
- Whether the process tree closes on cancellation and leaves no locks/artifacts behind.
- Time, memory, log size, and artifact size for small, medium, and large documents.

### Filesystem and permissions

- Cost of snapshots/rescans and lazy loading in trees similar to the project.
- Actual semantics of the chosen backend for atomic rename, chunked writes, bursts, coalescing, and dropped events.
- Change detection for images, includes, `.bib`, `.sty`, `.cls`, and dependencies outside the root.
- Persistence, stale state, and recovery of security-scoped bookmarks in signed/sandboxed builds.
- Access and reopening after a root rename, lost permission, ACL/TCC, or unreadable subfolder.
- Policy for symlinks, cycles, absolute paths, `..`, network/SMB volumes, and case-insensitive filesystems.
- Actual memory use, startup, and responsiveness of shells; the reports do not provide sufficient comparative benchmarks.

### Preview and security

- Behavior of `loadFileURL`, `loadHTMLString(baseURL:)`, and any app-owned scheme.
- Actual effectiveness of CSP/meta CSP in the chosen loading mode.
- Passive network requests without an entitlement and behavior of images/CSS/URLs.
- Actual execution of scripts, handlers, redirects, downloads, new windows, and dangerous schemes.
- PDFKit behavior for URLs, `file:`, Launch, remote go-to, attachments, forms, PDF JavaScript, corrupted or very large PDFs.
- Sandbox inheritance and passing bookmarks/permissions to a helper/XPC process.
- Signing/notarization of bundled executables and license matrix.

## 10. Source map

The four original reports are the sources for this synthesis and contain links to primary sources, ledgers, observed versions, research logs, refutations, and reasons for stopping. Primary sources were not revisited for this task.

- [Report: Markdown → HTML](reports/markdown-html.md) — parser, AST, GFM, mathematics, links, sanitization, and suggested local tests.
- [Report: LaTeX → preview](reports/latex-preview.md) — PDF/HTML, engines, `latexmk`, Tectonic, multi-file projects, bibliography, artifacts, security, and local tests.
- [Report: desktop and filesystem](reports/desktop-filesystem.md) — shells, permissions, FSEvents/watchers, contracts, queues, processes, and filesystem tests.
- [Report: preview, security, and distribution](reports/preview-security-distribution.md) — WebKit, PDFKit, sandboxing, bookmarks, helpers/XPC, shell escape, distribution, and threat model.

**Provenance note:** claim references in this synthesis point to sections of the original reports. Consult those documents for the date, version, and strength of evidence; do not infer them from this synthesis alone.

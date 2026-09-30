# Research report: preview, security, and distribution

Web access date: 2026-09-09  
Repository context: [research archive](../CONTEXT.md), [preview brief](../preview-security-distribution.md), and [current state](../../../current-state.md)
Repository state during research: no changes.

## 1. Executive summary

The combination with the best balance of control, native integration, and bounded risk is:

- Markdown: `WKWebView` for static HTML, with content JavaScript disabled, allowlist sanitization, a CSP policy, resource loading limited to the authorized folder, and intercepted navigation.
- LaTeX: PDFKit to display the generated PDF, with actions and links handled explicitly; Quick Look is a simple alternative but offers less control.
- Files: App Sandbox, read-only access to the folder selected by the user, and security-scoped bookmarks to reopen the project.
- Compilation: a temporary directory outside the project folder, time/output/resource limits, shell escape disabled or restricted, and no automatic package installation.

The main incompatibility remains between:

1. using an external LaTeX installation such as MacTeX;
2. keeping the application sandboxed, especially for Mac App Store distribution.

Apple documentation indicates that permissions for user-selected files do not authorize running programs located outside the app, container, or app group. For sandboxed distribution, the most controllable technical alternative is to bundle signed helper executables, possibly behind XPC. This substantially increases size, maintenance, and licensing complexity.

No option should be considered absolutely “safe.” The recommendations below reduce the impact of compromised local content but do not eliminate vulnerabilities in WebKit, PDFKit, parsers, compilers, or libraries.

## 2. Question and supported decision

The research examined how to:

- display local HTML and PDFs;
- limit JavaScript, navigation, and file access;
- process potentially hostile Markdown, images, PDFs, and LaTeX projects;
- use App Sandbox, permissions, and security-scoped bookmarks;
- run helper compilers;
- distribute and update the application inside or outside the Mac App Store.

The research supports a static preview architecture with defense in depth. It does not yet support a final decision on the LaTeX execution/bundling strategy.

## 3. Scope and assumptions

### Included

- local content modified by external processes, including LLMs;
- deliberately malicious content inside the opened folder;
- attempts to access files outside the authorized folder;
- HTML/JavaScript, images, SVG, PDF, links, and LaTeX artifacts;
- compromise of the preview process or compiler;
- personal use on macOS and possible future distribution.

### Excluded

- complete threat model for public distribution;
- decision on the Markdown parser or LaTeX compiler;
- implementation;
- comparison with other operating systems;
- authentication, cloud services, or collaboration;
- protection against an already compromised macOS system or user account.

### Threat model

Assumptions:

- the user may open a folder containing hostile files;
- content may try to execute code, read files, make network requests, or consume resources;
- the app runs under the user's identity;
- the app is not intended to have global access to the computer;
- the user still controls explicit actions such as selecting a folder or opening an external link.

App Sandbox, notarization, and sanitization are not assumed to make a file trustworthy.

## 4. Evaluation criteria

- containment of hostile content;
- file access control;
- network and navigation control;
- preview quality;
- isolation and recovery after failures;
- offline operation;
- dependencies and updates;
- App Sandbox compatibility;
- operational complexity;
- licensing and distribution;
- predictability when files change externally.

## 5. Claim matrix

| Claim | Importance | Status | Evidence | Limitations |
|---|---:|---|---|---|
| C1. `WKWebView` supports HTML, CSS, JavaScript, in-memory HTML, and local files. | High | Fact | E1 | Does not establish that local content is safe. |
| C2. `loadFileURL` can limit reading to a specified file or directory. | High | Fact | E2 | The specified area remains a read capability; it is not a complete path policy. |
| C3. Content JavaScript is enabled by default but can be disabled for navigation. | High | Fact | E3 | Disabling JavaScript does not prevent every passive request or renderer vulnerability. |
| C4. WebKit renders content in processes separate from the app. | High | Fact | E4 | Process isolation reduces impact but does not replace a sandbox or eliminate WebKit bugs. |
| C5. `WKNavigationDelegate` can allow or reject navigations. | High | Fact | E5 | The policy must cover redirects, new windows, downloads, and non-HTTP schemes. |
| C6. `WKWebsiteDataStore.nonPersistent` avoids persisting website data to disk. | Medium | Fact | E6 | It does not by itself control network requests or file access. |
| C7. DOMPurify uses an allowlist policy, but does not sanitize CSS or prevent HTTP leaks by itself. | High | Fact | E7 | The exact version, configuration, and sink must be pinned and tested. |
| C8. Current DOMPurify documentation records recent vulnerabilities and configuration risks. | High | Fact | E8 | The existence of a library does not prove that an integration is safe. |
| C9. PDFKit displays PDFs and supports selection, navigation, and text copying. | Medium | Fact | E9 | PDFKit remains a complex parser for untrusted files. |
| C10. PDFs can contain annotations/actions, including URL, URI, Launch, and remote go-to destinations. | High | Fact | E10 | The documentation does not prove exactly which actions `PDFView` performs automatically in each macOS version. |
| C11. Quick Look supports PDFs and text files, but its supported format list may change between versions. | Medium | Fact | E11 | It offers less policy control than a dedicated surface. |
| C12. App Sandbox limits resources through entitlements and can grant recursive access to the selected folder. | High | Fact | E12 | POSIX ACLs, TCC, and external state may still block access. |
| C13. Security-scoped bookmarks can persist resource access between launches and require explicit scope management. | High | Fact | E12 | A bookmark may become stale or invalid. |
| C14. A sandboxed helper does not automatically receive PowerBox permissions acquired after launch; bookmarks/data must be passed to it. | High | Fact | E13 | Exact behavior depends on the helper type and distribution model. |
| C15. Apple prefers XPC for privilege separation over a simple child process. | High | Fact | E13, E14 | XPC does not make the compiler trustworthy; it only creates another boundary. |
| C16. TeX Live treats shell escape as a risk; `-shell-escape` permits arbitrary commands, while restricted mode limits allowed commands. | Very high | Fact | E15 | Restricted mode still permits file reads/writes and approved commands. |
| C17. TeX Live recommends extra care with contributed programs and using a subdirectory/chroot for untrusted input. | Very high | Fact | E15 | This does not guarantee isolation on macOS. |
| C18. MacTeX 2026 requires macOS 11+, is universal for Intel/Arm, and the full package is about 6.4 GB; BasicTeX is about 134 MB. | High | Fact | E16 | The size may not include every dependency required by a thesis. |
| C19. Access to user-selected files does not by itself authorize running programs outside the app, container, or app group. | Very high | Fact | E12 | Compatibility with each distribution model requires local testing and App Store validation. |
| C20. Distribution outside the App Store requires Developer ID, Hardened Runtime, a secure timestamp, and signatures on distributed executables. | High | Fact | E17 | Notarization is not App Review or an audit of content opened by the app. |
| C21. TeX Live contains components with individual licenses, although the distribution follows free-software principles. | Medium | Fact | E18 | A complete legal inventory is still needed if components are bundled. |
| C22. Recommending static preview with JS disabled, sanitization, CSP, path policy, and sandboxing is a defense-in-depth inference. | Very high | Inference | C1–C21 | It has not been validated with a prototype on the target macOS version. |

## 6. Alternatives investigated

### 6.1 Markdown/HTML

| Option | Advantages | Risks/limitations |
|---|---|---|
| `WKWebView` with static HTML | Good visual fidelity; native API; supports CSS, pre-rendered math, and images | WebKit surface; JavaScript and navigation need an explicit policy |
| `WKWebView` with active JavaScript | Enables client-side libraries and interaction | Increases XSS, exfiltration, CPU use, and bridge complexity |
| `WKWebView` with `loadFileURL` | Simple local resource; Apple allows limiting `readAccessURL` | Paths, symlinks, `..`, absolute URLs, and schemes still require validation |
| `WKWebView` with an app-owned scheme | Allows validation of each resource request and MIME type | Adds native loading code; an error can create a new unsafe boundary |
| AppKit/native text | Smaller web surface and fewer dependencies | Lower fidelity for HTML, CSS, tables, and math |
| Quick Look | Fast integration for supported files | Variable format list and less control over navigation and content |
| HTML with sanitization alone | Reduces known XSS | Insufficient against CSS, external requests, later sinks, and reprocessing |

### 6.2 PDF

| Option | Advantages | Risks/limitations |
|---|---|---|
| PDFKit | Native, with control over display and access to annotations/actions | Complex parser; link/action policies need validation |
| Quick Look | Simple and integrated into the system | Less control over behavior and exact compatibility |
| Open in external Preview | Isolates the app from the Preview process | Transfers risk to another app and interrupts the intended workflow |

### 6.3 LaTeX

| Option | Advantages | Risks/limitations |
|---|---|---|
| Option | Advantages | Risks/limitations |
|---|---|---|
| Existing MacTeX/TeX Live installation | Smaller app package and greater compatibility with existing environments | External dependency; sandbox conflict; variable versions and paths |
| External BasicTeX | Much smaller than full MacTeX | Missing packages; extra installation/configuration |
| Bundled executables | Controlled versions; more predictable distribution | Size, signing, updates, licenses, and possible dependencies |
| Bundled helper/XPC | Better process and permission separation | IPC complexity, bookmark passing, and signing every executable |
| Simple child process | Easier to integrate | Apple documents less privilege separation than with XPC |
| Compilation without isolation | Direct integration | Unsuitable for potentially hostile content; may write to the project or execute commands |

## 7. Evidence-based comparison

### 7.1 Markdown with HTML or embedded JavaScript

`WKWebView` has content JavaScript enabled by default. Apple documents that `allowsContentJavaScript = false` blocks inline scripts, referenced JavaScript files, and `javascript:` URLs. This substantially reduces the C1 attack surface, but should not be treated as sanitization.

The conditional recommendation is:

1. convert Markdown to HTML;
2. sanitize the HTML before passing it to the WebView;
3. use a small allowlist;
4. remove scripts, `on*` handlers, `iframe`, `object`, `embed`, forms, `base`, `link`, `style`, and SVG unless a validated need exists;
5. disable content JavaScript;
6. apply CSP, for example with `script-src 'none'`, `object-src 'none'`, and `connect-src 'none'`;
7. do not expose an unnecessary native bridge to JavaScript;
8. intercept all navigation.

Current DOMPurify documentation states that it does not sanitize CSS or prevent passive HTTP requests. It also documents recent bypasses and fixes. Therefore, pin the version for each build, monitor it, and subject it to regression tests.

### 7.2 Images and files outside the folder

A `src="../..."` or an absolute URL should not be interpreted as authorization to escape the opened folder.

Two approaches are plausible:

- `loadFileURL` with `readAccessURL` set to exactly the selected folder;
- an app-owned resource loader that resolves each path, verifies it remains within the canonical root, and only then returns the content.

The second offers greater control over paths, MIME types, symlinks, and extensions, but requires more custom logic. The first is simpler and directly documented by Apple.

The app should not automatically follow:

- symlinks that escape the root;
- absolute paths;
- `..` components that leave the root;
- `file:`, `javascript:`, `data:`, `blob:`, or unauthorized custom-scheme URLs.

The need for references deliberately outside the project should remain an open product decision, not an accidental consequence of the renderer.

### 7.3 Links and navigation

`WKNavigationDelegate` can allow or cancel navigation before loading content. A plausible minimum policy would be:

- internal links: only to permitted files within the root;
- external links: do not load inside the preview; open only after an explicit user action;
- externally permitted schemes: initially only `https` and, if needed, `http`;
- block `file`, `javascript`, `data`, `blob`, `ftp`, and custom schemes;
- block new windows, automatic downloads, and unexpected redirects.

Explicitly opening a link in the browser is not “safe”: it only moves responsibility to another application, which may have access to the user's cookies, network, and credentials.

### 7.4 PDF

PDFKit offers suitable reading capabilities: pages, zoom, selection, search/copy, and navigation. However, the PDF model includes annotations and actions. Apple documents URL/URI, Launch, remote go-to, and other action types.

Therefore, the app should not assume that “PDF is just a drawing.” Test the following on the chosen minimum macOS version:

- clicks on HTTP/HTTPS links;
- `file:` links;
- Launch actions;
- remote go-to;
- attachments;
- forms and PDF-specific JavaScript;
- large or corrupted PDFs, or PDFs with unusually compressed images.

The conditional preference is PDFKit as the primary surface, with external actions blocked or requiring explicit confirmation. Quick Look may serve as a fallback, but should not be considered equivalent in control.

### 7.5 LaTeX compilation

This is the most important risk in the brief.

TeX Live documents that:

- `-shell-escape` allows arbitrary commands to run;
- restricted mode limits execution to a list of commands;
- untrusted input should be processed with caution;
- contributed programs may not be as robust as core programs;
- isolated subdirectories or chroot may improve security.

Recommended implications:

- never compile directly inside the project folder;
- create a temporary workspace;
- copy only the required inputs;
- produce PDFs, logs, and auxiliary files only in the temporary workspace/container;
- do not grant write permissions to the original folder;
- disable shell escape by default;
- allow restricted shell escape only when a required capability justifies it;
- do not install packages automatically;
- pin `PATH`, environment, working directory, and output location;
- set a timeout, log limit, artifact-size limit, and process termination policy;
- treat source files, `.sty`, `.bst`, `.bib`, scripts, SVG, EPS, and converters as potentially active inputs;
- clear or replace the workspace after compilation.

Apple documentation introduces an additional difficulty: a sandboxed app cannot rely solely on user-selected file permission to run programs located outside the app, container, or app group. This means an external MacTeX installation is not a simple, universal solution for sandboxed distribution.

## 8. Evidence

### E1–E6: WebKit

- **E1 — WKWebView.** Apple documents support for HTML, CSS, JavaScript, in-memory HTML content, and local files: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview).
- **E2 — local read boundary.** `loadFileURL(_:allowingReadAccessTo:)` accepts a file or directory to read; using the file itself limits reading to that file: [loadFileURL](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29).
- **E3 — JavaScript.** Apple documents that `allowsContentJavaScript` is true by default and false blocks inline scripts, JavaScript references, and `javascript:` URLs: [allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript).
- **E4 — content process.** WebKit renders content in processes separate from the app, though processes may be shared according to internal limits: [WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool).
- **E5 — navigation.** `WKNavigationDelegate` provides policies to allow or cancel navigation: [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).
- **E6 — persistence.** `WKWebsiteDataStore` has a non-persistent variant that keeps data in memory: [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore).

These sources establish API capabilities; they do not establish that a specific configuration withstands all malicious content.

### E7–E8: Sanitization and CSP

- **E7 — DOMPurify.** Security documentation describes the allowlist model, DOM sanitization, Trusted Types support, and limits regarding CSS and HTTP requests: [DOMPurify Security Goals & Threat Model](https://github.com/cure53/DOMPurify/wiki/Security-Goals-%26-Threat-Model).
- **E8 — maintenance and vulnerabilities.** The same documentation was current on 2026-09-09 and identified the current 3.4.x line, version 3.4.15, as well as recent advisories: [DOMPurify Security Advisories](https://github.com/cure53/DOMPurify/security/advisories).
- **E9 — CSP.** CSP defines restrictions for scripts, objects, frames, connections, and resources; the specification recommends avoiding `unsafe-inline` and `data:` when unnecessary: [Content Security Policy Level 3](https://www.w3.org/TR/CSP/).

CSP is defense in depth, not a replacement for sanitization or native navigation policy.

### E9–E11: PDF

- **E9 — PDFKit capabilities.** `PDFView` displays PDFs and supports selection, navigation, zoom, and text copying: [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview).
- **E10 — annotations/actions.** Apple documents that PDFs contain annotations and actions; `PDFAction` can represent URI/Launch through `PDFActionURL`: [PDFAnnotation](https://developer.apple.com/documentation/pdfkit/pdfannotation), [PDFAction type](https://developer.apple.com/documentation/pdfkit/pdfaction/type).
- **E11 — Quick Look.** Quick Look supports PDFs and text, but the list of supported types may change between system versions: [Quick Look](https://developer.apple.com/documentation/quicklook/).

The documentation confirms these surfaces and actions exist; it does not provide a security classification for arbitrary PDF files.

### E12–E14: App Sandbox, bookmarks, and helpers

- **E12 — sandbox and permissions.** Apple documents App Sandbox, Open Panels, read-only/read-write access to selected files, and recursive access when a folder is selected: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- **E13 — bookmarks and child processes.** Security-scoped bookmarks can persist access; dynamically acquired permissions are not automatically passed to helpers with sandbox inheritance: [Enabling App Sandbox Inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).
- **E14 — XPC.** Apple describes XPC as a mechanism for process separation and indicates that XPC is preferable for privilege separation: [Creating XPC services](https://developer.apple.com/documentation/xpc/creating-xpc-services), [Embedding a helper tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).

### E15–E16: TeX Live/MacTeX

- **E15 — shell escape and untrusted input.** TeX Live 2026 describes shell escapes, restricted mode, risks from contributed programs, and recommends using a subdirectory or chroot for untrusted content: [TeX Live Guide 2026](https://tug.org/texlive/doc/texlive-en/texlive-en.html).
- **E16 — versions and sizes.** TeX Live 2026 was released on 2026-03-01. MacTeX 2026 requires macOS 11 or later, supports Intel/Arm, and the full package is about 6.4 GB; BasicTeX is about 134 MB: [TeX Live](https://tug.org/texlive/), [MacTeX downloads](https://tug.org/mactex/mactex-download.html).

### E17–E18: Distribution and licensing

- **E17 — distribution outside the App Store.** For software distributed outside the App Store, Apple requires Developer ID, signed executables, Hardened Runtime, a secure timestamp, and notarization: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).
- **E18 — TeX dependencies.** TeX Live states that components have their own licenses and redistribution must comply with each component's terms: [TeX Live copying and redistribution](https://www.tug.org/texlive/copying.html), [About MacTeX](https://tug.org/mactex/aboutmactex.html).

## 9. Conflicts and counterarguments

### “A separate WKWebView process makes HTML safe”

Counterargument: a separate process reduces the impact of an exploit, but WebKit can still compromise that process. If it has access to local resources, the network, or a native bridge, exploitation may still matter.

### “Disabling JavaScript solves hostile HTML”

Counterargument: HTML can make passive requests through images, CSS, and other resources. DOMPurify explicitly states that it is not a CSS sanitizer and does not block all HTTP leaks.

### “Sanitizing with DOMPurify is enough”

Counterargument: the library offers no protection if called incorrectly, does not protect later sinks, does not cover CSS by default, and has version/configuration risks. Sanitization should be combined with CSP, disabled JavaScript, and path isolation.

### “PDF is only visual output”

Counterargument: a PDF can contain URL, Launch, and remote go-to annotations/actions, attachments, and forms. PDFKit's exact behavior should be tested on the target macOS version.

### “App Sandbox solves running external LaTeX”

Counterargument: Apple documentation indicates that user-selected file permissions do not authorize running programs outside the app, container, or app group. Do not assume an external MacTeX installation is compatible with a distributable sandboxed app.

### “Notarization validates app security”

Counterargument: notarization checks the distributed app, its signature, and issues detectable by the service. It does not validate local content the user will open or replace runtime controls.

### “TeX Live restricted shell escape makes compilation safe”

Counterargument: it reduces the ability to execute commands, but does not make macros, packages, auxiliary files, or converters trustworthy. It also does not automatically address file reads/writes or resource exhaustion.

## 10. Conditional recommendation

### High-confidence recommendation

For Markdown:

- `WKWebView`;
- treat content as untrusted;
- sanitize HTML with an allowlist;
- disable content JavaScript;
- use CSP as defense in depth;
- avoid unnecessary native bridges;
- limit resources to the authorized root;
- allow external navigation only after explicit action;
- use a non-persistent data store;
- omit the network entitlement if the MVP does not need network access.

For LaTeX:

- use PDFKit as the reading surface;
- handle PDF actions explicitly;
- do not automatically open paths or external applications;
- compile outside the source folder;
- impose process and output limits;
- disable or restrict shell escape.

### Decisive condition

If the future priority is App Sandbox and the Mac App Store, the LaTeX strategy should start with bundled, signed helper executables compatible with sandbox/XPC. The cost of bundling full TeX Live, or selecting a minimal distribution, should be assessed before finalizing that architecture.

If the priority is only a personal prototype on the user's Mac, depending on an external TeX installation may be acceptable, but it should be recorded as an accepted operational and security risk, not as a sandboxed or universally safe solution.

Confidence:

- WebKit/PDFKit APIs: high.
- App Sandbox permission model: high.
- TeX shell escape risks: high.
- Exact compatibility among external MacTeX, sandboxing, and each distribution model: medium/low without local testing.
- Adversarial security of the complete toolchain: medium/low without a prototype and corpus tests.

## 11. MVP implications

### Accepted risks

Conditionally acceptable for personal use:

- residual vulnerabilities in WebKit, PDFKit, or parsers;
- resource-consuming content, provided a timeout and recovery mechanism exist;
- the need for the user to grant folder access;
- dependence on an external TeX installation if the MVP is not sandboxed/distributed;
- opening external links only after explicit confirmation.

### Mitigated risks

These should be addressed by the chosen implementation:

- JavaScript and active HTML;
- unintended network requests;
- references outside the folder;
- compiler writes to the original folder;
- arbitrary shell escape;
- execution of helper tools;
- permissions lost after relaunch;
- PDFs with external actions;
- temporary dependencies mixed with the project;
- unbounded logs or hung processes.

### Deferred risks

These may remain outside the first validation, but should be explicit:

- support for client-side JavaScript;
- arbitrary HTML with forms, iframes, SVG, or document-provided CSS;
- authorized references outside the selected folder;
- compiling projects with full shell escape;
- automatic installation of TeX packages;
- sandboxed Mac App Store distribution with external TeX;
- auto-update;
- protection against every malformed PDF;
- bundling full MacTeX/TeX Live.

## 12. Error messages and recovery

The UI should distinguish these cases without hiding the cause:

- “macOS did not authorize this folder.”
- “The file exists, but is outside the authorized root.”
- “The resource was blocked by preview policy.”
- “The PDF contains an external action that was not opened.”
- “The compiler was not found or is incompatible.”
- “Compilation exceeded the time limit.”
- “Compilation attempted to use disallowed shell escape.”
- “The PDF/HTML could not be processed.”
- “The preview process ended; it can be restarted without changing the source files.”

Recovery should allow compilation to be cancelled, the renderer to be restarted, and temporary artifacts to be deleted without touching source files.

## 13. Gaps and next tests

These points require a prototype or local testing:

1. `WKWebView` behavior with `loadFileURL`, in-memory HTML, and an app-owned scheme;
2. access to relative images, `..`, symlinks, and absolute paths;
3. actual effectiveness of CSP/meta CSP in the chosen loading mode;
4. WebView network requests without a client network entitlement;
5. execution of links and PDF actions on each supported macOS version;
6. PDFs with attachments, Launch actions, forms, and corrupted documents;
7. sandbox inheritance in a helper and bookmark passing;
8. ability to run external MacTeX from a sandboxed app;
9. behavior of `pdflatex`, `xelatex`, `lualatex`, BibTeX, and helper tools with shell escape disabled/restricted;
10. timeout, process-tree termination, and memory/output limits;
11. notarization of all bundled executables;
12. license matrix for any redistributed TeX subset.

## 14. Source ledger

| Source | Date/version checked | Status | Reason |
|---|---|---|---|
| Apple WebKit documentation | Accessed 2026-09-09 | Used | Primary API source for WebView, navigation, JavaScript, and processes |
| Apple PDFKit documentation | Accessed 2026-09-09 | Used | Primary API source for PDF reading and actions |
| Apple Quick Look documentation | Accessed 2026-09-09 | Used | Native preview alternative |
| Apple App Sandbox documentation | Accessed 2026-09-09 | Used | Entitlements, folders, bookmarks, and helpers |
| Apple Hardened Runtime/notarization | Accessed 2026-09-09 | Used | Current distribution requirements |
| TeX Live Guide 2026 | Published 2026-02-21; release 2026-03-01 | Used | Shell escape, security, and platforms |
| MacTeX 2026 | Update listed on 2026-03-24 | Used | Compatibility, sizes, signing, and notarization |
| DOMPurify Security Goals | Current version listed as 3.4.15 on 2026-09-09 | Used | Sanitizer limitations and advisories |
| W3C CSP Level 3 | Accessed 2026-09-09 | Used | Normative basis for CSP |
| Adobe PDF documentation | Accessed 2026-09-09 | Partially used | PDF action taxonomy; not used to claim specific PDFKit behavior |
| Apple Developer Forums | Consulted during discovery | Rejected as primary evidence | Useful discussions, but not normative documentation |
| MDN same-origin/file URLs | Consulted during discovery | Rejected for macOS claims | Secondary source; does not replace WebKit/App Sandbox documentation |
| Blogs, snippets, Stack Overflow, and rankings | Not used | Rejected | Do not meet the requirement for current primary sources |
| Comparative benchmarks | Not found/needed | Not used | No comparative evidence applied to the MVP's specific workflow |

## 15. Research log

| Query | Discovery path | Result |
|---|---|---|
| Q1 | Local documentation → contexts, brief, vision | Scope, format, and threat model |
| Q2 | Apple Developer → WebKit/WKWebView | Local HTML, JS, navigation, and process capabilities |
| Q3 | Apple Developer → PDFKit/Quick Look | Reading surfaces and limitations |
| Q4 | Apple Developer → App Sandbox | Selected files, bookmarks, and entitlements |
| Q5 | Apple Developer → XPC/helper tools | Isolation and child-process limitations |
| Q6 | TUG → TeX Live/MacTeX | Shell escape, versions, sizes, and licensing |
| Q7 | Apple Developer → Hardened Runtime/notarization | Distribution requirements |
| Q8 | DOMPurify/W3C | Sanitization, CSP, CSS, and leaks |
| Q9 | Adobe PDF documentation | PDF actions and link/Launch risks |

## Reason for stopping the research

The research found sufficient primary evidence to:

- compare the main preview surfaces;
- define a defense-in-depth posture;
- identify the material conflict between sandboxing and an external LaTeX compiler;
- separate accepted, mitigated, and deferred risks;
- specify the remaining tests.

Continuing documentary research without choosing a minimum macOS version, distribution model, and compilation strategy would mostly add detail without resolving the central uncertainties. Those uncertainties require local testing and later project decisions, which this brief explicitly should not settle.

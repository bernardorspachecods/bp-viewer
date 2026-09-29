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

## 5. Decisões que dependem da opinião/uso pessoal de Bernardo

As perguntas abaixo são deliberadamente simples. Cada opção tem uma consequência concreta; a recomendação é condicional e não uma decisão tomada nesta síntese.

### 5.1 O que significa “preview” de LaTeX para o uso principal?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Confirmar a composição visual da tese** — PDF | Se a pergunta diária for “a tese compilou e está visualmente correta”, começar por PDF com o engine compatível com a tese | Mais fidelidade; menos HTML semântico; é preciso PDFKit e política para actions PDF |
| **Navegar/pesquisar a estrutura** — HTML | Se headings, links, pesquisa e acessibilidade forem mais importantes que equivalência visual, testar TeX4ht/make4ht, lwarp e/ou LaTeXML | Mais transformação e incompatibilidade; não há equivalência visual garantida |
| **Querer os dois** — PDF + HTML | Só se ambos forem necessidades reais desde o início e houver capacidade para duas cadeias | Duplica compilação, diagnósticos, caches, validação e superfícies de segurança |

**Decisão de Bernardo:** qual destas tarefas justifica a primeira versão?

### 5.2 O primeiro objetivo é protótipo pessoal local ou aplicação distribuível?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Protótipo pessoal no Mac atual** | Permite validar cedo com ferramentas já instaladas, registando o risco aceite | Pode depender de MacTeX/BasicTeX externo; não prova compatibilidade sandboxed nem distribuição universal |
| **Aplicação fora da App Store, assinada/notarizada** | Avaliar depois de um protótipo, mantendo executáveis e licenças sob controlo | Mais liberdade operacional, mas todos os executáveis e helpers precisam de assinatura/notarização e inventário |
| **Mac App Store/App Sandbox** | Tratar a distribuição como requisito desde o primeiro teste de compilação | TeX externo não é uma solução simples; pode exigir helpers/XPC empacotados, bookmarks e custo elevado de distribuição |

**Decisão de Bernardo:** o custo de distribuição deve limitar o MVP ou pode ficar para depois?

### 5.3 Que prioridade deve escolher o shell desktop?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **SwiftUI/AppKit** | Se integração macOS, bookmarks e comportamento de app Mac forem prioridade | Menos bridging para permissões/processos; UI e infraestrutura ficam em Swift |
| **Tauri 2** | Se UI web e core Rust forem importantes e houver disponibilidade para bridge macOS própria | WebView natural e bundle potencialmente menor; scopes persistentes no macOS precisam de validação/implementação |
| **Electron** | Se TypeScript/Node e ferramentas web reduzirem muito o risco de desenvolvimento | IPC e tooling fortes; bundle maior e ciclo Chromium/Node mais frequente |
| **Flutter** | Se a futura multiplataforma pesar mais que a hipótese de preview WebKit nativo | UI compilada; nenhum ganho específico foi demonstrado para este MVP macOS-first |

**Decisão de Bernardo:** qual custo é mais aceitável: Swift/native, Rust/bridge, bundle Electron ou Flutter?

### 5.4 Qual dialecto e nível académico de Markdown são realmente necessários?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **CommonMark + GFM + matemática comum** | Se os capítulos usam estrutura, tabelas, footnotes e fórmulas sem semântica LaTeX avançada | Permite começar com pipeline mais limitada; não oferece bibliografia, includes ou `\\label`/`\\ref` de forma geral |
| **Markdown com AST e extensões académicas próprias** | Se links entre capítulos, referências, composição e diagnósticos forem parte do fluxo real | Favorece `remark`/`unified` ou AST equivalente; aumenta manutenção e contratos próprios |
| **Markdown como aproximação de LaTeX** | Se os documentos dependem de referências matemáticas/bibliográficas e composição LaTeX-like | Pode tornar LaTeX/PDF o caminho principal; KaTeX provavelmente não basta para todos os casos |

**Decisão de Bernardo:** quais são os três ficheiros Markdown reais que devem ser suportados primeiro?

### 5.5 Dependências fora da pasta raiz devem funcionar?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Deny access outside the root** | If containment and predictability are priorities | Simple, safe policy; some existing projects will no longer compile/render |
| **Ask for additional authorization** | If there are legitimate dependencies outside the root and Bernardo accepts an explicit choice | Preserves control; requires multiple scopes/bookmarks, an additional watcher, and permission UX |
| **Allow automatically** | Only if convenience clearly outweighs the threat | Greater compatibility, but conflicts with the authorized-root posture and increases accidental exfiltration/writes |

**Bernardo's decision:** are projects self-contained, or is it normal for them to share resources outside the open folder?

### 5.6 How should external links work?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Block** | If the preview must remain offline and strictly local | Greater containment; web links are no longer useful |
| **Open externally after an explicit action** | If bibliographic/web links are useful but must not load in the WebView | Preserves utility with a visible choice; moves network risk to the browser |
| **Load in the preview** | Only if interactivity/network access is a real requirement | Requires a much broader CSP/network policy and increases attack surface |

**Bernardo's decision:** are external links part of the reading task or only a convenience?

### 5.7 How compatible must LaTeX compilation be?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Compatibility with the thesis's current environment** | If the thesis already compiles with a known engine/distribution | Better chance of fidelity; external dependencies and local configuration become central |
| **Controlled/portable environment** | If reproducibility, offline use, and distribution matter more | Consider Tectonic or bundled TeX, but validate the engine, Biber, fonts, paths, and licenses |
| **Broad compatibility with arbitrary TeX projects** | Only if higher costs are acceptable | Approaches full TeX Live/MacTeX; increases bundle size, execution surface, and support needs |

**Bernardo's decision:** does the app need to open his thesis, or be a general tool for LaTeX projects?

## 6. Conflitos e incompatibilidades entre reports

### 6.1 HTML flexível versus segurança e simplicidade

O report Markdown favorece `remark`/`unified` quando JavaScript é aceitável, devido ao AST, transformações de links, matemática e sanitização. O report de segurança favorece `WKWebView` com HTML estático e JavaScript desligado. Não há contradição necessária: o JavaScript pode existir no processo local de pré-renderização e ser excluído do conteúdo entregue à WebView. Há, porém, uma decisão de empacotamento/runtime e uma pipeline de compatibilidade a validar.

### 6.2 `cmark-gfm`/nativo versus `remark`/AST rico

`cmark-gfm` ou `swift-markdown` reduzem dependências e favorecem integração nativa, mas exigem renderer próprio para links, âncoras, matemática e políticas de recursos. `remark`/`unified` reduz esse trabalho de transformação, mas aumenta a superfície de pacotes, a importância da ordem dos plugins e a necessidade de pinning. O report não mede o custo real no corpus de Bernardo; a escolha depende do shell, do runtime aceitável e das extensões necessárias.

### 6.3 PDF fiel versus HTML navegável

O report LaTeX não trata PDF e HTML como equivalentes. PDF preserva melhor o resultado do motor original; HTML oferece vantagens de estrutura, pesquisa e acessibilidade. Escolher HTML por ser mais fácil de inserir numa WebView pode falhar na tarefa principal de conferir uma tese. Escolher PDF pode sacrificar semântica e flexibilidade de navegação. Esta é uma decisão de uso, não uma conclusão apenas técnica.

### 6.4 TeX externo versus App Sandbox/Mac App Store

O report LaTeX recomenda validar primeiro uma cadeia tradicional e admite Tectonic como alternativa operacional. O report de segurança alerta que uma permissão de ficheiro escolhido pelo utilizador não autoriza simplesmente executar programas externos fora da app, container ou app group numa aplicação sandboxed. Assim, “usar MacTeX instalado” pode ser aceitável para um protótipo pessoal, mas não deve ser promovido automaticamente a arquitetura de distribuição sandboxed.

### 6.5 Watch mode da ferramenta versus watcher da aplicação

`latexmk` e Tectonic têm modos de watch; Tauri, Chokidar e `notify` têm abstrações de watch. Nenhum report permite concluir que isso substitui o coordenador do `bp-viewer`: continuam necessários root discovery, dependências, debounce, snapshot/re-scan, geração, cancelamento e proteção contra resultados obsoletos.

### 6.6 Tectonic simples versus TeX Live abrangente

Tectonic reduz instalação e pode operar com cache, mas usa essencialmente XeTeX, pode precisar de Biber externo/compatível e divergir de paths/configurações tradicionais. TeX Live/MacTeX é mais abrangente, mas grande e difícil de empacotar/limitar. A release 0.17.0 corrigiu um problema específico de macOS ARM64 reportado contra 0.16.x; isso exige testar versões concretas, não concluir que Tectonic é geralmente inadequado ou seguro.

### 6.7 Sanitização, CSP e JavaScript desligado não são substitutos

O report de segurança regista limites distintos: DOMPurify não é sanitizer completo de CSS nem bloqueador de leaks HTTP; CSP é defesa em profundidade; JavaScript desligado não impede todos os pedidos passivos; processo separado do WebKit reduz impacto mas não elimina bugs. A política precisa de combinar as camadas.

### 6.8 Versões observadas e integração

O report Markdown encontrou desalinhamentos entre `rehype-katex`/KaTeX e `rehype-mathjax`/MathJax; isso não prova incompatibilidade final, mas impede assumir que “latest” funciona. Os reports desktop e LaTeX também contêm snapshots de versões e instalações locais diferentes. Todos devem ser tratados como observações datadas, com pinning e teste local antes de qualquer decisão.

## 7. Proposta de ordem de validação/prototipagem, priorizada por risco

Esta ordem prioriza riscos que podem invalidar a arquitetura inteira, não a conveniência de implementação. É uma proposta de trabalho, não uma decisão de produto.

### 0. Fixar o cenário de validação

Antes do código, Bernardo deve escolher temporariamente: tese/corpus real ou fixtures representativos; macOS mínimo; protótipo pessoal ou distribuição sandboxed; e se o objetivo LaTeX é PDF ou HTML. Sem isto, os resultados não têm critério comum.

### 1. Validar a cadeia LaTeX real — risco máximo

Com uma cópia dos documentos e outputs num diretório temporário:

- identificar root, `\\input`/`\\include`, imagens, `.bib`, `.sty`, `.cls`, fontes e ferramentas;
- testar o engine atual da tese com TeX Live/MacTeX/instalação existente e `latexmk` quando disponível;
- testar bibliografia clássica e BibLaTeX/Biber se usados;
- testar paths com espaços/Unicode, erros, pacote ausente, imagem ausente e pedido interativo;
- testar recompilação após alterações e confirmar que nada é escrito na pasta raw;
- testar shell escape desligado e registar exatamente o que deixa de funcionar.

**Critério de saída:** há uma cadeia que compila o corpus prioritário com diagnósticos controláveis, ou está documentado que a tese exige uma capacidade ainda não suportada.

### 2. Validar o conflito distribuição–compilador

Testar separadamente execução local de desenvolvimento, app assinada/notarizada se relevante e sandbox. Verificar acesso ao root, passagem de bookmarks ao helper, execução de compiladores externos, herança de sandbox, XPC/helper, assinatura e dependências.

**Critério de saída:** está claro se o MVP aceita TeX externo como risco pessoal ou se precisa de executáveis empacotados. Se Mac App Store for requisito, este passo não pode ser adiado.

### 3. Validar filesystem, dependências e concorrência

Construir fixtures para o contrato, independentemente da UI final:

- snapshot inicial com watcher já ativo;
- escrita incremental e rename atómico;
- bursts de alterações e eventos coalescidos/dropped;
- alteração/remoção de imagens, includes e bibliografia;
- raiz movida, permissões perdidas e bookmark stale;
- render lento que termina depois de uma geração nova;
- cancelamento e árvore de processos.

**Critério de saída:** snapshot/re-scan, manifesto de dependências e rejeição por geração produzem sempre o estado correto nos cenários testados.

### 4. Validar contenção de HTML e PDF

Antes de aceitar um parser específico, testar `WKWebView`/PDFKit no macOS mínimo com scripts, handlers, `iframe`, SVG, URLs perigosas, imagens externas, `..`, symlinks, paths absolutos, redirects, downloads, attachments e PDF actions.

**Critério de saída:** cada tentativa é bloqueada, explicitamente permitida ou diagnosticada conforme a política escolhida; não se assume que a API fará a política sozinha.

### 5. Comparar pipelines Markdown no corpus real

Usar a fixture sugerida pelo report Markdown: headings, tabelas, footnotes, código, imagens, links, âncoras, matemática comum, `\\label`/`\\ref`/`\\eqref`, macros e erros. Comparar `remark`/`unified`, `cmark-gfm`/`swift-markdown`, `markdown-it`, `micromark` e/ou `markdown-rs` apenas onde forem candidatos ao shell escolhido.

**Critério de saída:** dialecto suportado, limitações e renderer matemático estão escritos com exemplos de entrada/saída e diagnósticos.

### 6. Validar shell, permissões e restauração de UX

Só depois dos riscos anteriores, comparar os shells com a mesma sessão: abrir pasta, lazy tree, tabs, reinício, bookmark, seleção, WebView/PDF, mensagens de erro e atualização.

**Critério de saída:** a decisão de shell é baseada no fluxo e nos testes locais, não em tamanho de bundle ou preferência abstrata.

### 7. Validar alternativas LaTeX de HTML apenas se HTML for escolhido

Comparar TeX4ht/make4ht, lwarp e LaTeXML com a tese/fixtures, incluindo bibliografia, cross-references, imagens, MathML, CSS, splitting e diagnósticos. Não usar listas de pacotes suportados como prova de fidelidade geral.

### 8. Validar empacotamento e manutenção

Fixar versões; repetir builds offline; verificar compatibilidade `rehype-katex`/KaTeX e `rehype-mathjax`/MathJax; inventariar licenças; testar Apple Silicon, assinatura, notarização e tamanho real. Só então transformar uma recomendação condicional em decisão técnica aprovada.

## 8. Perguntas abertas para continuar a discussão do produto

1. O caso principal é uma tese única de Bernardo ou vários projetos heterogéneos?
2. A primeira versão precisa de suportar LaTeX que já depende de `biber`, TikZ/PGFPlots, fontes do sistema, shell escape ou ferramentas externas?
3. Qual é o macOS mínimo aceitável?
4. A pasta raiz deve ser autocontida por contrato?
5. O utilizador deve poder conceder acesso a dependências fora da raiz, e esse acesso deve persistir?
6. Um capítulo LaTeX selecionado deve sempre compilar o root, ou deve existir uma opção para compilar o ficheiro selecionado isoladamente quando possível?
7. Como deve a app escolher entre zero, um ou vários roots candidatos, e onde deve persistir a escolha?
8. O último preview válido deve continuar disponível após erro? Como deve ser marcado e por quanto tempo?
9. O que significa “atualizado” quando uma imagem ou include muda durante a compilação?
10. Qual a política para symlinks: ignorar, mostrar sem seguir ou seguir dentro de uma allow-list?
11. Links `.md#heading` devem abrir/focar tabs, e como devem ser tratados links para ficheiros inexistentes?
12. MathJax é necessário pelas referências matemáticas reais, ou KaTeX cobre o corpus prioritário?
13. Footnotes são suficientes, ou Bernardo precisa de bibliografia/citações semânticas em Markdown?
14. CSS fornecido pelo documento deve ser permitido, limitado ou removido?
15. Links externos devem ser bloqueados ou abertos no browser mediante confirmação?
16. O MVP precisa de notarização/distribuição ou apenas de correr no Mac de desenvolvimento?
17. A app deve funcionar sem qualquer rede depois de instalada, incluindo pacotes/fontes TeX?
18. Qual o tempo de atualização aceitável para um capítulo pequeno, médio e grande?
19. Qual o comportamento desejado para uma compilação que exceda timeout ou consuma recursos excessivos?
20. O editor futuro muda algum contrato do viewer agora, além da separação arquitetural então prevista?

## 9. Claims que ainda exigem validação local

Os seguintes pontos aparecem nos reports como lacunas ou próximos testes. Não são factos já confirmados para o `bp-viewer`.

### Corpus e renderização

- Qual parser Markdown reproduz corretamente os ficheiros reais, incluindo HTML bruto, tabelas, footnotes, imagens, anchors, Unicode e blocos de código.
- Se os documentos reais precisam de includes, bibliografia, referências semânticas ou convenções fora de CommonMark/GFM.
- Se KaTeX cobre a matemática usada; em particular, `\\label`, `\\ref`, `\\eqref`, ambientes, macros e erros.
- Se MathJax funciona com a versão realmente resolvida e com o tempo/complexidade aceitáveis.
- Compatibilidade concreta entre `remark`/`rehype`, KaTeX/MathJax, sanitização e o HTML produzido.
- Fidelidade de TeX4ht/make4ht, lwarp e LaTeXML para a tese real, se HTML LaTeX for considerado.

### LaTeX e processos

- Qual root deve ser descoberto para cada projeto, incluindo zero ou múltiplos candidatos.
- Se TeX Live/MacTeX, BasicTeX, MiKTeX ou Tectonic compilam o corpus com o engine esperado.
- Compatibilidade de BibTeX, BibLaTeX, Biber, MakeIndex/Xindy, TikZ/PGFPlots, fontes e conversores.
- Efeito de shell escape desligado/restrito e necessidade de ferramentas auxiliares.
- Funcionamento offline com cache Tectonic completo/incompleto e sem instalação automática.
- Fecho da árvore de processos no cancelamento e ausência de locks/artefactos residuais.
- Tempo, memória, tamanho de logs e tamanho de artefactos sob documentos pequenos, médios e grandes.

### Filesystem e permissões

- Custo de snapshot/re-scan e lazy loading em árvores semelhantes às do projeto.
- Semântica concreta do backend escolhido perante rename atómico, escrita em blocos, bursts, coalescing e dropped events.
- Deteção de alterações em imagens, includes, `.bib`, `.sty`, `.cls` e dependências fora da raiz.
- Persistência, stale e recuperação de security-scoped bookmarks em build assinada/sandboxed.
- Acesso e reabertura após rename da raiz, perda de permissão, ACL/TCC e subpasta ilegível.
- Política de symlinks, ciclos, paths absolutos, `..`, volumes de rede/SMB e case-insensitive filesystem.
- Memória, arranque e responsividade reais dos shells; os reports não têm benchmark comparativo suficiente.

### Preview e segurança

- Comportamento de `loadFileURL`, `loadHTMLString(baseURL:)` e eventual esquema app-owned.
- Eficácia concreta de CSP/meta CSP no modo de carregamento escolhido.
- Pedidos de rede passivos sem entitlement e comportamento de imagens/CSS/URLs.
- Execução efetiva de scripts, handlers, redirects, downloads, novas janelas e esquemas perigosos.
- PDFKit perante URLs, `file:`, Launch, remote go-to, attachments, forms, JavaScript PDF, PDFs corrompidos ou muito grandes.
- Herança de sandbox, passagem de bookmarks e permissões ao helper/XPC.
- Assinatura/notarização de executáveis empacotados e matriz de licenças.

## 10. Mapa das fontes

Os quatro reports originais são as fontes de síntese e contêm os links para as fontes primárias, ledgers, versões observadas, registos de pesquisa, refutações e razões para parar. As fontes primárias não foram reconsultadas nesta tarefa.

- [Relatório: Markdown → HTML](reports/markdown-html.md) — parser, AST, GFM, matemática, links, sanitização e testes locais sugeridos.
- [Relatório: LaTeX → preview](reports/latex-preview.md) — PDF/HTML, engines, `latexmk`, Tectonic, multi-ficheiro, bibliografia, artefactos, segurança e testes locais.
- [Relatório: desktop e filesystem](reports/desktop-filesystem.md) — shells, permissões, FSEvents/watchers, contratos, filas, processos e testes de filesystem.
- [Relatório: preview, segurança e distribuição](reports/preview-security-distribution.md) — WebKit, PDFKit, sandbox, bookmarks, helpers/XPC, shell escape, distribuição e modelo de ameaça.

**Nota de procedência:** as referências a claims nesta síntese apontam para secções dos reports originais. A data, versão e força da evidência devem ser consultadas nesses documentos; não devem ser inferidas apenas a partir desta síntese.

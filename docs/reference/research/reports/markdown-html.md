# Research report: Markdown → HTML

Research date: 2026-09-09  
Repository context: [research archive](../CONTEXT.md), [Markdown brief](../markdown-html.md), and [current state](../../../current-state.md).

## 1. Executive summary

The best option depends on the desktop runtime, which has not yet been chosen:

- If bundling JavaScript is acceptable, the most complete option is a local `remark`/`unified` pipeline: CommonMark + GFM + mathematics → AST → link/anchor transformation → HTML → sanitization.
- If the MVP requires native integration without a JavaScript runtime, `cmark-gfm` is a small, fast base with no external dependencies, but requires custom work for link rewriting, anchors, mathematics, and fine-grained HTML control.
- `markdown-it` is a balanced alternative for direct HTML and custom syntax, but mathematics and footnotes require separate components.
- `swift-markdown` is interesting for a Swift project, but does not remove the need to create an HTML renderer and carefully validate footnotes, URLs, and safe HTML.

The conditional recommendation is:

> Prefer a local AST-aware pipeline based on `remark`/`unified` if a JavaScript runtime is acceptable. Prefer `cmark-gfm`/`swift-markdown` if native integration and minimal dependencies are priorities, provided local tests confirm the real documents do not require academic semantics beyond Markdown/GFM.

Markdown handles structure, tables, code blocks, images, links, anchors, and footnotes well. By itself it does not provide a complete system for bibliographic citations, cross-file includes, global equation numbering, or semantic references such as `\\label`/`\\ref`.

## 2. Question and supported decision

The research examined which parser and pipeline offer the best balance of:

- fidelity to real Markdown;
- GFM, tables, quotations, and footnotes;
- mathematics;
- extensibility;
- offline operation;
- security;
- control over HTML/CSS;
- updates after external changes;
- integration and maintenance complexity.

The research supports comparing approaches and recommending a conditional direction. It does not settle:

- desktop framework;
- language;
- final policy for external links;
- definitive Markdown dialect;
- need for full LaTeX compatibility;
- final choice between KaTeX and MathJax.

## 3. Scope and assumptions

Included:

- local Markdown files;
- chapters with mathematics and relative images;
- links to other files;
- frequent changes from external processes;
- potentially dangerous content;
- HTML rendering on a reading surface;
- local dependencies and offline distribution.

Out of scope:

- desktop framework;
- interface design;
- adapter implementation;
- source editing;
- exhaustive comparison of all parsers;
- full bibliography management;
- LaTeX compilation.

“Offline” means that the runtime does not depend on servers, CDNs, or APIs during use. Dependencies may be acquired during development and bundled with the app.

## 4. Evaluation criteria

The relevant criteria are:

- CommonMark/GFM compliance;
- representation of academic documents;
- AST and transformation capabilities;
- predictable HTML and styling;
- mathematics and error handling;
- local resource resolution;
- security for HTML, URLs, and scripts;
- performance and predictability;
- native or JavaScript integration;
- licensing;
- maintenance and updates;
- behavior after external changes.

Rankings, popularity, and third-party benchmarks were not used as proof of quality. Performance numbers published by the projects themselves are treated only as indications.

## 5. Claim matrix

| Claim | Importance | Status | Evidence | Limitation |
|---|---:|---|---|---|
| C1. CommonMark remains the clearest baseline for parser compatibility. | High | Fact | E1 | The specification does not cover every extension used in real documents. |
| C2. GFM adds tables, strikethrough, task lists, autolinks, and footnotes. | High | Fact | E2, E5 | The published GFM specification is old; current GitHub behavior includes additional post-processing. |
| C3. `cmark-gfm` provides an AST, HTML renderer, C99, and zero external runtime dependencies. | High | Fact | E3 | The API is low-level and requires additional work for product policies. |
| C4. `markdown-it` has configurable rules, a token renderer, and browser distribution. | High | Fact | E4 | Mathematics and some academic extensions are outside the core. |
| C5. `micromark` supports CommonMark, GFM, mathematics, and frontmatter through extensions. | High | Fact | E5 | Extensions are ESM and AST integration requires additional components. |
| C6. `remark`/`unified` supports AST transformations and HTML conversion through `remark-rehype`. | High | Fact | E6 | The pipeline has more packages and a larger maintenance surface. |
| C7. The `remark` ecosystem supports GFM and mathematics through maintained plugins. | High | Fact | E6, E7 | Correct composition and plugin order are the app's responsibility. |
| C8. Footnotes are viable in GFM but do not constitute a bibliography system. | High | Fact + inference | E2, E7, E9 | There is no semantic model for bibliographic references, bibliographies, or author-date citations. |
| C9. KaTeX can render to HTML without client-side JavaScript. | High | Fact | E8 | TeX coverage is incomplete; `\\label`, `\\ref`, and `\\eqref` are unsupported. |
| C10. MathJax offers broader coverage and supports processing in Node. | High | Fact | E8, E9 | The pipeline is more asynchronous and operationally heavier. |
| C11. Parsers that are safe by default do not automatically make a WebView safe. | Critical | Fact | E3, E5, E7, E10 | Navigation, URLs, resources, and scripts still need control. |
| C12. Relative links and images should be resolved from the Markdown file, not the working directory. | High | Fact + recommendation | E10 | Whether to allow traversal outside the project folder remains a product decision. |
| C13. Markdown does not define includes or semantic relationships between files. | High | Fact | E1, E2, E11 | The app can add its own rewriting, validation, or composition. |
| C14. Automatic updates should invalidate the preview when Markdown or relevant dependencies change. | High | Operational inference | E12 | Debouncing, cancellation, and atomic-write detection require local testing. |
| C15. Local rendering before the WebView reduces the WebView's parsing responsibility. | High | Architectural inference | E6, E10 | HTML still needs sanitization and resource controls. |
| C16. `swift-markdown` is a plausible native integration but requires a custom HTML renderer. | High | Fact + inference | E13 | No ready-to-use official API equivalent to `remark-rehype` was found for this purpose. |
| C17. `markdown-rs` is a modern Rust alternative with HTML, AST, GFM, and mathematics. | Medium | Fact | E14 | Integration maturity and the lack of an external plugin system comparable to unified need validation. |

## 6. Investigated alternatives

### 6.1 `cmark-gfm` or `swift-markdown`

`cmark-gfm` is the reference C implementation associated with GFM. The project provides:

- CommonMark parser;
- GFM extensions;
- manipulable AST;
- HTML renderer;
- LaTeX, XML, CommonMark, and other renderers;
- C99;
- no external dependencies;
- default sanitization of raw HTML and dangerous URLs.

The latest listed version is `0.29.0.gfm.13`. The project remains aligned with a GFM line based on specification `0.29`, while the main CommonMark specification is already at `0.31.2`.

Its strengths are predictability and native integration. Its weakness is that the HTML renderer does not by itself handle:

- `.md` links to the viewer's internal route;
- heading IDs according to a custom policy;
- relative images and permissions;
- mathematics `$...$`;
- handling of custom HTML;
- cross-document references.

`swift-markdown` uses `cmark-gfm` and exposes a persistent tree of Swift values, along with `MarkupVisitor` for creating custom renderers. It is a good option if the app is Swift-native, but requires writing and maintaining the HTML renderer.

### 6.2 `markdown-it`

`markdown-it` provides:

- CommonMark support;
- configurable rules;
- plugins;
- token-based renderer;
- ESM, CommonJS, and browser builds;
- MIT license;
- observed version `15.0.1`.

It offers a good balance for direct HTML and small, specific extensions. Tables and strikethrough are close to its expected use, but footnotes are provided through a separate plugin (`markdown-it-footnote`). Mathematics would require selecting and validating another plugin, fragmenting the pipeline.

It is a plausible alternative if the main requirement is controllable HTML with few transformations. It is less compelling if the app needs a rich semantic tree to rewrite links, inspect references, extract headings, validate files, and add different transformations.

### 6.3 `micromark` + extensions

`micromark` is a state-machine parser with concrete tokens and direct HTML compilation. The observed version is `4.0.2`. Official extensions include:

- GFM;
- tables;
- footnotes;
- task lists;
- tag filtering;
- mathematics;
- frontmatter;
- directives.

The observed GFM extension is `3.0.0`; the math extension is `3.1.0`.

It is particularly strong when direct HTML, safe defaults, and a small implementation are desired. Its own documentation recommends `micromark` for converting Markdown to HTML with selected extensions.

For `bp-viewer`, however, the need to transform relative links, resolve files, and create internal routes may justify an additional AST layer. In that case, `micromark` is no longer the whole pipeline and instead becomes the parsing core.

### 6.4 `remark`/`unified` + `rehype`

This is the most extensible alternative. The conceptual pipeline is:

```text
Markdown
  → remark-parse
  → remark-gfm
  → remark-math
  → AST transformations
  → remark-rehype
  → math renderer
  → rehype-sanitize
  → HTML
```

The observed ecosystem includes:

- `remark` `15.0.1`;
- `remark-gfm` `4.0.1`;
- `remark-math` `6.0.0`;
- `rehype-katex` `7.0.1`;
- `rehype-mathjax` `7.1.0`;
- `rehype-sanitize` `6.0.0`.

Advantages:

- AST Markdown (`mdast`);
- AST HTML (`hast`);
- transformations that are easy to test;
- GFM with footnotes;
- integrated math;
- ID extraction and generation;
- local link validation;
- ability to alter HTML without manually concatenating strings.

Disadvantages:

- larger number of dependencies;
- ESM-only in several packages;
- need to pin compatible versions;
- plugin order matters;
- sanitization requires a schema suited to math and syntax highlighting.

It offers the best coverage for the complete scenario described in the brief.

### 6.5 `markdown-rs`

`markdown-rs` is a Rust alternative with:

- CommonMark;
- GFM;
- footnotes;
- tables;
- task lists;
- mathematics;
- frontmatter;
- AST `mdast`;
- safe-by-default HTML.

The version observed in `Cargo.toml` is `1.0.0`, with `rust-version = 1.56`. The project uses a monolithic architecture with extensions enabled through options.

It is relevant for a native Rust desktop app, but does not automatically solve WebView integration, link rewriting, or resource policies. Its extensibility model is less modular than `unified`.

## 7. Evidence-based comparison

### Variants and real documents

CommonMark is the most interoperable baseline. GFM adds several constructs that are useful for a thesis:

- tabelas;
- footnotes;
- strikethrough;
- task lists;
- autolinks.

However, GFM is not a complete academic standard. Frontmatter, directives, includes, bibliographic citations, and static-site conventions are additional extensions.

The GFM published by GitHub is `0.29-gfm`, dated 2019. The specification itself notes that GitHub performs post-processing and sanitization after conversion. Therefore, “GFM-compatible” does not necessarily mean “identical to current GitHub behavior.”

### AST and extensibility

For simple transformations, `markdown-it` may be sufficient through rules and tokens.

For `bp-viewer`, an explicit AST is more important because it allows the app to:

- resolve URLs relative to the file path;
- distinguish external links, images, headings, and internal references;
- generate IDs;
- validate links to other documents;
- replace `.md` links with internal routes;
- apply sanitization after transformations;
- produce diagnostics with file positions.

Here, `remark`/`unified` and `markdown-rs` have a structural advantage over direct HTML renderers.

### Mathematics

Mathematics is not part of CommonMark or GFM. The `remark-math` extension explicitly notes that this syntax reduces Markdown portability.

KaTeX:

- generates HTML in the local process;
- provides `renderToString`;
- needs no math JavaScript in the WebView;
- supports size and expansion limits;
- has a `trust` option for potentially dangerous commands.

However, the official table lists unsupported commands, including `\\label`, `\\ref`, and `\\eqref`. This limits reproduction of academic documents that rely on equation references.

MathJax:

- offers broader TeX coverage;
- supports CHTML, SVG, and MathML;
- can be used in Node;
- processes asynchronously;
- documents `\\label`, `\\ref`, and `\\eqref`.

The conditional choice is:

- KaTeX for common mathematics, predictability, and static HTML;
- MathJax when command and math reference coverage justifies greater complexity.

Even MathJax does not automatically turn multiple Markdown files into a complete LaTeX document with global numbering and cross-chapter references. That would require a custom document layer.

### Tables, footnotes, and references

GFM and the main alternatives support tables.

Footnotes are supported by:

- `remark-gfm`;
- `micromark-extension-gfm`;
- `cmark-gfm`, through the corresponding option;
- `markdown-rs`.

There are two limitations:

1. GFM footnotes are not equivalent to an academic bibliography.
2. Footnote behavior is not fully standardized within the GFM ecosystem; `micromark` documentation records differences and bugs in GitHub's implementation.

`remark-validate-links` demonstrates that validating links to headings and local files is a concern separate from the parser, not a universal Markdown capability.

### Images, relative links, and anchors

Markdown represents the destination of a link or image as a URL. It does not define that:

- `chapter-2.md` should open in the viewer;
- `chapter-2.md#method` should navigate to a rendered heading;
- an include should be expanded;
- links outside the project folder should be allowed;
- remote images should be loaded.

The app must define this policy.

For `WKWebView`, the `loadHTMLString(_:baseURL:)` API allows providing a base URL for resolving relative URLs. This can preserve references such as `../images/figure.png`, but the solution should:

- use the original Markdown folder as the base;
- control the read root;
- intercept links to other `.md` files;
- handle missing files;
- distinguish relative paths from remote URLs;
- prevent arbitrary navigation.

The recommendation is to resolve and normalize these destinations before passing HTML to the WebView, rather than relying only on automatic browser resolution.

### CSS, themes, and generated HTML

All alternatives produce HTML that can be styled with CSS.

`remark`/`rehype` offers more semantic control because it allows changing the HTML tree before serialization. This makes it easier to:

- theme classes;
- IDs;
- figure wrappers;
- code classes;
- reference markup;
- sanitization schemas.

`cmark-gfm` and `markdown-it` offer more direct HTML, but complex modifications tend to require a custom renderer or specific rules.

Syntax highlighting should be treated as an optional transformation. Basic code blocks do not require running code or loading scripts.

### Security

There are several distinct layers:

1. parser;
2. math renderer;
3. final HTML;
4. WebView;
5. resource loading;
6. navigation.

By default, `cmark-gfm` removes raw HTML and dangerous protocols such as `javascript:`, `vbscript:`, `data:`, and `file:`.

`micromark` is also safe by default, but warns that enabling `allowDangerousHtml` or `allowDangerousProtocol` changes this property.

`rehype-sanitize` removes anything not explicitly allowed by the schema. Its documentation recommends placing it after the last potentially unsafe transformation. The schema must carefully allow HTML produced by KaTeX/MathJax, including parts of SVG or MathML.

Parser security alone is not enough to secure the WebView. Final content must not be able to:

- execute `<script>`;
- define `onerror`, `onclick`, or other handlers;
- open an `iframe`;
- use dangerous protocols;
- load resources outside the defined policy;
- navigate the app to arbitrary pages.

MDX was deliberately excluded from this recommendation: its ecosystem documentation treats MDX as code, not safe Markdown.

### Updates and rerendering cost

The parser does not need to know about the filesystem. The update architecture can:

1. receive a change event;
2. wait for the write to finish;
3. reread the file;
4. cancel an earlier pending render;
5. rerender;
6. publish only the latest result.

Apple documents `DispatchSource` for filesystem events and `NSFilePresenter` for coordinated changes. The `NSFilePresenter` documentation warns that changes made by low-level writes do not generate file coordination notifications; therefore, the watcher should be validated with real external tools.

The cost of rerendering an entire chapter should be measured locally. This research has no sufficient independent comparative benchmark to claim that one alternative will be materially faster for the project's documents.

### Client versus local process

#### Rendering inside the WebView

Advantages:

- less IPC;
- direct DOM updates;
- parser and renderer can share JavaScript with the visual layer.

Risks:

- more privileged code inside the WebView;
- harder control over file and resource access;
- greater likelihood of mixing user content with app code;
- asynchronous math may complicate updates.

#### Prerendering in the local process

Advantages:

- file reading and resolution stay outside the WebView;
- sanitization happens before HTML is inserted;
- parsing errors can be normalized;
- the pipeline is easier to test independently of the interface;
- the WebView can receive only final HTML and known CSS.

Costs:

- IPC or a process/UI boundary;
- need to control cancellation and render versions;
- possible additional runtime if Node is used.

For this project, local prerendering appears to be the most predictable architecture, but this is an architectural recommendation, not a final decision.

## 8. Evidence

### E1 — CommonMark

The latest published CommonMark specification is `0.31.2`, dated 2024-01-28. It defines headings, lists, code blocks, nonstandard tables, links, images, raw HTML, and HTML-level anchors, but not GFM or mathematics.

Source: [CommonMark Specification](https://spec.commonmark.org/)

### E2 — GFM

The published GFM specification is `0.29-gfm`, dated 2019-04-06. It defines GFM as a strict superset of CommonMark and includes tables, task lists, strikethrough, and autolinks. It also states that GitHub performs additional sanitization and post-processing.

Source: [GitHub Flavored Markdown Spec](https://github.github.com/gfm/)

### E3 — cmark-gfm

The official repository documents an AST, multiple renderers, C99, no external dependencies, CommonMark tests, fuzzing, and default sanitization. The latest listed release is `0.29.0.gfm.13`.

Sources: [cmark-gfm README](https://github.com/github/cmark-gfm), [cmark-gfm releases](https://github.com/github/cmark-gfm/releases), [C API](https://raw.githubusercontent.com/github/cmark-gfm/master/src/cmark-gfm.h)

### E4 — markdown-it

The official documentation describes CommonMark, configurable rules, plugins, a renderer, and “safe by default.” The observed `package.json` lists `15.0.1`, MIT, with browser, ESM, and CommonJS exports.

Sources: [markdown-it README/documentation](https://markdown-it.github.io/markdown-it/), [package.json](https://raw.githubusercontent.com/markdown-it/markdown-it/master/package.json), [changelog](https://github.com/markdown-it/markdown-it/blob/master/CHANGELOG.md)

### E5 — micromark

The official documentation describes CommonMark, GFM, mathematics, frontmatter, concrete tokens, syntax and HTML extensions, default safety, and limits against excessive input. The observed versions are `micromark 4.0.2`, `micromark-extension-gfm 3.0.0`, and `micromark-extension-math 3.1.0`.

Sources: [micromark](https://github.com/micromark/micromark), [GFM extension](https://github.com/micromark/micromark-extension-gfm), [math extension](https://github.com/micromark/micromark-extension-math)

### E6 — remark/unified

The official documentation describes `mdast`, AST plugins, `remark-rehype` for conversion to `hast`, and transformation to HTML. `remark` recommends `micromark` when the only goal is HTML, but an AST pipeline is suitable when the product needs transformations.

Sources: [remark](https://github.com/remarkjs/remark), [remark-rehype](https://github.com/remarkjs/remark-rehype), [remark-gfm](https://github.com/remarkjs/remark-gfm)

### E7 — Mathematics in unified

`remark-math` documents the separation between math parsing and rendering with KaTeX or MathJax, including build-time rendering without client-side JavaScript.

Source: [remark-math](https://github.com/remarkjs/remark-math)

### E8 — KaTeX

The documentation observed is for version `0.18.7`. KaTeX provides `renderToString`, the `maxSize`, `maxExpand`, and `trust` options, and documents unsupported commands such as `\\label`, `\\ref`, and `\\eqref`.

Sources: [KaTeX API](https://katex.org/docs/api), [KaTeX security](https://katex.org/docs/security), [KaTeX options](https://katex.org/docs/options), [support table](https://katex.org/docs/support_table), [package.json](https://raw.githubusercontent.com/KaTeX/KaTeX/main/package.json)

### E9 — MathJax

The stable documentation observed is for MathJax 4. It documents Node usage, asynchronous processing, SVG/CHTML/MathML output, and references such as `\\label`, `\\ref`, and `\\eqref`.

Sources: [MathJax documentation](https://docs.mathjax.org/en/latest/), [documentation PDF](https://docs.mathjax.org/_/downloads/en/stable/pdf/), [rehype-mathjax package](https://raw.githubusercontent.com/remarkjs/remark-math/main/packages/rehype-mathjax/package.json)

### E10 — WebKit and local URLs

Apple documents `WKWebView.loadHTMLString(_:baseURL:)` for relative URL resolution and `loadFileURL(_:allowingReadAccessTo:)` for local content.

Sources: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/), [loadHTMLString(_:baseURL:)](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring%28_%3Abaseurl%3A%29)

### E11 — Links to other files

`remark-validate-links` checks links to local files and headings, including links to headings in other Markdown documents. This shows that validating cross-document references is an additional layer, not an intrinsic CommonMark capability.

Source: [remark-validate-links](https://github.com/remarkjs/remark-validate-links)

### E12 — External changes

Apple documents `DispatchSource` for filesystem events and `NSFilePresenter`/`NSFileCoordinator` for coordinated changes.

Sources: [DispatchSource filesystem events](https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent/all), [NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter), [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)

### E13 — Swift Markdown

`swift-markdown 0.8.0` uses `cmark-gfm` and provides a persistent tree and `MarkupVisitor`. The observed `Package.swift` requires Swift tools `6.2` at tag `0.8.0` and licenses the project under Apache-2.0 with the Runtime Library Exception.

Sources: [Swift Markdown](https://github.com/swiftlang/swift-markdown), [release 0.8.0](https://github.com/swiftlang/swift-markdown/releases), [Package.swift 0.8.0](https://raw.githubusercontent.com/swiftlang/swift-markdown/0.8.0/Package.swift), [MarkupVisitor](https://github.com/swiftlang/swift-markdown/blob/main/Sources/Markdown/Visitor/MarkupVisitor.swift)

### E14 — markdown-rs

The Rust project documents CommonMark, GFM, footnotes, mathematics, frontmatter, an AST, safe-by-default HTML, and version `1.0.0` in `Cargo.toml`.

Sources: [markdown-rs](https://github.com/wooorm/markdown-rs), [Cargo.toml](https://raw.githubusercontent.com/wooorm/markdown-rs/main/Cargo.toml), [releases](https://github.com/wooorm/markdown-rs/releases)

## 9. Conflicts and attempted refutations

### “cmark-gfm is automatically the best option”

Refutation: it is excellent as a native core, but does not solve Markdown mathematics, internal routes, cross-file composition, or HTML policies. Its advantage holds only if real documents are close to CommonMark/GFM and the project accepts a custom renderer and transformations.

### “GFM is a complete academic standard”

Refutation: GFM provides footnotes and tables, but not bibliographies, semantic citations, includes, equation numbering, or cross-chapter references.

### “KaTeX reproduces enough LaTeX for any thesis”

Refutation: the official table lists unsupported commands, including `\\label`, `\\ref`, and `\\eqref`. MathJax is an alternative for math closer to LaTeX, but increases complexity.

### “Sanitizing Markdown is enough”

Refutation: sanitizing the Markdown tree is insufficient when raw HTML, a math renderer, SVG, CSS, local URLs, or navigation are involved. `rehype-sanitize` should be applied after potentially unsafe transformations.

### “Rendering in the WebView is simpler”

Refutation: it may reduce IPC, but mixes user-controlled content with the surface that loads resources and navigates. Local rendering better separates parsing, permissions, and presentation.

### “The latest tool version guarantees compatibility”

Refutation: versions are misaligned. For example, `rehype-katex 7.0.1` declares a dependency on KaTeX `^0.16.0`, while the observed KaTeX version is `0.18.7`; `rehype-mathjax 7.1.0` declares `mathjax-full ^3.0.0`, while current MathJax documentation is for version 4. This requires compatibility testing and explicit pinning.

## 10. Conditional recommendation

### Preferred option if JavaScript is acceptable

Use a local pipeline:

```text
remark-parse
  + remark-gfm
  + remark-math
  → custom AST transformations
  → remark-rehype
  → KaTeX or MathJax
  → rehype-sanitize
  → final HTML
```

Conditions:

- all packages must be bundled locally;
- versions must be pinned;
- raw HTML must remain disabled or undergo explicit sanitization;
- links and images must be rewritten relative to the Markdown path;
- `.md` links must be intercepted by the viewer;
- choose the math renderer based on the real documents.

Confidence: medium-high for the balance of extensibility, academic content, and security.

### Preferred option if native integration is the priority

Use `cmark-gfm` directly or through `swift-markdown`, with:

- GFM;
- footnotes enabled;
- controlled HTML renderer;
- custom transformation for links and images;
- separate math renderer;
- additional sanitization if raw HTML or rich math is allowed.

Confidence: medium. It is technically viable, but depends on how much custom rendering the MVP is prepared to maintain.

### When to change the recommendation

The recommendation should shift to MathJax or a pipeline closer to LaTeX if the real documents depend on:

- `\\label`, `\\ref`, or `\\eqref`;
- math environments unsupported by KaTeX;
- global equation numbering;
- automatic bibliographic references;
- includes or composition of multiple chapters;
- semantics close to a full LaTeX document.

## 11. Implications for the MVP

Without settling product decisions, the synthesis should consider:

- explicitly declare the supported dialect;
- keep the parser and renderers outside the WebView where possible;
- model document context with an absolute path, base directory, and authorized root;
- treat links, images, and headings as data to transform;
- define an explicit plugin order;
- sanitize after the last unsafe transformation;
- include parsing/math errors as renderable output;
- cancel old renders when a newer change arrives;
- keep artifacts and dependencies in the app bundle;
- avoid CDN or network dependencies during use.

## 12. Gaps and suggested local tests

1. **Academic chapter fixture**
   - headings, blockquotes, tables, footnotes, code blocks, images, and inline/display math;
   - compare `cmark-gfm`, `markdown-it`, `micromark`, and `remark`.

2. **Relative links**
   - Markdown files in subfolders;
   - images with `../`;
   - names with spaces, Unicode, and parentheses;
   - `.md#heading` links;
   - missing files;
   - attempts to escape the project root.

3. **Mathematics**
   - common KaTeX formulas;
   - supported and unsupported environments;
   - `\\label`, `\\ref`, `\\eqref`;
   - large or recursive macros;
   - TeX errors without interrupting the entire preview.

4. **Security**
   - `<script>`;
   - `onclick`, `onerror`;
- `javascript:`, `file:`, `data:`, and `vbscript:`;
   - `<iframe>`;
   - SVG with handlers;
   - raw HTML combined with KaTeX/MathJax;
   - confirm that no document script is executed.

5. **External updates**
   - incremental write;
   - atomic write via a temporary file and rename;
   - several rapid changes;
   - image change without a Markdown change;
   - removal or rename of a related file;
   - an old render finishing after a newer render.

6. **Performance**
   - chapters of 10 KB, 100 KB, and 500 KB;
   - time to first HTML;
   - time to final math output;
   - memory;
   - behavior during successive changes.

7. **Version compatibility**
   - `rehype-katex` with bundled KaTeX;
   - `rehype-mathjax` with the actually resolved version;
   - offline builds without CDN access;
   - native build on Apple Silicon.

## 13. Source ledger

### Used

| Source | Type | Observed version/date | Reason |
|---|---|---|---|
| CommonMark | Specification | 0.31.2, 2024-01-28 | Syntax baseline and standard limitations. |
| GFM | Specification | 0.29-gfm, 2019-04-06 | Tables, footnotes, and GitHub extensions. |
| cmark-gfm | Repository/API/releases | 0.29.0.gfm.13 | Native parser, AST, security, and license. |
| markdown-it | Repository/package/changelog | 15.0.1; changelog 15.0.0 on 2026-07-30 | Direct HTML and extensibility. |
| micromark | Repositories/package | 4.0.2; GFM 3.0.0; math 3.1.0 | Direct parser, extensions, and security. |
| remark/unified | Official repositories | remark 15.0.1; GFM 4.0.1 | AST and transformation pipeline. |
| remark-math | Repository/package | 6.0.0; KaTeX 7.0.1; MathJax 7.1.0 | Mathematics and local rendering. |
| rehype-sanitize | Repository/package | 6.0.0 | Sanitization and transformation ordering. |
| KaTeX | Documentation/package | 0.18.7 | TeX coverage, security, and static HTML. |
| MathJax | Official documentation | version 4 | Coverage and Node processing. |
| Apple WebKit/Foundation | Official documentation | consulted 2026-09-09 | Relative URLs and external changes. |
| Swift Markdown | Repository/package | 0.8.0; Swift tools 6.2 | Native integration and Swift AST. |
| markdown-rs | Repository/Cargo/release | 1.0.0 | Rust alternative. |

### Rejected or used only for discovery

| Source/path | Reason |
|---|---|
| Search snippets and rankings | Not sufficient primary evidence. |
| GitHub stars/watchers | Do not measure suitability, security, or maintenance. |
| `marked` | The `micromark` ecosystem's own comparison says it does not conform to CommonMark/GFM and is unsafe by default; it was not retained as a leading candidate. |
| `swift-markdownkit` | Third-party project; used only for discovery, without sufficient evidence to compete with official options. |
| Unofficial `markdown-it` math plugins | Not compared in depth or treated as equivalent to `remark-math`. |
| Benchmarks published by the parsers themselves | Retained as vendor claims, not independent comparisons. |

## 14. Research log

- Q1 — Read repository instructions, overview, and Markdown → HTML brief. Result: defined criteria and format.
- Q2 — Consult CommonMark and GFM. Result: distinguished the base standard, extensions, and lack of math.
- Q3 — Consult `cmark-gfm`, `markdown-it`, `micromark`, `remark`, and `markdown-rs`. Result: compared ASTs, direct HTML, extensions, and dependencies.
- Q4 — Consult `remark-math`, KaTeX, and MathJax. Result: compared math support, coverage, errors, and security.
- Q5 — Consult `rehype-sanitize` and parser documentation. Result: established sanitization as a separate step.
- Q6 — Consult Apple WebKit/Foundation. Result: identified implications for base URLs, local files, and watchers.
- Q7 — Look for refutations and limitations. Result: confirmed version mismatches, KaTeX limitations, the age of the GFM specification, and lack of bibliographic semantics.

### Reason for stopping

The research reached the requested standard: the main alternatives' official specifications and repositories were consulted, material limitations documented, currently observable versions checked, and tests defined that can only be resolved with real documents and a local prototype.

No tests were implemented and the repository was not changed.

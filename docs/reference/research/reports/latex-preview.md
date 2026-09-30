# Research report: LaTeX → preview

Access date: 2026-09-09.  
Repository context: [research archive](../CONTEXT.md), [LaTeX brief](../latex-preview.md), and [current state](../../../current-state.md).

No files were changed. The working tree was clean.

## 1. Executive summary

For real LaTeX theses, a PDF produced by the LaTeX engine itself is the strategy most likely to preserve visual fidelity, classes, packages, images, bibliography, and cross-references.

The most comprehensive technical setup is a local TeX distribution — TeX Live/MacTeX or MiKTeX — with `latexmk`, using temporary output directories and serialized compilation. `latexmk` detects dependencies through generated files and supports continuous recompilation of sources, included files, and graphics. ([CTAN latexmk](https://ctan.org/pkg/latexmk/), [manual latexmk 4.88](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf))

Tectonic substantially reduces installation effort and packages the engine in one executable, but adds a dependency on bundles/cache, relies primarily on XeTeX, needs special attention to `biber`, and may differ from traditional TeX installations. Version 0.17.0 fixed recent macOS issues, but its recent history makes validation against the actual thesis advisable. ([Tectonic manual](https://tectonic-typesetting.github.io/book/latest/), [release 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0))

HTML is viable, but should not be treated as automatically visually equivalent to PDF. TeX4ht, lwarp, and LaTeXML use different conversion models and may require bindings, specific configuration, or feature replacements. The research found insufficient independent evidence to claim that any of them generally reproduces the appearance of an arbitrary thesis.

## 2. Question and supported decision

The research examined how to process and present local LaTeX on macOS without assuming PDF, HTML, MacTeX, or any specific engine.

The research supports these conditional conclusions:

- PDF is the highest-fidelity option when the goal is to view the original compilation result.
- HTML offers greater potential for structural navigation, search, accessibility, and WebView integration, but carries a higher risk of incompatibilities.
- A traditional TeX installation is more comprehensive; Tectonic is operationally simpler but less neutral toward the TeX ecosystem.
- The final choice depends on the real LaTeX corpus, the thesis engine, and the relative importance of visual fidelity, simple installation, semantic HTML, and accessibility.

This does not settle a product decision.

## 3. Scope and assumptions

Included:

- PDF, HTML, and hybrid approaches;
- TeX Live/MacTeX, BasicTeX, MiKTeX, and Tectonic;
- `latexmk`, `make4ht`, lwarp, and LaTeXML;
- multi-file documents;
- `\\input`, `\\include`, images, bibliography, and references;
- recompilation after external changes;
- logs, errors, warnings, and hung processes;
- temporary directories, shell escape, licensing, and macOS;
- accessibility, selection, and search in the preview.

Out of scope:

- desktop framework;
- specific viewer;
- code implementation;
- LaTeX editor;
- decisions about writing features;
- exhaustive benchmark or validation against a specific private thesis.

## 4. Evaluation criteria

The relevant criteria are:

- visual fidelity to the expected thesis output;
- support for existing classes and packages;
- offline operation;
- installation and external dependencies;
- bibliography and cross-references;
- dependency detection;
- predictability and recompilation time;
- artifact isolation;
- error diagnostics;
- security;
- accessibility and search;
- maintenance and macOS distribution.

No numeric weights were assigned because the project documentation does not define them.

## 5. Claim matrix

| Claim | Importance | Status | Evidence | Limitation |
|---|---:|---|---|---|
| C1. A PDF produced by the original engine is the most direct visual reference. | High | Strong inference | E1, E2, E3 | Does not prove that all viewers display the PDF identically. |
| C2. TeX Live 2026 is available; MacTeX is the macOS distribution based on TeX Live. | High | Fact | E4 | MacTeX is large; BasicTeX is incomplete. |
| C3. MiKTeX offers runtime package installation. | Medium | Fact | E5 | This can make the first compilation network-dependent and less predictable. |
| C4. Tectonic is distributed as a single executable and can obtain support files through bundles. | High | Fact | E6 | Its cache/bundle has offline and reproducibility implications. |
| C5. Tectonic supports `--only-cached`, `--untrusted`, `--outdir`, logs, and dependency files. | High | Fact | E7 | Not all features correspond to options in traditional TeX Live. |
| C6. Tectonic has a `watch` mode that rebuilds when inputs change. | Medium | Fact | E8 | Watch does not mean incremental page composition. |
| C7. `latexmk` tracks the main file, included files, and graphics. | High | Fact | E9 | It still depends on engine and auxiliary-tool behavior. |
| C8. `latexmk` automates multiple passes and tools such as BibTeX/Biber. | High | Fact | E9, E10 | Unusual configurations may require `latexmkrc`. |
| C9. `\\input` and `\\include` support multi-file documents; the compiler needs a root file. | High | Fact/inference | E11, E12 | An isolated chapter may not compile. |
| C10. Bibliography and cross-references require additional processing and more than one pass. | High | Fact | E9, E10, E13 | The exact number of passes depends on the toolchain. |
| C11. Biber and BibLaTeX must use compatible versions. | High | Fact | E13 | The exact combination must be checked in the installation being used. |
| C12. TeX4ht converts through modified LaTeX and an auxiliary DVI. | High | Fact | E14 | This path is not equivalent to the final PDF. |
| C13. make4ht supports output directories, build files, BibTeX/Biber, and post-processing. | Medium | Fact | E15 | The build file itself can introduce dependencies and external commands. |
| C14. lwarp supports many packages and can generate HTML with SVG or MathJax. | Medium | Fact | E16 | It requires Perl and Poppler utilities; it declares itself incompatible with Tagged PDF. |
| C15. LaTeXML produces HTML5, MathML, images, and structured references through bindings. | Medium | Fact | E17 | Coverage depends on bindings; the published version is older. |
| C16. PDFKit on macOS supports display, selection, copying, navigation, and search. | Medium | Fact | E18 | The specific integration belongs in the viewer brief. |
| C17. Accessible PDF depends on tagging and support in the packages used. | Medium | Fact/inference | E19 | The tagging project is still under development. |
| C18. Shell escape is a risk surface and should be disabled by default. | High | Fact/recommendation | E20, E7 | Some documents depend on it, for example for external tools. |
| C19. Tectonic had recent issues specific to macOS ARM64. | High | Limited fact | E21, E22 | The issue was fixed in 0.17.0; it does not prove a general current failure. |
| C20. The final recommendation depends on the actual thesis corpus. | High | Inference | E1–E22 | Only local tests can confirm compatibility. |

## 6. Alternatives investigated

### A. TeX Live/MacTeX + `latexmk` + PDF

Workflow:

1. choose the root file;
2. run `pdflatex`, `xelatex`, or `lualatex`;
3. run BibTeX/Biber/MakeIndex when needed;
4. repeat until references and bibliography have stabilized;
5. display the PDF.

This is the most complete option for an existing thesis. TeX Live includes the engines and tools; MacTeX adds macOS-specific integration. MacTeX 2026 requires macOS 11 or later, supports Intel and Apple Silicon, and the full installer is approximately 6.4 GB. ([MacTeX 2026](https://tug.org/mactex/mactex-download.html), [TeX Live 2026](https://tug.org/texlive/))

Limitations:

- large installation;
- versions and packages depend on the distribution;
- `latexmk` may not be present in minimal installations;
- some packages require Perl, Python, Ghostscript, `dvisvgm`, or shell escape;
- root-file discovery must be addressed.

### B. BasicTeX

BasicTeX includes the main engines but omits many of the packages and tools in the full MacTeX distribution. ([BasicTeX/MacTeX](https://tug.org/mactex/morepackages.html))

It is suitable for testing a small installation, but is less predictable for real theses: a missing package may need to be installed later and change the environment during use.

### C. MiKTeX + PDF

MiKTeX works on macOS and can install missing packages automatically. ([MiKTeX installation on macOS](https://miktex.org/howto/install-miktex-mac))

Advantages:

- smaller initial installation;
- convenient behavior when packages are missing.

Risks:

- the first compilation may depend on the network;
- the result depends on the automatic installation policy;
- the environment may change during compilation;
- the distribution and configuration differ from TeX Live.

### D. Tectonic + PDF

Tectonic is an engine based on XeTeX/TeX Live, distributed as a single executable. It obtains support files through bundles and can keep artifacts outside the source folder. ([Tectonic installation](https://tectonic-typesetting.github.io/book/latest/installation/), [compilation](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Advantages:

- simple primary dependency;
- native support for Unicode and modern fonts through its XeTeX foundation;
- `--only-cached` option to prevent network access;
- `--untrusted` option to disable unsafe features;
- `--outdir`, `--keep-logs`, `--synctex`, and dependency rules.

Risks:

- it is based on XeTeX rather than pdfTeX or LuaTeX;
- compatibility with documents that depend on details specific to other engines is not guaranteed;
- BibLaTeX bibliographies may require external `biber` or `tectonic-biber`, with compatible versions;
- bundles/cache require management;
- external paths and traditional TeX configurations may behave differently.

Current documentation indicates that Tectonic V2 may prefer a `tectonic-biber` executable to avoid incompatibilities between Biber and the bundle's BibLaTeX. ([Tectonic V2 CLI](https://tectonic-typesetting.github.io/book/latest/ref/v2cli.html))

Version 0.17.0, released on 2026-07-27, fixed a `SIGBUS` in `\\setmainfont` calls on macOS and improved watch-mode handling. ([Tectonic 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0))

### E. TeX4ht + make4ht + HTML

TeX4ht is not a fully independent parser: it modifies LaTeX macros, produces an auxiliary DVI, and transforms that output into HTML/XML, MathML, or other formats. ([TeX4ht on CTAN](https://ctan.org/pkg/tex4ht?lang=en), [TeX4ht commands](https://tug.ctan.org/support/TeX4ht/doc/mn-commands.html))

`make4ht` adds:

- output directory;
- build directory;
- build files Lua;
- running BibTeX/Biber;
- image conversion;
- post-processing;
- error detection through the log.

The version checked is 0.4e, dated 2026-02-24. ([make4ht on CTAN](https://ctan.org/pkg/make4ht?lang=en), [make4ht repository](https://github.com/michal-h21/make4ht))

Advantages:

- reuses the LaTeX toolchain;
- supports HTML5, MathML, and multiple files;
- allows detailed customization.

Limitations:

- requires configuration when the thesis uses packages with limited support;
- visual output depends on CSS and image handling;
- the DVI/HTML path may differ from PDF composition;
- there is no official mode equivalent to `latexmk -pvc` for the entire workflow; watching would need to be handled by the application or surrounding architecture.

### F. lwarp + HTML

lwarp also uses LaTeX to generate HTML and declares support for more than 500 packages/classes, MathJax or SVG for mathematics, compilation with LuaLaTeX/XeLaTeX/PDFLaTeX, and integration with `latexmk`. It requires Perl and Poppler utilities. The version checked is 0.922, dated 2026-06-16. ([lwarp on CTAN](https://www.ctan.org/pkg/lwarp), [lwarp documentation](https://mirrors.ibiblio.org/pub/mirrors/CTAN/macros/latex/contrib/lwarp/lwarp.pdf))

Advantages:

- an HTML alternative relatively close to the LaTeX workflow;
- can generate print and HTML versions;
- covers a broad set of packages.

Limitations:

- the package page itself marks “Tagged PDF – incompatible”;
- requires more external tools;
- declared support does not mean fidelity for every document;
- MathJax or SVG may increase preview complexity.

### G. LaTeXML + HTML5/MathML

LaTeXML converts LaTeX to an XML representation and then post-processes it into HTML5, XHTML, MathML, images, bibliographies, and references. It uses specific bindings for classes and packages. ([LaTeXML manual](https://math.nist.gov/~BMiller/LaTeXML/manual/), [conversion](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/), [post-processing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

Advantages:

- stronger focus on semantic structure;
- MathML and HTML5;
- splitting by chapters/sections;
- explicit handling of labels, index, bibliography, and cross-references.

Limitations:

- it is not the engine that composes the PDF;
- missing bindings may require custom development;
- some mathematical conversions are classified as experimental;
- the stable version checked is 0.8.8, released on 2024-02-29. ([LaTeXML 0.8.8 release](https://github.com/brucemiller/LaTeXML/releases/tag/v0.8.8))

## 7. Evidence-based comparison

| Strategy | Visual fidelity | Installation | Offline | Multiple files | Bibliography | Dependencies | Diagnostics |
|---|---|---|---|---|---|---|---|
| TeX Live/MacTeX + latexmk + PDF | Highest, when using the expected engine | Large | Yes, after installation | Strong | Strong | Many possible | Strong |
| MiKTeX + PDF | High | Smaller initially | Conditional | Strong | Strong | May install at runtime | Strong |
| Tectonic + PDF | High for XeTeX-compatible documents | Small | Yes, after preloading the cache | Strong, with path differences | Biber must be validated | Bundle and possible external tools | Good |
| TeX4ht + make4ht | Variable | Medium | Yes | Good | Good, configurable | TeX + converters | Good through logs |
| lwarp | Variable | Medium | Yes | Good | Through LaTeX/latexmk | TeX + Perl + Poppler | Good |
| LaTeXML | Structurally rich, visually variable | More complex | Yes, after installation | Good | Handled in post-processing | Perl/XML/XSLT/bindings | Good |
| PDF converted to images | Visually faithful | Depends on Poppler | Yes | Does not solve compilation | Same as PDF before conversion | PDF converter | Poor for text/search |

The main inference is:

- if “preview” means confirming that the thesis compiled as expected, PDF is the strongest candidate;
- if “preview” means exploring structure, searching, and navigating semantically in a WebView, HTML may be better, but requires accepting a compatibility boundary;
- keeping PDF and HTML in parallel would duplicate the compilation toolchain and failure points.

No sufficiently controlled independent comparison was found to establish general differences in quality, speed, or compatibility among TeX4ht, lwarp, and LaTeXML. These comparisons should be treated as hypotheses to test.

## 8. Dependencies and compilation

### Traditional toolchain

Possible dependencies:

- `pdflatex`, `xelatex`, or `lualatex`;
- `latexmk`;
- BibTeX or Biber;
- MakeIndex, Xindy, or glossary tools;
- image converters;
- TeX fonts or fonts installed on macOS;
- Perl for `latexmk`;
- Python, Pygments, or other tools when required by packages;
- shell escape only when essential.

Web2c documents options such as `-interaction`, `-halt-on-error`, `-output-directory`, and `-recorder`. The recorder writes an `.fls` file listing the files opened by the process. ([Web2c 2026](https://www.tug.org/texinfohtml/web2c.html))

For a process controlled by the application, the technical principles are:

- `nonstopmode` or `batchmode` to prevent interactive prompts;
- `halt-on-error` to stop early on fatal errors;
- `file-line-error` to associate errors with source lines;
- `recorder` to obtain dependencies;
- separate capture of stdout, stderr, and `.log`;
- an external timeout;
- cancel the previous process before starting another for the same root.

`nonstopmode` does not imply success; warnings and recoverable errors must be distinguished from the final result.

### Tectonic

The standalone command supports:

- `--outdir`;
- `--keep-logs`;
- `--keep-intermediates`;
- `--only-cached`;
- `--untrusted`;
- `--synctex`;
- `--makefile-rules`;
- an explicit number of reruns.

In V2 mode, artifacts are placed in a `build` folder by default; intermediates and logs may remain in memory unless requested. ([Tectonic build](https://tectonic-typesetting.github.io/book/latest/v2cli/build.html), [Tectonic compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

The `--only-cached` option matters for the no-cloud requirement: it prevents network connections, but works only when all required files are already available locally.

### HTML

TeX4ht/make4ht and lwarp still run LaTeX and therefore inherit:

- multiple passes;
- bibliography;
- image generation;
- external tools;
- shell escape risks;
- the need for a root file.

LaTeXML adds a second post-processing phase. Its manual describes scanning, indexing, bibliography, cross-references, mathematics, graphics, and XSLT as distinct operations. ([LaTeXML post-processing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

## 9. Multi-file documents

A typical thesis document may look like this:

```text
main.tex
chapters/
  introduction.tex
  methods.tex
  results.tex
figures/
  diagram.pdf
references.bib
```

The application cannot assume that the selected `.tex` file is the root. A chapter included through `\\input` or `\\include` usually has no preamble and cannot compile on its own.

Implications:

- automatic root-file discovery remains an open product/architecture question;
- `\\include` may generate auxiliary files in subdirectories;
- relative paths should remain relative to the root file;
- shared images and bibliographies should be included in the dependency graph;
- symlinks, absolute paths, and files outside the opened folder require an explicit policy.

LaTeXML documents that `\\input` searches for `.tex` and `.sty` files, while `\\include` searches for `.tex`; traditional LaTeX and build tools have their own rules. ([LaTeXML conversion](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/))

## 10. Bibliography and references

`latexmk` is particularly suitable for this scenario because it automates the required passes and detects when BibTeX/Biber needs to run again. ([latexmk README](https://ctan.org/tex-archive/support/latexmk?lang=en))

BibLaTeX 3.22 and Biber 2.22 were released on 2026-08-13. BibLaTeX identifies Biber as its backend, and Biber documents Unicode support and configurable processing. ([BibLaTeX 3.22](https://ctan.org/pkg/biblatex?lang=en), [Biber 2.22](https://ctan.org/pkg/biber/?lang=en))

For the MVP, testing should cover at least:

- classic BibTeX;
- BibLaTeX + Biber;
- global bibliography;
- chapter-level bibliographies;
- unresolved citations;
- updates to the `.bib` file;
- a deliberately incompatible version combination.

With Tectonic, the Biber dependency must be checked separately because the Tectonic bundle and the system-installed Biber may not be compatible.

## 11. Temporary artifacts

Compilation should use a location outside the thesis folder.

Traditional TeX supports `-output-directory`; `latexmk` supports `-outdir` and `-auxdir`, creates missing directories, and documents possible BibTeX/MakeIndex issues when directories are external or absolute. ([latexmk manual, directories](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf))

Tectonic also supports `--outdir`; in V2 it uses a `build` folder by default. ([Tectonic compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Conditional technical recommendation:

- put the PDF, `.aux`, `.log`, `.fls`, `.synctex`, derived images, and bibliography files in a temporary cache folder for each project/root;
- never write artifacts automatically into the source folder;
- associate the result with the root file's absolute path and the compilation toolchain version;
- clear caches only through a controlled operation.

## 12. Updates and concurrency

`latexmk` has a continuous preview mode and tracks source files, includes, and graphics. ([latexmk on CTAN](https://ctan.org/pkg/latexmk/))

Tectonic has `tectonic -X watch`, which watches inputs and rebuilds the document. ([Tectonic watch](https://tectonic-typesetting.github.io/book/latest/v2cli/watch.html))

For `bp-viewer`, this does not eliminate the need for a filesystem architecture:

- the application still needs to know which root file to rebuild;
- nearby events should be grouped;
- an older compilation must not replace the result of a newer change;
- two compilations of the same root must not write to the same artifacts simultaneously;
- a hung compilation needs a timeout and cancellation;
- changes to images, `.bib`, `.sty`, `.cls`, and included files should invalidate the preview.

The existence of `watch` does not demonstrate incremental composition by chapter or page. The documentation describes rebuilding the current document, not partial compilation.

## 13. Errors, warnings, and hangs

The result should distinguish:

- successful compilation;
- a partial PDF generated with warnings;
- a fatal error with no valid PDF;
- a fatal error while an older PDF remains available;
- a process terminated by timeout;
- a process cancelled because of a later change;
- a missing dependency;
- a missing external tool;
- blocked shell escape;
- a process waiting for input.

Useful information includes:

- message;
- severity;
- file;
- line number;
- engine;
- command executed;
- duration;
- distribution version;
- whether an earlier artifact exists.

make4ht documentation confirms that TeX exit codes do not distinguish every error and that the log must be analyzed. ([make4ht, log handling](https://github.com/michal-h21/make4ht))

## 14. Security, permissions, and distribution

TeX Live recommends caution when processing unknown documents because TeX and auxiliary tools can write files and execute commands. ([TeX Live Guide 2026](https://tug.org/texlive/doc/texlive-en/texlive-en.html))

Shell escape should be disabled by default. Tectonic also documents shell escape as unsafe and provides `--untrusted`. ([Tectonic security](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Conditional principles:

- run in a dedicated temporary directory;
- limit read/write paths;
- do not enable `--shell-escape` globally;
- define a per-package/tool allowlist when unavoidable;
- enforce a timeout and process limit;
- do not directly execute commands derived from document content;
- preserve permissions for the folder selected by the user;
- handle files outside the opened folder as an explicit case.

Licensing:

- TeX Live/MacTeX bundle components with individual licenses; distribution within an app requires an inventory;
- `latexmk` uses GPL;
- TeX4ht, make4ht, and lwarp use LPPL;
- Tectonic uses MIT but lists derived components under several licenses;
- Biber uses Perl Artistic License 2.

Sources: [MacTeX licensing](https://tug.org/mactex/aboutmactex.html), [latexmk](https://ctan.org/pkg/latexmk/), [TeX4ht](https://ctan.org/pkg/tex4ht?lang=en), [make4ht](https://ctan.org/pkg/make4ht?lang=en), [lwarp](https://www.ctan.org/pkg/lwarp), [Tectonic LICENSE](https://github.com/tectonic-typesetting/tectonic/blob/master/LICENSE), [Biber](https://ctan.org/pkg/biber/?lang=en).

## 15. Fidelity, accessibility, and search

PDFKit on macOS provides display, selection, copying, navigation, and search for PDF documents. ([PDFKit](https://developer.apple.com/documentation/pdfkit), [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview))

This makes PDF a good fit for:

- preserve the thesis layout;
- copy text;
- search;
- navigate by page;
- handle tables, figures, and notes as produced by the original engine.

Accessibility is not automatic. The LaTeX Tagging Project documents that the current core can generate accessible PDF/PDF-UA-2 in supported scenarios, but support in contributed packages is still evolving. LuaLaTeX has particularly relevant support for associated MathML. ([LaTeX Tagging Project](https://latex3.github.io/tagging-project/documentation/), [using accessible PDF](https://latex3.github.io/tagging-project/documentation/usage-instructions))

HTML can offer:

- heading structure;
- internal links;
- MathML;
- more direct text search;
- navigation by section.

However, it depends on CSS, JavaScript, MathML/MathJax, and the viewer's policy. LaTeXML explicitly documents that MathJax may be needed on platforms without adequate MathML support. ([LaTeXML postprocessing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

## 16. Conditional recommendation

Technical recommendation, not a product decision:

1. First validate a PDF toolchain using the same engine as the thesis, preferably through TeX Live/MacTeX or MiKTeX + `latexmk`.
2. Evaluate Tectonic as a lower-overhead alternative only if the corpus compiles correctly with XeTeX/Tectonic, including bibliography, fonts, paths, and external packages.
3. Evaluate HTML as a separate adapter, not as an implicitly equivalent replacement for PDF.
4. For HTML, first compare TeX4ht/make4ht and lwarp using the real thesis; consider LaTeXML when semantic structure/MathML is an important requirement.
5. Do not enable shell escape by default, and do not assume the user's installation contains every tool.

Confidence:

- traditional PDF: high for fidelity, medium-high for operation;
- Tectonic: medium;
- TeX4ht/make4ht: medium-low without specific testing;
- lwarp: medium-low;
- LaTeXML: medium for structure, low-medium for visual equivalence.

## 17. MVP implications

Without settling decisions:

- the relationship between the selected file and the LaTeX root must be represented;
- the adapter needs a root discovery or configuration phase;
- compilation should be isolated in a temporary location;
- dependencies should include relevant `.tex`, `.bib`, `.sty`, `.cls`, image, font, and intermediate output files;
- processes should be serialized per document;
- the preview should retain the previous result when recompilation fails, if that is the UX decision;
- logs and errors should be handled as structured data;
- the local environment should expose tool versions;
- “works offline” must distinguish an installed distribution, package cache, and external tools.

These are technical implications; they do not constitute approval of new features.

## 18. Gaps and next local tests

Testing should use a temporary location outside the project, for example:

```text
/tmp/bp-viewer-latex-fixtures/
```

### Minimum matrix

1. Minimal document with `main.tex`.
2. `main.tex` with three chapters included through `\\input`.
3. Chapters included through `\\include`, including subdirectories.
4. Cross-references between chapters.
5. BibTeX bibliography.
6. BibLaTeX + Biber bibliography.
7. PNG, JPEG, PDF, and SVG/EPS images where applicable.
8. TikZ/PGFPlots.
9. System font through `fontspec`.
10. Deliberately missing package.
11. Deliberately missing image.
12. Syntax error.
13. Document that requests interactive input.
14. External process that exceeds the timeout.
15. Sequential changes to `main.tex`, a chapter, an image, and `.bib`.
16. Two change events while compilation is in progress.
17. Paths with spaces, Unicode, symlinks, and external files.
18. Offline mode with Tectonic and an incomplete cache.
19. Search and copy text in the PDF.
20. Check headings, links, and MathML in HTML.

### Strategies to compare

For each fixture, record:

- engine and version;
- distribution and version;
- command;
- first compilation;
- recompilation after a change;
- duration;
- number of passes;
- artifacts produced;
- visual result;
- warnings;
- errors;
- offline behavior;
- need for specific configuration.

The goal should be more than “it generates a file”: verify that the result matches the real document and that the toolchain remains controllable after external changes.

## 19. Evidence

### E1 — TeX Live 2026 and macOS

TeX Live 2026 was released on 2026-03-01; MacTeX is the macOS distribution based on TeX Live.  
Sources: [TeX Live](https://tug.org/texlive/), [MacTeX download](https://tug.org/mactex/mactex-download.html).

Establishes: availability, versions, and general compatibility.  
Does not establish: that MacTeX is required for the project.

### E2 — PDF engines

pdfTeX produces PDF directly; XeTeX supports Unicode and modern fonts; LuaTeX supports Unicode, OpenType/TrueType fonts, and Lua.  
Sources: [pdfTeX](https://ctan.org/pkg/pdftex?lang=en), [XeTeX](https://ctan.org/pkg/xetex?lang=en), [LuaTeX](https://ctan.org/pkg/luatex?omit-dependencies=true).

Establishes: documented differences between engines.  
Does not establish: which engine a specific thesis uses.

### E3 — Web2c

Web2c documents `-output-directory`, `-recorder`, `-halt-on-error`, and interaction modes.  
Source: [Web2c manual 2026](https://www.tug.org/texinfohtml/web2c.html).

### E4 — `latexmk`

The version checked is 4.88, dated 2026-03-09. The project documents continuous recompilation, dependencies, bibliography, output directories, and multiple passes.  
Sources: [CTAN latexmk](https://ctan.org/pkg/latexmk/), [README](https://ctan.org/tex-archive/support/latexmk?lang=en), [manual 4.88](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf).

### E5 — Tectonic

Tectonic provides a single executable, bundles, `--only-cached`, `--untrusted`, `--outdir`, logs, and watch mode.  
Sources: [installation](https://tectonic-typesetting.github.io/book/latest/installation/), [compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html), [build](https://tectonic-typesetting.github.io/book/latest/v2cli/build.html), [watch](https://tectonic-typesetting.github.io/book/latest/v2cli/watch.html).

### E6 — Tectonic 0.17.0 and macOS

Release 0.17.0, dated 2026-07-27, records `SIGBUS` fixes on macOS and improvements to watch mode.  
Source: [Tectonic 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0).

### E7 — Recent Tectonic limitation

Issue #1345 reported crashes in Tectonic 0.16.x on macOS ARM64 with `\\setmainfont`; a later release reports the fix.  
Sources: [issue #1345](https://github.com/tectonic-typesetting/tectonic/issues/1345), [release 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0).

Establishes: the need to test specific versions.  
Does not establish: a general current incompatibility.

### E8 — TeX4ht/make4ht

TeX4ht uses modified LaTeX and auxiliary DVI; make4ht adds build files, output directories, bibliography tools, and log parsing.  
Sources: [TeX4ht](https://ctan.org/pkg/tex4ht?lang=en), [commands](https://tug.ctan.org/support/TeX4ht/doc/mn-commands.html), [make4ht](https://github.com/michal-h21/make4ht).

### E9 — lwarp

lwarp 0.922, dated 2026-06-16, supports many packages, MathJax/SVG, latexmk, Perl, and Poppler.  
Source: [lwarp on CTAN](https://www.ctan.org/pkg/lwarp).

### E10 — LaTeXML

LaTeXML 0.8.8 is dated 2024-02-29 and documents bindings, HTML5, MathML, bibliography, cross-references, and splitting.  
Sources: [release](https://github.com/brucemiller/LaTeXML/releases/tag/v0.8.8), [manual](https://math.nist.gov/~BMiller/LaTeXML/manual/), [conversion](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/), [post-processing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/).

### E11 — Bibliography

BibLaTeX 3.22 and Biber 2.22 were released on 2026-08-13; BibLaTeX identifies Biber as its backend.  
Sources: [BibLaTeX](https://ctan.org/pkg/biblatex?lang=en), [Biber](https://ctan.org/pkg/biber/?lang=en), [Tectonic V2 external tools](https://tectonic-typesetting.github.io/book/latest/ref/v2cli.html).

### E12 — Viewer and accessibility

PDFKit documents selection, copying, search, and navigation. The LaTeX Tagging Project documents the current state of accessible PDF and the limitations of package support.  
Sources: [PDFKit](https://developer.apple.com/documentation/pdfkit), [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview), [Tagging Project](https://latex3.github.io/tagging-project/documentation/).

### E13 — Local inspection

No ambiente consultado em 2026-09-09:

- TeX Live 2026 BasicTeX;
- `pdflatex`, `lualatex`, `xelatex`;
- `make4ht`;
- `lwarpmk`;
- Tectonic 0.16.9;
- no `latexmk`;
- no `biber`;
- no LaTeXML;
- no `dvisvgm`.

This is only a local snapshot, not a project requirement.

## 20. Conflicts and counterarguments

- Tectonic's simple installation does not imply compatibility equivalent to full TeX Live.
- “Supports hundreds of packages” in lwarp or an extensive list of LaTeXML bindings does not prove fidelity for the thesis's specific combination of class, macros, and packages.
- HTML with MathML may be structurally better, but requires adequate viewer support and may need MathJax.
- PDF may be searchable and selectable, but is not automatically accessible.
- `watch` in `latexmk` or Tectonic does not solve root discovery, event grouping, or safe cancellation.
- Automatically installing packages reduces initial effort but makes offline behavior less predictable.
- An external benchmark found during research was rejected: its conditions were not verifiable enough to generalize to a private thesis, engines, and the `bp-viewer` corpus.

## 21. Source ledger

### Used

- Local project documentation — primary source for scope and constraints.
- TUG/TeX Live/MacTeX — distribution, versions, and macOS.
- Web2c — execution options and recorder.
- CTAN and author manuals — latexmk, TeX4ht, make4ht, lwarp, BibLaTeX, and Biber.
- Official Tectonic documentation and repository — engine, bundles, watch, security, and releases.
- Official LaTeXML manual and repository — conversion, bindings, and post-processing.
- Apple Developer Documentation — PDFKit.
- LaTeX Project Tagging Project — accessibility and tagging.

### Rejected as primary evidence

- Wikipedia — a secondary source and unnecessary when official documentation was available.
- Reddit and community comments — useful for discovering issues, but not used for material claims.
- Search snippets — not treated as evidence.
- Independent benchmarks without an equivalent corpus/conditions — not generalizable to this case.
- Statements about engine popularity or preference — do not demonstrate technical suitability.

## 22. Search log

- Q1 — current versions of TeX Live, MacTeX, BasicTeX, and MiKTeX.
- Q2 — `latexmk`, dependencies, continuous mode, output/aux directories, and logs.
- Q3 — Tectonic, bundles, cache, security, watch mode, and macOS releases.
- Q4 — TeX4ht and make4ht, HTML, MathML, images, and build files.
- Q5 — lwarp, coverage, engines, MathJax/SVG, and dependencies.
- Q6 — LaTeXML, bindings, bibliography, MathML, splitting, and version.
- Q7 — pdfTeX, XeTeX, LuaTeX, and multi-file input.
- Q8 — BibLaTeX, Biber, and version compatibility.
- Q9 — PDFKit, search, selection, and navigation.
- Q10 — local inventory of tools and versions.

## 23. Reason for stopping

The research covered the strategies, engines, distributions, wrappers, multi-file documents, bibliography, images, recompilation, artifacts, errors, security, licensing, accessibility, and limitations required by the brief.

What remains uncertain is specific to empirical testing: which toolchain compiles the real thesis with sufficient fidelity, which packages need configuration, and what recompilation times are acceptable. Generic documentation cannot resolve this; the local tests described above are required.

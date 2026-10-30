---
bkf: document
description: Manual LaTeX preview check and standalone compilation procedure for a multi-page document with a TikZ include and BibTeX bibliography.
tags: [fixtures, latex, validation]
---

# LaTeX preview validation

Open [`main.tex`](/Fixtures/latex-preview-test/main.tex) in bp-viewer. The document should produce multiple pages and includes a table of contents, cross-references, an equation, a table, lists, links, a TikZ diagram included from [`fixture-diagram.tex`](/Fixtures/latex-preview-test/fixture-diagram.tex), and a BibTeX bibliography in [`references.bib`](/Fixtures/latex-preview-test/references.bib).

To validate outside the app, from this folder:

```bash
WORKSPACE="$(mktemp -d)"
cp main.tex fixture-diagram.tex references.bib "$WORKSPACE/"
cd "$WORKSPACE"
/Library/TeX/texbin/pdflatex -interaction=nonstopmode -halt-on-error main.tex
/Library/TeX/texbin/bibtex main
/Library/TeX/texbin/pdflatex -interaction=nonstopmode -halt-on-error main.tex
/Library/TeX/texbin/pdflatex -interaction=nonstopmode -halt-on-error main.tex
open main.pdf
rm -rf "$WORKSPACE"
```

The command uses classic BibTeX, available in the current installation. It does not require `latexmk`, `biber`, or shell escape. Artifacts are kept in the temporary workspace, not in this directory.

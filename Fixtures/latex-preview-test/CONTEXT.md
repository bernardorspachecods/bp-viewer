# LaTeX fixture context

Open `main.tex` in `bp-viewer`. The document should produce multiple pages and
includes a table of contents, cross-references, an equation, a table, lists,
links, a TikZ diagram included from `fixture-diagram.tex`, and a BibTeX
bibliography in `references.bib`.

Para validar fora da app, a partir desta pasta:

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

The command uses classic BibTeX, available in the current installation. It does
not require `latexmk`, `biber`, or shell escape. Artifacts are kept in the
temporary workspace, not in this directory.

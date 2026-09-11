# Fixture LaTeX para teste manual

Abra `main.tex` no `bp-viewer`. O documento deve produzir várias páginas e
inclui índice, referências cruzadas, equação, tabela, listas, links, um
diagrama TikZ incluído por `fixture-diagram.tex` e bibliografia BibTeX em
`references.bib`.

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

O comando usa BibTeX clássico, disponível na instalação atual. Não requer
`latexmk`, `biber` ou shell escape. Os artefactos ficam no workspace temporário
e não nesta pasta.

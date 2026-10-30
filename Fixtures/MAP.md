---
description: "Manual validation fixtures for Markdown, link, and LaTeX previews: small input files, a local SVG, and a LaTeX project; these corpora contain no personal documents."
---

# Manual preview fixtures

## Task routes

| Task | Start here |
| --- | --- |
| Validate Markdown images and mathematics | [Markdown preview validation](/Fixtures/MarkdownValidation/validation.md) |
| Validate LaTeX preview and compilation | [LaTeX preview validation](/Fixtures/latex-preview-test/validation.md) |
| Validate link navigation | [Link navigation validation](/Fixtures/markdown-link-test/validation.md) |

## Member inventory

<!-- BKF:GENERATED-MEMBER-INVENTORY:START -->
| What it is | Document |
| --- | --- |
| Manual checks for the Markdown preview's local and remote images, common TeX mathematics, and local image updates; the fixture files are test inputs. | [validation.md](/Fixtures/MarkdownValidation/validation.md) |
| Manual LaTeX preview check and standalone compilation procedure for a multi-page document with a TikZ include and BibTeX bibliography. | [validation.md](/Fixtures/latex-preview-test/validation.md) |
| Describes the manual link navigation fixture and its web, text, and CSV targets, which should open outside a BP Viewer preview tab. | [validation.md](/Fixtures/markdown-link-test/validation.md) |
<!-- BKF:GENERATED-MEMBER-INVENTORY:END -->

## Artifact references

- [local-diagram.svg](/Fixtures/MarkdownValidation/images/local-diagram.svg) is the local image loaded by the Markdown preview fixture.
- [main.tex](/Fixtures/latex-preview-test/main.tex) is the multi-page LaTeX preview and compilation input.
- [fixture-diagram.tex](/Fixtures/latex-preview-test/fixture-diagram.tex) is included by the LaTeX fixture as a TikZ diagram.
- [references.bib](/Fixtures/latex-preview-test/references.bib) supplies the LaTeX fixture bibliography.
- [plain-text.txt](/Fixtures/markdown-link-test/plain-text.txt) is a local text target in the link navigation fixture.
- [data.csv](/Fixtures/markdown-link-test/data.csv) is a local CSV target in the link navigation fixture.

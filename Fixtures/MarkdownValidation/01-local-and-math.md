# Markdown validation: local image and mathematics

This fixture validates a relative local image and common mathematical notation
in the `bp-viewer` preview. Open the file from the `Fixtures/MarkdownValidation`
directory.

## Imagem local

![Local validation diagram](images/local-diagram.svg "Local SVG image")

The image above is loaded from `images/local-diagram.svg`, relative to this file.

## Fórmulas inline

Energy: $E = mc^2$. A fraction: $\frac{1}{2}$. Subscripts and operators:
$\alpha_i \leq \beta^2$.

## Fórmula em bloco

$$
\frac{-b + \sqrt{b^2 - 4ac}}{2a}
$$

## Soma com limites

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

## Fixture scope

These formulas use only fractions, roots, subscripts, superscripts, Greek
letters, and operators that the local renderer aims to support. They do not
represent support for arbitrary LaTeX macros.

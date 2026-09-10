# Markdown validation: local image and mathematics

Esta fixture valida uma imagem local relativa e matemática comum no preview do
`bp-viewer`. O ficheiro deve ser aberto a partir da pasta
`Fixtures/MarkdownValidation`.

## Imagem local

![Diagrama local de validação](images/local-diagram.svg "Imagem SVG local")

A imagem acima vem de `images/local-diagram.svg`, relativa a este ficheiro.

## Fórmulas inline

Energia: $E = mc^2$. Uma fracção: $\frac{1}{2}$. Índices e operadores:
$\alpha_i \leq \beta^2$.

## Fórmula em bloco

$$
\frac{-b + \sqrt{b^2 - 4ac}}{2a}
$$

## Soma com limites

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

## Limite desta fixture

Estas fórmulas usam apenas fracções, raízes, índices, expoentes, letras gregas
e operadores que o renderer local pretende suportar. Não representam suporte
para macros LaTeX arbitrárias.

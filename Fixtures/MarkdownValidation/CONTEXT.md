# Contexto de `MarkdownValidation`

Esta fixture cobre renderização de uma imagem SVG local, matemática TeX comum
e uma imagem remota.

- Abra `01-local-and-math.md` na app para validar `images/local-diagram.svg`,
  fórmulas inline e fórmulas em bloco.
- Abra `02-remote-image.md` com internet disponível para validar o recurso
  remoto; offline, a ausência da imagem é um resultado ambiental separado.
- Alterar `images/local-diagram.svg` permite verificar a atualização por
  dependência local.

O registo histórico e as limitações desta fixture estão em
[`docs/reference/markdown-fixtures.md`](../../docs/reference/markdown-fixtures.md).

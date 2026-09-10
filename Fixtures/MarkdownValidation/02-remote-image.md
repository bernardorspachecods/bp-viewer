# Markdown validation: remote image

Esta fixture valida que o preview mantém e tenta carregar uma imagem remota
quando existe ligação à internet.

![Imagem remota de teste](https://placehold.co/640x160/png?text=bp-viewer+remote "Imagem remota")

## Resultado esperado

Com internet, a imagem remota deve aparecer. Sem internet, é aceitável que o
browser mostre a imagem em falta; isso não deve impedir o resto do Markdown de
ser apresentado.

Esta URL não é uma dependência local observada pelo watcher da app.

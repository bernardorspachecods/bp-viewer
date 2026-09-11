# Teste de links Markdown

Usa esta página para confirmar que a app distingue links web de ficheiros
locais que não são visualizados pelo BP Viewer.

## Links externos

- [Abrir example.com](https://example.com)
- [Abrir a documentação Apple](https://developer.apple.com/documentation/webkit)

Ambos devem abrir no browser predefinido do macOS.

## Ficheiros locais não suportados

- [Abrir ficheiro de texto](plain-text.txt)
- [Abrir CSV](data.csv)

Estes devem abrir na aplicação predefinida do macOS, sem criar uma tab de
preview no BP Viewer.

## Checklist

- [x] Link externo abre no browser.
- [x] Segundo link externo abre no browser.
- [x] Ficheiro `.txt` abre na aplicação predefinida.
- [x] Ficheiro `.csv` abre na aplicação predefinida.
- [x] A app permanece aberta e utilizável depois de cada clique.

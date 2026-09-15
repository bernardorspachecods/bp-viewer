# Estado atual da app

`bp-viewer` é uma aplicação macOS nativa para abrir uma pasta local, navegar
pelos ficheiros Markdown e LaTeX e apresentar o resultado renderizado.

## Janela e navegação

- A janela tem topbar, sidebar de projeto, barra de tabs e superfície de
  documento.
- A sidebar abre uma pasta como raiz, mostra a árvore por pastas e ficheiros e
  ignora ficheiros ocultos.
- A árvore carrega o primeiro nível e expande pastas sob pedido. A pesquisa por
  nome ou caminho carrega o índice completo quando necessário.
- O filtro de compatibilidade mostra Markdown e LaTeX por defeito; pode ser
  desligado para mostrar todos os ficheiros.
- A árvore mantém expansão, scroll e filtro por workspace.
- A abertura de uma nova raiz pede confirmação quando já existe um workspace
  aberto.
- Ficheiros `.md`, `.markdown`, `.tex` e `.latex` podem ser abertos em tabs.
  Outros ficheiros são abertos pela aplicação predefinida do macOS.

## Markdown

- `SwiftMarkdownAdapter` converte o conteúdo em HTML seguro para apresentação
  numa `WKWebView`.
- O preview apresenta headings com outline, listas, tabelas, blocos de código,
  links, imagens e matemática TeX comum convertida para MathML.
- Imagens locais existentes são embutidas no HTML e continuam a ser observadas
  como dependências.
- Links Markdown para Markdown e LaTeX abrem ou focam tabs; links para outros
  ficheiros usam o macOS; links externos abrem no browser.
- O preview mantém o último resultado quando uma atualização falha e mostra o
  diagnóstico.
- O documento Markdown pode ser editado na própria superfície visual ou no
  modo de Markdown integral. A edição tem autosave, undo/redo, deteção de
  alterações externas e resolução de conflitos.
- Parágrafos, headings, listas, formatação inline, citações, separadores,
  checkboxes, blocos de código, imagens, tabelas, fórmulas, HTML e front matter
  usam o modelo de edição existente em `BPViewerCore`.

## LaTeX e PDF

- Ao abrir um ficheiro LaTeX, a app procura roots dentro do workspace. Uma root
  única é escolhida automaticamente; zero ou várias roots abrem uma seleção.
- A escolha da root fica guardada por workspace. Um capítulo aberto permanece
  como contexto da tab da root, sem criar uma segunda tab de preview.
- `latexmk` é usado quando está disponível; `pdflatex`, `xelatex` e `lualatex`
  são usados conforme a instalação e o conteúdo do documento.
- A compilação corre num workspace temporário e produz bytes de PDF para a
  superfície `PDFView`.
- Dependências fora do workspace pedem autorização. O modo de `shell escape`
  é configurável e começa desativado.
- O preview mostra erros de compilação, permite expandir e copiar o diagnóstico
  e conserva o PDF anterior quando a compilação atual falha.
- O PDF suporta outline, pesquisa, cópia, impressão, links tratados pela app,
  zoom e restauração da posição de leitura.

## Tabs, preferências e snapshots

- Cada ficheiro tem no máximo uma tab. As tabs podem ser selecionadas,
  reordenadas, fechadas individualmente, fechadas à direita ou fechadas exceto
  a tab escolhida.
- Tabs, tab ativa, contexto LaTeX, tema, largura e visibilidade da sidebar,
  zooms predefinidos, filtro, expansão e posições de leitura são persistidos.
- A app restaura a última pasta existente e remove referências a tabs que já não
  existem.
- O utilizador pode selecionar uma área do preview, incluindo conteúdo obtido
  com auto-scroll, e abrir o recorte numa janela flutuante.
- Snapshots são guardados como PNG em Application Support e permanecem
  disponíveis entre reinícios até serem fechados pelo utilizador.

## Entradas principais do código

- [`Sources/BPViewerApp/CONTEXT.md`](../Sources/BPViewerApp/CONTEXT.md) —
  composição da janela e coordenação da sessão.
- [`Sources/BPViewerCore/CONTEXT.md`](../Sources/BPViewerCore/CONTEXT.md) —
  lógica partilhada de filesystem, Markdown, LaTeX, tabs e edição.
- [`docs/technical/architecture.md`](technical/architecture.md) — fronteiras
  técnicas implementadas.
- [`docs/technical/ui-architecture.md`](technical/ui-architecture.md) —
  composição e estado atuais da UI.

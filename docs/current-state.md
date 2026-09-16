# Estado atual da app

`bp-viewer` é uma aplicação macOS nativa para abrir uma pasta local, navegar
pelos ficheiros Markdown, LaTeX, JSON e PDF e apresentar o resultado renderizado
ou formatado.

## Janela e navegação

- A janela tem topbar, sidebar de projeto, barra de tabs e superfície de
  documento.
- A sidebar abre uma pasta como raiz, mostra a árvore por pastas e ficheiros e
  ignora ficheiros ocultos.
- A árvore carrega o primeiro nível e expande pastas sob pedido. A pesquisa por
  nome ou caminho procura apenas pastas diretamente dentro da raiz, faz scroll
  automático até à primeira correspondência e aplica um highlight, sem filtrar
  a árvore nem percorrer descendentes.
- O filtro de compatibilidade mostra Markdown, LaTeX, JSON, Word e PDF por defeito; pode ser
  desligado para mostrar todos os ficheiros.
- A árvore mantém expansão, scroll e filtro por workspace.
- A abertura de uma nova raiz pede confirmação quando já existe um workspace
  aberto.
- Ficheiros `.md`, `.markdown`, `.tex`, `.latex`, `.json`, `.docx` e `.pdf` podem ser
  abertos em tabs. Documentos Word são convertidos localmente para HTML rico e
  visualizados numa página com fundo e zoom responsivo.
- O preview Word participa na pesquisa comum da tab ativa.
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
- Um duplo clique no preview abre diretamente o editor de source Markdown.
  A edição tem syntax highlighting adaptado aos temas claro/escuro, autosave,
  undo/redo, shortcuts `⌘B`, `⌘I` e `⌘K`, deteção de alterações externas e
  resolução de conflitos.
- O editor pode ocupar a superfície inteira ou funcionar em split view, com o
  source Markdown à esquerda e o preview live à direita.
- `⌘F` abre uma barra de pesquisa comum para previews e editores source. A
  pesquisa fica limitada à tab ativa, ignora maiúsculas/minúsculas e acentos,
  permite avançar/recuar com Enter/Shift+Enter e fecha com Esc. Em split view,
  pesquisa o painel que tem o foco.

## LaTeX e PDF

- Ficheiros PDF existentes podem ser abertos diretamente em tabs e apresentados
  com a mesma superfície PDFKit usada pelo preview LaTeX.

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

## JSON

- Ficheiros `.json` são validados, formatados com indentação estável e
  apresentados numa superfície de leitura monoespaçada.
- Um duplo clique entra num editor raw monoespaçado, com undo/redo, gravação
  explícita apenas para JSON válido e resolução de conflitos externos, sem
  split view.
- O preview JSON suporta seleção/cópia de texto, zoom, snapshots e atualização
  automática quando o ficheiro muda.
- O preview e o editor raw JSON usam a mesma barra de pesquisa da app.
- Rascunhos JSON inválidos podem permanecer abertos no editor, mas não são
  gravados até voltarem a ser válidos; o editor mostra o estado “Não guardado”.
- Ao fechar uma tab com alterações por guardar, a app permite editar, guardar
  ou fechar sem guardar.
- JSON inválido mantém o último preview válido, quando existe, e mostra o
  diagnóstico da validação.

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

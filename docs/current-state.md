# Estado atual da app

`bp-viewer` é uma aplicação macOS nativa para abrir uma pasta local, navegar
pelos ficheiros Markdown, LaTeX, JSON, CSV e PDF e apresentar o resultado
renderizado ou formatado.

## Janela e navegação

- A janela usa tabs nativas do macOS para workspaces. Cada tab nativa
  representa uma pasta e mantém uma topbar, sidebar, árvore e barra de tabs de
  documentos independentes.
- A sidebar abre uma pasta como raiz, mostra a árvore por pastas e ficheiros e
  ignora ficheiros ocultos.
- O botão direito numa pasta permite copiar o caminho, renomeá-la e enviá-la
  para o Lixo. Num ficheiro, o menu também permite renomear, duplicar e enviá-lo
  para o Lixo. Ficheiros e pastas podem ser movidos arrastando-os para uma pasta
  da árvore; a app pede confirmação antes de executar o movimento. Tabs abertas
  acompanham renomeações e movimentos; itens com alterações por guardar não
  podem ser enviados para o Lixo.
- A árvore carrega o primeiro nível e expande pastas sob pedido. Ficheiros
  arrastados para as extremidades laterais da lista são movidos para a root
  aberta, mesmo quando não existe espaço vazio abaixo dos itens. A pesquisa por
  nome ou caminho procura apenas pastas diretamente dentro da raiz, faz scroll
  automático até à primeira correspondência e aplica um highlight, sem filtrar
  a árvore nem percorrer descendentes.
- O cabeçalho permite fechar todas as pastas e limpar os registos de expansão;
  cada pasta de primeiro nível tem a mesma ação disponível ao passar o rato.
- O filtro de compatibilidade mostra Markdown, LaTeX, JSON, CSV, Word, PDF e
  imagens por defeito; pode ser desligado para mostrar todos os ficheiros.
- A árvore mantém expansão, scroll e filtro por workspace.
- O botão de pasta, o `+` nativo e `⇧⌘T` abrem uma nova tab nativa de workspace
  através do seletor de pastas. Workspaces já abertos são focados em vez de
  duplicados; trocar de workspace não fecha tabs nem pede confirmação.
- Ficheiros `.md`, `.markdown`, `.tex`, `.latex`, `.bib`, `.json`, `.csv`, `.docx`,
  `.pdf`, `.png`, `.jpg`, `.jpeg`, `.webp`, `.heic` e `.heif` podem ser abertos
  em tabs. Documentos Word são convertidos localmente para HTML rico e
  visualizados numa página com fundo e zoom responsivo. Imagens são apresentadas
  num preview read-only com moldura/canvas, ajuste à janela, zoom, refresh manual,
  atualização automática quando o ficheiro muda e captura de snapshots.
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
  A edição tem syntax highlighting adaptado aos temas claro/escuro, gravação
  explícita,
  undo/redo, shortcuts `⌘B`, `⌘I` e `⌘K`, deteção de alterações externas e
  resolução de conflitos.
- O editor pode ocupar a superfície inteira ou funcionar em split view, com o
  source Markdown à esquerda e o preview live à direita.
- As alterações Markdown permanecem no rascunho enquanto o editor está aberto;
  `Save` e `Esc` guardam explicitamente e saem do modo de edição, enquanto
  `Discard Changes` repõe a versão guardada e mantém o editor aberto. Alterações
  externas durante a edição abrem o painel de conflito sem gravar
  automaticamente.
- Na barra de ações comum, um documento já guardado não mostra o estado `Saved`
  nem `Discard Changes`; o botão `Save` permanece visível mas desativado.
- Durante a edição, a toolbar disponibiliza um diff com dois modos:
  `Versão guardada no disco`, que compara o rascunho atual com o conteúdo
  existente no ficheiro, e `Git diff`, que compara o rascunho atual com a
  versão `HEAD`. A coluna esquerda é read-only e a coluna direita é o editor
  real; alterações na direita continuam a atualizar o preview Markdown live.
  O diff mantém `undo/redo` no rascunho e não mantém uma lista separada de
  versões históricas.
- No modo `Git diff`, `Discard Git Changes` aparece junto de `Current Draft`
  quando o ficheiro é rastreado e tem versão em `HEAD`. Uma confirmação única
  repõe o ficheiro inteiro para `HEAD`, descartando alterações staged, unstaged
  e o rascunho atual; depois a app mantém o editor aberto e regressa ao modo
  source.
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
- Um duplo clique no PDF LaTeX abre o source contextual (ou o root) com
  números de linha e tenta posicionar o cursor através de SyncTeX; sem mapa,
  abre o editor sem deslocamento.
- Ficheiros `.bib` abertos na árvore usam o root LaTeX do projeto e entram no
  mesmo editor como source contextual; citações podem abrir diretamente a
  entrada correspondente no ficheiro de referências. Um duplo clique numa
  referência impressa no PDF usa o mapa SyncTeX do `.bbl` gerado para abrir
  essa entrada no `.bib`; no título da bibliografia, abre o início do `.bib`.
- O editor LaTeX usa highlighting de comandos, comentários, ambientes,
  argumentos e matemática, com fallback monoespaçado. A toolbar oferece
  source/split view, Undo/Redo, Save, Discard Changes, Disk Diff e Git Diff.
- Em split view, o source editado permanece à esquerda e o PDF à direita.
  Alterações são compiladas após um debounce de dois segundos, em workspace
  temporário, mantendo o último PDF válido durante erros.
- O source contextual pode ser guardado independentemente do resultado da
  compilação. Alterações externas no source abrem conflito; alterações noutras
  dependências apenas recompilam mantendo o rascunho. Diffs e descarte Git
  aplicam-se ao ficheiro contextual.

## JSON

- Ficheiros `.json` são validados e apresentados numa superfície raw read-only
  monoespaçada, preservando exatamente as linhas do ficheiro, incluindo vazias.
  A superfície mostra números de linha.
- Um duplo clique entra num editor raw monoespaçado, com undo/redo, gravação
  explícita apenas para JSON válido e resolução de conflitos externos, sem
  split view.
- O editor JSON disponibiliza os modos de diff `Versão guardada no disco` e
  `Git diff`, com a versão de referência read-only à esquerda e o editor raw
  editável à direita, ambos com numeração de linhas. Linhas adicionadas no
  lado direito têm marcador `+` e destaque verde, tal como num diff Git.
  Ficheiros fora de Git ou sem versão `HEAD` mostram um
  estado explicativo, sem retirar o modo de comparação com o disco.
- No modo `Git diff`, a ação `Discard Git Changes` tem o mesmo comportamento
  destrutivo do editor Markdown: repõe staged, unstaged e rascunho para `HEAD`
  numa única confirmação, mantendo o editor aberto e saindo do diff.
- O preview JSON suporta seleção/cópia de texto, zoom, snapshots e atualização
  automática quando o ficheiro muda.
- O preview e o editor raw JSON usam a mesma barra de pesquisa da app.
- Rascunhos JSON inválidos podem permanecer abertos no editor, mas não são
  gravados até voltarem a ser válidos; o editor mostra o estado “Não guardado”.
- Ao sair do editor JSON com conteúdo inválido, a app permite continuar a editar
  ou descartar as alterações; a opção de guardar só aparece para JSON válido.
- A barra do editor JSON disponibiliza `Discard Changes` para repor a versão
  guardada sem sair do modo de edição.
- Ao fechar uma tab de documento com alterações por guardar, a app permite
  continuar a editar, guardar ou descartar as alterações. Ao fechar uma tab
  nativa de workspace, uma única confirmação permite guardar tudo, descartar
  tudo ou cancelar.
- JSON inválido mantém o último preview válido, quando existe, e mostra o
  diagnóstico da validação.

## CSV

- Ficheiros `.csv` são lidos e apresentados numa tabela de leitura, com suporte
  para campos entre aspas, aspas escapadas, linhas multilinha e separadores
  vírgula, ponto e vírgula ou tab detetados automaticamente.
- O preview CSV apresenta uma grelha tipo folha de cálculo, com letras de
  colunas, números de linhas, célula ativa e navegação por teclado. Um
  duplo-clique permite editar uma célula; `Enter` ou `Esc` confirmam a célula
  no rascunho sem gravar o ficheiro, mantendo disponíveis `Save` e
  `Discard Changes`.
- A barra de edição CSV disponibiliza `Undo` e `Redo`; `⌘Z` desfaz e `⇧⌘Z`
  refaz alterações no rascunho sem gravar automaticamente o ficheiro.
- O preview CSV participa na pesquisa, zoom, snapshots e atualização automática
  quando o ficheiro muda.
- `⌘S` grava as alterações mantendo o separador detetado e aplicando aspas apenas
  quando necessárias. Alterações externas enquanto existe um rascunho mostram
  um conflito com opções para manter o rascunho ou usar a versão externa.

## Tabs, preferências e snapshots

- Cada ficheiro tem no máximo uma tab. As tabs podem ser selecionadas,
  reordenadas, fechadas individualmente, fechadas à direita ou fechadas exceto
  a tab escolhida.
- O botão `+` no fim da barra cria uma tab Markdown nova em memória, sem caminho
  predefinido; o primeiro `Save` abre o painel para escolher o ficheiro `.md`.
- Tabs, tab ativa, contexto LaTeX, tema, largura e visibilidade da sidebar,
  largura e visibilidade do outline por ficheiro, zooms predefinidos, filtro,
  expansão e posições de leitura são persistidos.
- A app restaura todas as tabs nativas de workspaces existentes, na ordem em
  que estavam abertas, foca a última ativa e remove referências a pastas ou
  tabs que já não existem.
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

# Arquitetura de UI atual

## Composição da janela

```text
RootView
└── WorkspaceView
    ├── Topbar
    ├── SidebarView
    │   ├── cabeçalho da pasta
    │   ├── pesquisa e filtro
    │   └── árvore de ficheiros
    ├── tab bar
    └── superfície do documento
        ├── MarkdownPreviewView
        ├── JSONPreviewView
        ├── CSVPreviewView
        ├── LatexPreviewView
        ├── PDFPreviewView
        ├── ImagePreviewView
        └── DocxPreviewView
```

`DocumentOutlineView`, `DocumentDiffView`, `SettingsView` e os overlays de erro, escolha de root,
permissão e mudança de workspace são apresentados pela camada da app. Os
snapshots usam uma janela AppKit separada.

## Estado da UI

`WorkspaceWindowManager` gere as tabs nativas do macOS e mantém um `AppModel`
por janela/tab de workspace. `AppModel` é o `ObservableObject` principal de
cada workspace e publica a raiz, árvore, tabs,
tab ativa, pesquisa, alvo da pesquisa, filtro, expansão, sidebar, zoom, tema,
estado de pesquisa, pedidos de seleção LaTeX e captura de snapshots. A sessão de tabs, persistência
e resolução de documentos vivem no Core; a árvore é mantida por
`WorkspaceTreeSession`; pedidos de renderização, edição e baselines de diff são
tratados, respetivamente, por `DocumentRenderCoordinator`,
`DocumentEditCoordinator` e `DocumentDiffCoordinator`, que devolvem eventos ou
valores aplicados pelo `AppModel`.

Os modelos principais são:

- `DocumentTab` — identidade do ficheiro, tipo, contexto, estado do preview,
  artefacto atual, outline, zoom, posição de leitura, dependências e erro.
- `SourceEditSession` — modo source/split, source base e atual, gravação,
  histórico undo/redo e conflito externo.
- `DocumentDiff` — resultado puro e reutilizável, independente do formato,
  com linhas/hunks, números de linha e referência selecionada.
- `AppState`, `WorkspaceState` e `DocumentState` — estado persistido no Core;
  `WorkspaceSessionCoordinator` gere a sua leitura e escrita.
- `PreviewStatus` — `idle`, `updating`, `ready`, `stale`, `failed`,
  `unavailable`, `cancelled` e `timeout`.

## Superfícies

### Sidebar

`SidebarView` apresenta a raiz aberta, a pesquisa, o filtro de compatibilidade,
o estado de indexação e a árvore lazy. Selecionar um ficheiro pede ao
`AppModel` para abrir ou focar a tab correspondente.
As ramificações expandidas são achatadas em linhas visíveis antes de serem
entregues à `LazyVStack`, para que o scroll não tenha de construir uma view
recursiva com todos os descendentes.
O cabeçalho fecha todas as pastas; em cada pasta de primeiro nível, o mesmo
comando aparece no hover e limpa apenas o ramo dessa pasta.

O menu de contexto usa `WorkspaceFileOperations` para renomear
pastas/ficheiros, duplicar e enviar itens para o Lixo, mantendo tabs abertas
sincronizadas com os novos caminhos. Ficheiros são `draggable` por caminho e as
pastas aceitam `dropDestination`, que executa o movimento apenas dentro da raiz
do workspace. Duas zonas de drop nas extremidades laterais da lista também
representam a root aberta, permitindo devolver um ficheiro à root sem depender
de espaço vazio no fim da árvore.

### Tabs

A tab bar apresenta o nome e o contexto do ficheiro, o estado do preview e as
ações de fecho. O botão `+` cria uma tab Markdown transitória em memória; o
local do ficheiro só é escolhido pelo painel de gravação. A ordenação,
unicidade e tab ativa são mantidas por `DocumentTabSession` no Core, e tabs
transitórias não entram na persistência do workspace.

### Markdown

`MarkdownPreviewView` compõe o HTML, a pesquisa, o outline, o zoom, o estado de
renderização e os erros. A barra de pesquisa comum vive na superfície da tab e
segue o foco entre o editor source e o preview em split view. `MarkdownWebPreview` contém a `WKWebView`, o
JavaScript, a navegação e a posição de leitura. `SourceEditorView` contém o
editor AppKit partilhado por Markdown e JSON. Um duplo clique abre o editor de
source Markdown, cujo syntax highlighting usa uma paleta própria para os temas
claro e escuro; a toolbar alterna entre o editor integral e o split view, que
mantém o source à esquerda e o preview live à direita. O outline é redimensionável
por ficheiro e restaura a largura guardada desse documento.
`DocumentDiffView` é acionada pela toolbar e mantém a referência read-only à
esquerda e o editor real à direita. Pode comparar o disco ou `HEAD`; ao sair,
restaura o modo anterior. Os dois editores partilham o scroll vertical, usando
o mesmo mapa de alturas por linha, para manter as linhas correspondentes
alinhadas enquanto qualquer uma das colunas é deslocada.

### PDF

`PDFPreviewView` apresenta PDFs locais e os artefactos LaTeX em `PDFView`,
controla zoom, pesquisa, outline, posição de leitura, impressão e navegação de
links. A pesquisa comum encaminha as operações para PDFKit.

### Imagens

`ImagePreviewView` apresenta PNG, JPG/JPEG, WebP e HEIC/HEIF num canvas
read-only com cartão, borda e sombra, ajuste automático à janela, scroll para
imagens ampliadas, zoom partilhado da tab, refresh e captura de snapshots.
Alterações no ficheiro ativo provocam nova leitura através do
`DocumentRenderCoordinator`.

### LaTeX

`LatexPreviewView` compõe a toolbar de edição, o editor `NSTextView`, o diff e
o `PDFPreviewView` em split view. O duplo clique no PDF envia página e
coordenadas para `LatexSyncTeXLookup`, que resolve o ficheiro/linha e aplica o
cursor; quando SyncTeX não existe, a entrada no source continua disponível.
Quando SyncTeX devolve uma linha do `.bbl` gerado, `AppModel` usa o conteúdo
guardado desse `.bbl` para encontrar a chave da entrada e abrir o `.bib`.
`SourceEditorView` aplica a paleta `LatexSyntaxColorPalette`. O PDF encaminha
links locais para o router do `AppModel` e links externos para o browser.

### JSON

`JSONPreviewView` apresenta o JSON validado numa superfície raw read-only
monoespaçada selecionável, preservando literalmente as linhas do source,
incluindo vazias, com numeração, zoom e captura de snapshots. Um duplo clique troca para o editor raw
monoespaçado, com undo/redo, gravação explícita apenas para JSON válido,
validação antes de gravar e resolução de conflitos externos; não há split view.
Preview e editor usam a mesma barra de pesquisa e o foco define o alvo. O diff
usa a mesma `DocumentDiffView` que Markdown; o editor AppKit partilhado fornece
o gutter de linhas e as decorações Git-like do lado direito. JSON inválido ao sair do editor
abre uma confirmação para continuar ou descartar.

### CSV

`CSVPreviewView` apresenta os dados numa tabela HTML selecionável, com cabeçalho,
números de linha, scroll horizontal, zoom, pesquisa e captura de snapshots.
Duplo-clique permite editar células existentes; `Enter` confirma, `Esc` cancela
ou confirma a célula no rascunho, e a gravação é feita com `Save` ou `⌘S`.
`Undo`/`Redo` e os atalhos `⌘Z`/`⇧⌘Z` operam sobre o rascunho sem gravar.
Não existem operações para criar/remover
linhas ou colunas.

### Word

`DocxPreviewView` converte o conteúdo rico do `.docx` para HTML local e
apresenta-o numa `WKWebView` com canvas, página branca e magnificação ligada ao
zoom da app. A pesquisa comum encaminha as queries para a WebKit.

### Sistema visual e preferências

`DesignSystem.swift` concentra tokens, botões de toolbar, badges, estados vazios
e controlos reutilizáveis. `SettingsView` altera tema, zooms predefinidos e
modo de `shell escape` através do `AppModel`.

## Interações de nível de janela

`RootView` encaminha comandos para abrir pasta, atualizar o preview, alternar
tema/sidebar, mostrar pesquisa, controlar zoom, selecionar tabs e capturar
snapshots. `WorkspaceWindowManager` cria e agrupa as janelas como tabs nativas,
restaura a ordem dos workspaces e encaminha os comandos globais para a janela
ativa. `AppModel` trata também abertura pelo Finder, drag-and-drop, atalhos de
documentos e confirmação ao fechar uma tab nativa com alterações.

As views não executam diretamente scanners, compiladores ou persistência; enviam
ações ao `AppModel` e renderizam o estado publicado por ele.

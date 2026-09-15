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
        ├── PDFPreviewView
        └── DocxPreviewView
```

`DocumentOutlineView`, `SettingsView` e os overlays de erro, escolha de root,
permissão e mudança de workspace são apresentados pela camada da app. Os
snapshots usam uma janela AppKit separada.

## Estado da UI

`AppModel` é o `ObservableObject` principal e publica a raiz, árvore, tabs,
tab ativa, pesquisa, filtro, expansão, sidebar, zoom, tema, estado de pesquisa,
pedidos de seleção LaTeX e captura de snapshots.

Os modelos principais são:

- `DocumentTab` — identidade do ficheiro, tipo, contexto, estado do preview,
  artefacto atual, outline, zoom, posição de leitura, dependências e erro.
- `MarkdownEditSession` — modo Markdown/split, source base e atual, gravação,
  histórico undo/redo e conflito externo.
- `AppState` — estado persistido global, por documento e por workspace.
- `PreviewStatus` — `idle`, `updating`, `ready`, `stale`, `failed`,
  `unavailable`, `cancelled` e `timeout`.

## Superfícies

### Sidebar

`SidebarView` apresenta a raiz aberta, a pesquisa, o filtro de compatibilidade,
o estado de indexação e a árvore lazy. Selecionar um ficheiro pede ao
`AppModel` para abrir ou focar a tab correspondente.

### Tabs

A tab bar apresenta o nome e o contexto do ficheiro, o estado do preview e as
ações de fecho. A ordenação e a unicidade das tabs são mantidas por
`TabSessionState` no core.

### Markdown

`MarkdownPreviewView` apresenta o HTML na `WKWebView`, a pesquisa, o outline,
o zoom, o estado de renderização e os erros. Um duplo clique abre o editor de
source Markdown; a toolbar alterna entre o editor integral e o split view, que
mantém o source à esquerda e o preview live à direita, além de hospedar
autosave e resolução de conflitos.

### PDF

`PDFPreviewView` apresenta PDFs locais e os artefactos LaTeX em `PDFView`,
controla zoom, pesquisa, outline, posição de leitura, impressão e navegação de
links.

### JSON

`JSONPreviewView` apresenta o JSON validado e formatado numa superfície
monoespaçada selecionável, com zoom e captura de snapshots. Um duplo clique
troca para o editor raw monoespaçado, com undo/redo, autosave, validação antes
de gravar e resolução de conflitos externos; não há split view.

### Word

`DocxPreviewView` converte o conteúdo rico do `.docx` para HTML local e
apresenta-o numa `WKWebView` com canvas, página branca e magnificação ligada ao
zoom da app.

### Sistema visual e preferências

`DesignSystem.swift` concentra tokens, botões de toolbar, badges, estados vazios
e controlos reutilizáveis. `SettingsView` altera tema, zooms predefinidos e
modo de `shell escape` através do `AppModel`.

## Interações de nível de janela

`RootView` encaminha comandos para abrir pasta, atualizar o preview, alternar
tema/sidebar, mostrar pesquisa, controlar zoom, selecionar tabs e capturar
snapshots. `AppModel` trata também abertura pelo Finder, drag-and-drop, atalhos
de teclado e confirmação ao trocar de raiz.

As views não executam diretamente scanners, compiladores ou persistência; enviam
ações ao `AppModel` e renderizam o estado publicado por ele.

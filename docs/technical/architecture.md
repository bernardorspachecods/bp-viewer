# Arquitetura técnica atual

## Organização dos módulos

```text
BPViewerApp
├── AppModel                  intents da UI e coordenação da sessão
├── ActiveDocumentWatcher     adaptação de eventos de ficheiros ativos
├── WorkspaceTreeSession      árvore lazy, filtros e watchers do workspace
├── DocumentRenderCoordinator renders e cancelamento por tab
├── DocumentEditCoordinator  sessões, conflitos e gravação de documentos
├── DocumentDiffCoordinator  baselines de disco/Git e composição do diff
├── RootView / WorkspaceView  composição da janela
├── WorkspaceWindowManager    tabs nativas e modelos por workspace
├── SidebarView               árvore e navegação do workspace
├── MarkdownPreviewView       composição do preview e edição Markdown
├── MarkdownWebPreview        ponte WebKit, JavaScript e navegação Markdown
├── SourceEditorView          editor AppKit, gutter e decorações partilhados
│                             por Markdown, JSON e diff
├── JSONPreviewView           preview JSON raw numerado
├── CSVPreviewView            preview CSV tabular
├── LatexPreviewView          edição LaTeX e split source/PDF
├── LatexSyncTeXLookup        duplo clique PDF → source
├── PDFPreviewView            preview PDF e superfície PDF partilhada
├── ImagePreviewView          preview nativo de imagens raster
├── DocxPreviewView           preview Word através de HTML/WebKit
├── SettingsView              preferências da app
└── SnapshotSupport           seleção e janelas de snapshots

BPViewerCore
├── FileSystemFoundation      nós e scanner
├── SessionModels             modelos puros de sessão e persistência
├── DocumentTabSession        invariantes e transições das tabs
├── WorkspaceSessionCoordinator persistência e sessão de workspace
├── DocumentOpenCoordinator   resolução de documentos e contexto LaTeX
├── MarkdownAdapter            Markdown → HTML
├── MarkdownEditing / Merge   edição e merge de Markdown
├── DocumentDiff              diff puro entre duas fontes de texto
├── CSVAdapter                 parsing e HTML estático para preview CSV
├── MarkdownPreviewLink       resolução de links
├── MathMLRenderer            matemática TeX → MathML
├── LatexRootDiscovery        descoberta de roots
├── LatexAdapter               compilação, overrides e diagnóstico LaTeX
├── LatexSyntaxHighlighter     tokens e paleta de source LaTeX
├── LatexRenderCache           cache de resultados
└── LatexTabContextPersistence contexto de capítulos LaTeX
```

`BPViewerApp` contém a integração macOS e o estado observável. `BPViewerCore`
contém a lógica sem UI usada pela app e pelos runners executáveis. Os targets
`BPViewerContractRunner` e `BPViewerFoundationRunner` exercitam essa lógica
partilhada.

## Coordenação

`AppModel`, isolado no `MainActor`, é o coordenador efetivo da apresentação de
um workspace. `WorkspaceWindowManager` mantém uma instância do modelo por tab
nativa e partilha o coordenador de persistência entre elas. O modelo mantém o
estado observável das tabs e encaminha intents para os módulos de
sessão e para os coordenadores especializados. `DocumentTabSession`
mantém as invariantes das tabs; `WorkspaceSessionCoordinator` concentra
persistência e estado por workspace; `DocumentOpenCoordinator` resolve URLs e
contexto LaTeX; `ActiveDocumentWatcher` adapta eventos Darwin para a UI.
`WorkspaceTreeSession` encapsula o scanning lazy, filtro, expansão e watchers
da árvore; `DocumentRenderCoordinator` encapsula gerações, cancelamento e
renderização; `DocumentEditCoordinator` encapsula undo/redo, validação,
gravação explícita e conflitos; `DocumentDiffCoordinator` seleciona e obtém
baselines sem expor Git à UI. O `DocumentDiffEngine` no Core compara fontes em
memória e devolve um resultado independente de Markdown ou JSON. Estes módulos
devolvem valores e eventos, sem mutar diretamente `AppModel`.

O fluxo principal é:

```text
ação da UI
  → AppModel
    → sessão de workspace / coordinator de render / coordinator de edição
        → scanner / watcher / adapter / process runner
        → DocumentTab e estado SwiftUI
        → preview Markdown, JSON, CSV, PDF ou Quick Look
```

## Filesystem e atualização

- `FileSystemScanner` cria `FileNode` com path absoluto, path relativo, tipo e
  filhos carregados.
- A árvore começa com o nível superior e carrega filhos quando uma pasta é
  expandida. Pesquisar ou desligar o filtro de compatibilidade pode exigir a
  indexação completa.
- Watchers de diretórios atualizam a árvore. Watchers dos ficheiros ativos e das
  dependências invalidam o preview. Durante a edição, uma alteração externa é
  reconciliada como conflito; não dispara autosave Markdown.
- Cada render usa uma geração. Resultados cancelados ou obsoletos não substituem
  o estado mais recente da tab.

## Renderização

O `SwiftMarkdownAdapter` usa `swift-markdown` para produzir HTML próprio. Faz
escaping de texto e atributos, controla esquemas de URL, embebe imagens locais,
recolhe dependências e cria outline e blocos editáveis.

O `LocalLatexAdapter` resolve a root, prepara um workspace temporário (ou uma
overlay quando existe rascunho contextual), executa o compiler através de
`ProcessRunner`, recolhe dependências, valida o PDF produzido e devolve dados
SyncTeX quando disponíveis. O cache é indexado por root, dependências,
compiler e configuração; previews de rascunho não entram no cache.

Imagens suportadas são lidas como bytes e validadas através do ImageIO antes de
serem entregues à superfície nativa. O preview não altera o ficheiro original.

## Persistência e artefactos

- `AppState` é um modelo `Codable` com versão de schema em `SessionModels.swift`.
- `AppStateStore` guarda o estado JSON em `UserDefaults`; o acesso é encapsulado
  por `WorkspaceSessionCoordinator`.
- O estado global guarda tema, sidebar, zooms predefinidos e `shell escape`.
- A lista ordenada de workspaces abertos e o workspace ativo são guardados no
  estado da app para restaurar as tabs nativas ao iniciar.
- O estado por documento guarda zoom, outline e posição de leitura.
- O estado por workspace guarda tabs, expansão, scroll, filtro, seleção de root,
  autorizações externas e registos de snapshots.
- O estado transitório do diff vive apenas na sessão em memória; HTML, PDF,
  logs e conteúdo raw não são usados como estado persistido da sessão.
- Os PNG dos snapshots ficam fora do repositório, em Application Support.

## Limites de segurança

- O HTML Markdown usa uma Content Security Policy local e não habilita scripts
  de conteúdo.
- A app não escreve artefactos de compilação na pasta raw do utilizador.
- Paths de dependências LaTeX são resolvidos e filtrados antes da compilação.
- Dependências fora da raiz exigem confirmação explícita e são observadas depois
  de autorizadas.
- O `shell escape` começa desativado e é uma preferência explícita da app.

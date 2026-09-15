# Arquitetura técnica atual

## Organização dos módulos

```text
BPViewerApp
├── AppModel                  coordenação da sessão e do ciclo de vida
├── RootView / WorkspaceView  composição da janela
├── SidebarView               árvore e navegação do workspace
├── MarkdownPreviewView       preview e edição Markdown
├── PDFPreviewView            preview LaTeX/PDF
├── SettingsView              preferências da app
└── SnapshotSupport           seleção e janelas de snapshots

BPViewerCore
├── FileSystemFoundation      nós, scanner e estado de tabs
├── MarkdownAdapter            Markdown → HTML
├── MarkdownEditing / Merge   edição e merge de Markdown
├── MarkdownPreviewLink       resolução de links
├── MathMLRenderer            matemática TeX → MathML
├── LatexRootDiscovery        descoberta de roots
├── LatexAdapter               compilação e diagnóstico LaTeX
├── LatexRenderCache           cache de resultados
└── LatexTabContextPersistence contexto de capítulos LaTeX
```

`BPViewerApp` contém a integração macOS e o estado observável. `BPViewerCore`
contém a lógica sem UI usada pela app e pelos runners executáveis. Os targets
`BPViewerContractRunner` e `BPViewerFoundationRunner` exercitam essa lógica
partilhada.

## Coordenação

`AppModel`, isolado no `MainActor`, é o coordenador efetivo da aplicação. Ele
mantém a raiz aberta, a árvore, as tabs, os renders, os watchers, a persistência
e as janelas de snapshot.

O fluxo principal é:

```text
ação da UI
  → AppModel
    → scanner / watcher / adapter / process runner
      → DocumentTab e estado SwiftUI
        → preview Markdown ou PDF
```

## Filesystem e atualização

- `FileSystemScanner` cria `FileNode` com path absoluto, path relativo, tipo e
  filhos carregados.
- A árvore começa com o nível superior e carrega filhos quando uma pasta é
  expandida. Pesquisar ou desligar o filtro de compatibilidade pode exigir a
  indexação completa.
- Watchers de diretórios atualizam a árvore. Watchers dos ficheiros ativos e das
  dependências invalidam o preview.
- Cada render usa uma geração. Resultados cancelados ou obsoletos não substituem
  o estado mais recente da tab.

## Renderização

O `SwiftMarkdownAdapter` usa `swift-markdown` para produzir HTML próprio. Faz
escaping de texto e atributos, controla esquemas de URL, embebe imagens locais,
recolhe dependências e cria outline e blocos editáveis.

O `LocalLatexAdapter` resolve a root, prepara um workspace temporário, executa
o compiler através de `ProcessRunner`, recolhe dependências e valida o PDF
produzido. O cache é indexado por root, dependências, compiler e configuração.

## Persistência e artefactos

- `AppState` é um modelo `Codable` com versão de schema.
- `AppStateStore` guarda o estado JSON em `UserDefaults`.
- O estado global guarda tema, sidebar, zooms predefinidos e `shell escape`.
- O estado por documento guarda zoom, outline e posição de leitura.
- O estado por workspace guarda tabs, expansão, scroll, filtro, seleção de root,
  autorizações externas e registos de snapshots.
- HTML, PDF, logs e conteúdo raw não são usados como estado persistido da sessão.
- Os PNG dos snapshots ficam fora do repositório, em Application Support.

## Limites de segurança

- O HTML Markdown usa uma Content Security Policy local e não habilita scripts
  de conteúdo.
- A app não escreve artefactos de compilação na pasta raw do utilizador.
- Paths de dependências LaTeX são resolvidos e filtrados antes da compilação.
- Dependências fora da raiz exigem confirmação explícita e são observadas depois
  de autorizadas.
- O `shell escape` começa desativado e é uma preferência explícita da app.

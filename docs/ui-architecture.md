# Arquitetura de UI

## Objetivo

Definir a estrutura visual, o modelo de estado e as fronteiras entre a UI e os módulos de filesystem/renderização do `bp-viewer`.

Esta arquitetura deve suportar o MVP viewer-only e permitir acrescentar, no futuro, um editor raw à esquerda do preview sem reconstruir o workspace.

O shell atual já usa SwiftUI com pontes AppKit onde necessário. As interfaces
abaixo descrevem a arquitetura-alvo e os contratos de UI; não obrigam os nomes
dos tipos a coincidirem com a implementação atual.

## Princípios

- A UI apresenta estado; não lê ficheiros diretamente nem inicia compiladores.
- O preview é uma superfície que recebe artefactos e diagnósticos, sem conhecer a origem Markdown ou LaTeX.
- A árvore, tabs, preview e futura edição comunicam através de estado e comandos explícitos.
- A complexidade de permissões, watchers, dependências e processos fica atrás de módulos com interfaces pequenas.
- O layout atual deve preencher o espaço disponível sem criar uma dependência estrutural do editor futuro.
- O sistema visual usa tokens e primitivas reutilizáveis; estilos locais hardcoded não são a fonte normal de UI.
- A arquitetura é nativa de macOS e a implementação atual usa SwiftUI/AppKit; detalhes de integração continuam sujeitos a validação local.

## Estrutura da janela

```text
MainWindow
├── AppShell
│   ├── TopBar
│   ├── ProjectSidebar
│   │   ├── FolderHeader
│   │   ├── TreeSearch
│   │   └── FileTree
│   └── DocumentWorkspace
│       ├── TabBar
│       └── DocumentSurface
│           ├── EditorPane       (futuro)
│           └── PreviewPane
└── GlobalOverlays
    ├── ErrorDetails
    ├── RootSelection
    └── PermissionPrompt
```

No MVP, o `EditorPane` não está presente e o `PreviewPane` ocupa todo o `DocumentSurface`.

Quando o editor for adicionado, o workspace passa a suportar:

```text
DocumentWorkspace
├── TabBar
└── DocumentSurface
    ├── EditorPane
    └── PreviewPane
```

A `ProjectSidebar` continua a ser a navegação do projeto; não deve ser confundida com o editor.

## Módulos de UI

### `AppShell`

Responsável por compor a janela, encaminhar comandos globais e manter o layout persistível.

Deve conhecer:

- tema atual;
- tamanho e posição da janela;
- largura e visibilidade da sidebar;
- workspace ativo;
- comandos de menu e atalhos.

Não deve conhecer parsing Markdown, compilação LaTeX ou detalhes de permissões.

### `TopBar`

Apresenta ações globais e do documento ativo, incluindo conforme o contexto:

- abrir pasta;
- toggle de compatibilidade da árvore;
- tema claro/escuro;
- atualização/recompilação;
- pesquisa do preview;
- zoom;
- outline quando disponível;
- estado resumido de atualização ou erro.

Os controlos devem enviar comandos ao workspace, não alterar diretamente adapters ou processos.

### `ProjectSidebar`

Apresenta a sessão de projeto e a árvore de ficheiros.

Inclui:

- pasta-raiz atual;
- pastas recentes e ação de abrir pasta;
- pesquisa por nome/caminho;
- toggle de ficheiros compatíveis;
- árvore ordenada;
- estados de acesso bloqueado, ficheiro removido e pasta vazia.

A sidebar pode ser redimensionada ou escondida. A seleção de um ficheiro pede ao workspace para abrir ou focar uma tab.

### `TabBar`

Apresenta documentos abertos, tab ativa, estado resumido e ações de fecho.

Cada tab referencia um documento; não contém uma cópia do conteúdo raw.

Quando duas tabs tiverem o mesmo nome, apresentam contexto da pasta-pai. Para LaTeX, a tab representa o documento de preview/root e pode manter o capítulo selecionado como contexto.

### `DocumentSurface`

É o ponto de extensão do workspace para superfícies de documento.

No MVP, renderiza apenas `PreviewPane`. No futuro, compõe editor e preview sem obrigar a mudar o modelo de tabs, sessão ou coordenação de renderização.

### `PreviewPane`

Recebe um estado de preview aprovado pelo `WorkspaceCoordinator`:

- HTML renderizado;
- PDF compilado;
- estado de atualização;
- diagnóstico;
- possibilidade de preview válido desatualizado;
- posição de leitura e zoom.

Não deve saber se o artefacto veio de Markdown, LaTeX ou de um teste fake.

### `GlobalOverlays`

Contém estados que exigem decisão explícita sem destruir o workspace:

- escolha entre roots LaTeX;
- confirmação de dependência fora da raiz;
- recuperação de permissão;
- detalhes completos de erro;
- confirmação ao trocar de pasta com tabs abertas.

## Modelo de estado

O estado deve ser separado por responsabilidade, mesmo que a implementação inicial use um store coordenador.

### `AppState`

- tema;
- tamanho/posição da janela;
- largura e visibilidade da sidebar;
- pastas recentes;
- versão do esquema de preferências.

### `ProjectState`

- referência da pasta-raiz;
- estado de acesso;
- snapshot da árvore;
- filtro de ficheiros compatíveis;
- pesquisa da árvore;
- seleção atual;
- estado expandido/fechado das pastas.

### `TabState`

- identidade do documento;
- referência do ficheiro;
- root e contexto LaTeX, quando aplicável;
- sequência da sessão e documento ativo;
- posição de leitura;
- zoom;
- estado de preview;
- diagnóstico atual e último preview válido.

### `RenderState`

Cada tab deve poder representar independentemente:

```text
idle
updating
ready
stale
failed
unavailable
cancelled
timeout
```

O estado deve incluir geração/revisão suficiente para impedir que um resultado antigo substitua um resultado mais recente.

## Coordenação e fronteiras

```text
UI command
    ↓
WorkspaceCoordinator
    ├── ProjectSession / FileSystemGateway
    ├── SnapshotIndex / DependencyIndex
    ├── RenderCoordinator
    │   ├── MarkdownAdapter
    │   └── LaTeXAdapter
    └── PreviewSink
         ↓
     UI state
```

### `WorkspaceCoordinator`

É o módulo profundo que traduz ações de UI em transições de workspace:

- abrir/focar/fechar tabs e atualizar a sessão;
- selecionar ficheiros;
- abrir ou trocar a pasta-raiz;
- encaminhar refresh/recompile;
- pedir resolução de root LaTeX;
- reagir a alterações externas;
- publicar estados de atualização, erro e preview válido.

A UI não deve duplicar esta lógica em cada componente visual.

### `FileSystemGateway`

É a única interface usada pela UI para listar, ler, obter metadata e resolver recursos autorizados.

Paths, bookmarks e permissões não devem circular como lógica espalhada por views.

### `RenderCoordinator`

Recebe pedidos de renderização por documento/root e devolve resultados identificados por geração.

É responsável por debounce, cancelamento, fila, publicação apenas do resultado atual e associação do diagnóstico à tab correta.

### `PreviewSink`

Traduz artefactos aprovados em estado consumível pela superfície de preview. A sua interface deve aceitar HTML, PDF e diagnósticos sem obrigar a UI a conhecer o adapter.

## Sistema visual

O sistema visual deve ser definido antes de espalhar estilos pela app.

### Tokens

Devem existir tokens para:

- cores de fundo, superfície, texto, secundário, foco, seleção, erro, aviso e sucesso;
- tipografia e hierarquia de títulos;
- espaçamento;
- tamanhos de controlos;
- raios, bordas e separadores;
- elevação/sombras, se usadas;
- estados claro e escuro.

### Primitivas

As primeiras primitivas reutilizáveis devem cobrir:

- botão de toolbar;
- item de menu/contexto;
- tab;
- linha da árvore;
- badge de estado;
- painel de erro;
- estado vazio;
- indicador de loading;
- split pane;
- content container do preview.

Uma primitiva só deve existir quando tiver comportamento ou estilo partilhado real. Não criar uma camada genérica de componentes apenas para esconder markup simples.

### Regras de consistência

- estados equivalentes usam as mesmas cores, ícones e linguagem;
- ações destrutivas ou externas têm confirmação explícita quando definido em `vision.md`;
- espaçamento e alinhamento vêm de tokens;
- componentes não definem cores e dimensões arbitrárias localmente;
- o preview pode ter estilos próprios de conteúdo, mas a moldura e os controlos pertencem ao sistema visual da app.

## Persistência local

Não é necessária uma base de dados.

Uma camada de preferências local deve guardar apenas estado pequeno e reconstruível:

- referências persistentes a raízes autorizadas;
- tabs e ordem;
- root/contexto LaTeX;
- posição de leitura e zoom;
- tema;
- expansão da árvore;
- tamanho da janela e sidebar;
- versão do esquema para migrações futuras.

Conteúdo raw, HTML, PDF e logs não devem ser tratados como estado persistido da UI.

## Decisões abertas de implementação

Esta especificação fecha a forma da UI, mas não escolhe ainda:

- detalhes da fronteira entre SwiftUI e AppKit e dos serviços nativos;
- mecanismo concreto de persistência de bookmarks;
- arquitetura exata do store/coordenador;
- biblioteca de WebView/PDF além das superfícies nativas a validar;
- refinamentos do design system depois da próxima ronda visual, sem quebrar os tokens e primitivas existentes.

As lacunas restantes devem ser fechadas por testes locais e pelo plano técnico,
não por preferência abstrata. O primeiro protótipo visual já foi ultrapassado:
o estado implementado e a validação atual vivem em
[`technical-plan.md`](technical-plan.md).

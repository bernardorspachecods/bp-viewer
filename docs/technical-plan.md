# Plano técnico inicial

Este documento transforma a [visão atual](vision.md) e a [síntese da pesquisa](research/synthesis.md) num plano de prototipagem e implementação. Não altera decisões de produto, não escolhe definitivamente uma stack que a pesquisa deixou aberta e não substitui validação no Mac com a tese de Bernardo.

## Como ler este plano

Cada afirmação usa uma destas categorias:

- **Requisito confirmado** — vem de `docs/vision.md`; deve orientar o MVP.
- **Recomendação técnica** — inferência apoiada pela síntese/reports, com confiança e trade-offs explícitos; ainda não é uma decisão de Bernardo.
- **Decisão aberta** — não há evidência suficiente para fechar; o plano indica o teste que deve reduzi-la.
- **Validação local** — só pode ser resolvida com protótipo, instalação e ficheiros reais.

As referências apontam primeiro para a síntese. Os reports individuais são citados apenas onde suportam um detalhe material: [desktop e filesystem](research/reports/desktop-filesystem.md), [Markdown → HTML](research/reports/markdown-html.md), [LaTeX → preview](research/reports/latex-preview.md) e [preview, segurança e distribuição](research/reports/preview-security-distribution.md).

## Estado de implementação — 2026-09-10

O shell nativo e o primeiro vertical slice de Markdown já estão implementados:

- `swift-markdown` é o parser provisório;
- o adapter gera HTML próprio, com escaping de texto/atributos e rejeição de esquemas de URL perigosos;
- raw HTML é omitido nesta primeira versão até existir uma política de sanitização testada;
- o HTML é apresentado num `WKWebView` com JavaScript de conteúdo desligado;
- a tab Markdown lê o ficheiro fora da UI, publica apenas a geração mais recente e observa alterações do ficheiro ativo;
- erros mantêm o último preview disponível e mostram o diagnóstico;
- a árvore indexa inicialmente apenas o primeiro nível, carrega pastas sob pedido e mostra progresso durante indexação/pesquisa;
- links Markdown internos para `.md`/`.tex` focam ou abrem tabs, enquanto links externos passam para o browser do macOS;
- o preview já oferece pesquisa `⌘F`, zoom persistido e MathML local para a sintaxe TeX comum;
- imagens locais do Markdown entram nas dependências observadas para atualização automática;
- o adapter Markdown vive num módulo core partilhado com um contract runner executável;
- as fundações de filesystem, árvore lazy, filtros, pesquisa, tabs e restauração vivem num módulo core partilhado com um foundation runner executável;
- matemática TeX avançada, links internos fora da raiz, dependências transclusivas e LaTeX continuam fases seguintes.

Esta implementação é deliberadamente provisória: a escolha do parser, a política completa de recursos e o watcher de dependências só ficam fechados depois de testar a tese real.

### Estado de validação automática

Existem dois runners executáveis que podem ser corridos sem abrir uma janela:

- `BPViewerContractRunner`: 11 contratos do adapter Markdown, incluindo links,
  imagens, dependências, CSP, HTML raw e matemática TeX comum;
- `BPViewerFoundationRunner`: 31 contratos de scanner, árvore lazy, filtro,
  pesquisa, tabs e restauração/persistência em formato puro.

Os 42 contratos passam após a integração do commit `1932d32`. A suite
`swift test` ainda não corre no CommandLineTools atual porque o target existente
usa o módulo `Testing`, que não está disponível nesse toolchain. Esta limitação
não invalida os runners, mas deve ser resolvida ou aceite explicitamente antes
de depender da suite standard como gate de CI.

Continuam sem cobertura automática de integração: SwiftUI/AppKit, entrega de
eventos de UI, WKWebView, atalhos, ciclo de vida assíncrono da `AppModel`,
`UserDefaults` real, callbacks dos watchers, renames concorrentes e performance
em árvores grandes. Esses pontos passam para a ronda de teste real da app,
começando por UI manual contigo; os casos determinísticos de watchers e
gerações devem ser extraídos para seams testáveis antes de fechar a fase de
Markdown.

### Backlog de testes automáticos após a ronda de UI

Esta é a lista explícita de cobertura que ainda falta automatizar. Não é um
bloqueio para começar a validar a UI manualmente, mas deve ser tratada antes de
considerar o shell e o Markdown suficientemente estabilizados:

- eventos SwiftUI/AppKit, incluindo cliques, foco, seleção e redimensionamento;
- carregamento e navegação do `WKWebView`;
- atalhos de teclado, incluindo tabs, pesquisa, zoom, refresh e fecho;
- watchers perante alterações, renames, remoções e substituições atómicas;
- tarefas assíncronas, debounce, cancelamento e `generation guards`;
- persistência real com `UserDefaults` isolado e restauração após reinício;
- comportamento e responsividade em árvores grandes.

Cada item deve ter pelo menos um teste de regressão reproduzível. Onde a
framework de UI não permitir um teste unitário simples, usar um teste de
integração ou um seam/fake determinístico; não transformar um teste manual
único numa garantia automática.

### O que Bernardo deve validar manualmente antes de LaTeX

Na próxima ronda, a validação deve usar pastas e ficheiros reais e concentrar-se
no comportamento que os runners não conseguem provar:

1. Abrir a pasta da tese ou uma cópia controlada e confirmar que a árvore fica
   utilizável, sem bloqueios ou atrasos anormais.
2. Pesquisar nomes e caminhos em árvores pequenas e grandes; confirmar que o
   indicador de pesquisa aparece, que os resultados não ficam obsoletos e que a
   árvore mantém os ancestrais corretos.
3. Expandir e fechar muitas pastas, alternar o filtro de compatíveis e confirmar
   que não desaparecem ficheiros `.md` ou `.tex` válidos.
4. Abrir várias tabs, trocar entre elas, fechar a ativa, fechar as restantes e
   reabrir a app; confirmar ordem, tab ativa e ausência de duplicados.
5. Testar tema, sidebar, largura da sidebar, zoom, pesquisa `⌘F`, seleção/cópia
   e os atalhos atualmente implementados.
6. Alterar externamente um Markdown enquanto está aberto, incluindo alterações
   rápidas sucessivas; confirmar atualização, debounce e ausência de preview
   antigo a substituir o novo.
7. Introduzir temporariamente um erro Markdown e confirmar que aparece o erro,
   que o último preview válido pode ser identificado como desatualizado e que a
   recuperação funciona depois de corrigir o ficheiro.
8. Alterar, remover e restaurar uma imagem local referenciada pelo Markdown;
   confirmar que o preview acompanha a dependência.
9. Testar links internos Markdown, links externos e links para ficheiros não
   suportados, verificando que cada ação abre o destino esperado.
10. Confirmar que a app continua estável ao alternar rapidamente entre tabs,
    atualizar, pesquisar e alterar ficheiros externamente ao mesmo tempo.

Deve ser registado para cada ponto: `passou`, `falhou` ou `não aplicável`, com
uma nota curta e, quando houver falha, os passos para reproduzir. Só depois
desta ronda devemos decidir se há correções de Markdown/UI suficientes para
implementar o adapter LaTeX.

## 1. Requisitos e decisões de produto já confirmados

Esta secção não propõe tecnologia. Regista o que a implementação deve respeitar.

### 1.1 Produto e fronteiras

- O produto é uma aplicação desktop pessoal para macOS.
- O MVP é macOS-first, sem compromisso com Windows ou Linux.
- A app navega numa pasta local, mostra uma árvore e apresenta previews renderizados de Markdown e LaTeX.
- O MVP não edita os ficheiros raw, não depende de um LLM, não usa cloud, contas ou base de dados.
- Os ficheiros raw continuam fora do controlo de edição da aplicação.
- O primeiro alvo é a tese atual de Bernardo, não compatibilidade genérica com qualquer projeto LaTeX.
- A distribuição inicial é para uso pessoal fora da App Store, por build local ou pacote direto.
- O alvo inicial é a versão atual do macOS; não há compromisso com versões antigas.

Fontes: [vision.md — Objetivo, Escopo do MVP, Fora do escopo inicial e Decisões confirmadas](vision.md); [synthesis — Estado atual](research/synthesis.md).

### 1.2 Navegação, raiz e árvore

- O utilizador pode abrir qualquer pasta como raiz.
- A árvore mostra a raiz e descendentes, com toggle para ficheiros compatíveis — `.md` e `.tex` — ou todos os ficheiros.
- Com o filtro ativo, pastas sem descendentes compatíveis ficam ocultas; a resolução interna de dependências não fica limitada pelo filtro.
- Pastas aparecem antes de ficheiros e ambos são ordenados alfabeticamente.
- A raiz começa expandida; as restantes pastas começam fechadas, e o estado expandido/fechado é restaurado.
- A árvore suporta teclado, pesquisa por nome/caminho, drag & drop, abertura a partir do Finder e menu contextual.
- Ficheiros/pastas sem acesso continuam visíveis com indicação de acesso bloqueado.
- Ficheiros ocultos ficam escondidos por defeito.
- Clicar numa pasta apenas expande/fecha; não muda o preview ativo.
- Ativar uma tab torna o ficheiro correspondente visível na árvore.

### 1.3 Preview e atualização

- O MVP apresenta apenas preview; não inclui editor.
- Alterações externas atualizam automaticamente com debounce.
- A UI mostra estados de atualização, atualizado e erro.
- Em erro, mostra os detalhes por defeito; o utilizador pode pedir o último preview válido, claramente marcado como desatualizado.
- Deve tentar preservar a posição de leitura e mostrar quando o preview foi atualizado.
- Markdown suporta matemática delimitada, imagens locais e imagens remotas. Imagens remotas podem falhar offline; a utilização normal pressupõe ligação à internet.
- HTML raw é permitido somente depois de sanitizado.
- Links `.md`/`.tex` dentro da pasta aberta focam ou abrem tabs; links locais para ficheiros não suportados e links externos abrem o programa/browser normal apenas por ação explícita.
- LaTeX aparece como PDF compilado dentro da app, em scroll contínuo por defeito.
- O preview oferece tema claro/escuro, pesquisa apenas na tab ativa, zoom, outline quando disponível, seleção/cópia e atualização manual (`⌘R` incluído).
- `⌘W` fecha a tab ativa sem fechar a janela e `Control-Tab` avança pelas tabs com wrap-around.

### 1.4 LaTeX e tabs

- Ao abrir `.tex`, a app tenta identificar o root e compilar o documento completo.
- Zero ou múltiplos candidatos exigem escolha do utilizador; a escolha é memorizada por projeto e pode ser alterada.
- A abertura de `.tex` inicia compilação automaticamente.
- O MVP usa instalação local de LaTeX; a app não inclui o compilador.
- `biber`, TikZ/PGFPlots, fontes especiais, `shell escape` e ferramentas externas podem existir na tese e precisam de validação com ficheiros reais.
- Dependências LaTeX fora da raiz exigem confirmação explícita.
- Alterações em capítulos/dependências recompilam o root; não se assume compilação segura de páginas isoladas.
- Abrir um capítulo LaTeX foca a tab do documento principal, sem tab duplicada do capítulo.
- Há várias tabs; cada ficheiro tem no máximo uma tab aberta. A restauração preserva referências, ordem, tab ativa, posição de leitura, tema, janela e largura da sidebar.
- O estado persistido guarda referências, não cópias de conteúdo.

### 1.5 Implicações de arquitetura que já são requisitos

- A UI deve separar visualização de edição futura.
- Alterar outra pasta com tabs abertas exige confirmação.
- Fechar a app não pode ficar bloqueado por compilação ativa.
- A recompilação deve agrupar alterações, analisar dependências, cancelar trabalhos obsoletos e reutilizar cache, sem apresentar isso como compilação incremental por página.
- Configurações avançadas de LaTeX devem existir no MVP numa área discreta, mantendo o fluxo normal simples.

## 2. Arquitetura técnica recomendada

### 2.1 Forma geral

**Recomendação técnica — confiança média-alta:** separar shell, sessão/permissões, filesystem, watcher, índice de dependências, adapters, coordenação de render, processos e superfícies de preview. Esta separação é a recomendação central de [synthesis — Decisões acionáveis](research/synthesis.md) e [desktop e filesystem — Contratos entre componentes](research/reports/desktop-filesystem.md).

```text
App shell macOS
  ├── ProjectSession + persistência local
  ├── FileSystemGateway + SnapshotIndex
  ├── FileWatcher ─────────────┐
  ├── DependencyIndex           │ invalida
  ├── RenderCoordinator ◄───────┘
  │     ├── MarkdownAdapter  ──► HTML Preview
  │     └── LaTeXAdapter     ──► PDF Preview
  └── Preview surfaces + estado por tab
```

O shell não deve permitir que a UI leia paths livremente ou lance compiladores. O watcher não deve transportar “conteúdo final”; apenas invalida snapshots. O adapter não deve assumir que o artefacto é sempre HTML ou PDF.

### 2.2 Shell nativo macOS e divisão SwiftUI/AppKit

**Requisito confirmado:** `vision.md` privilegia uma app nativa macOS.

**Recomendação técnica — confiança média:** usar uma divisão híbrida, caso o protótipo confirme que SwiftUI cobre a composição normal da interface:

- **SwiftUI:** cena/janela, sidebar, árvore, tabs, topbar, estados de loading/erro, comandos (`⌘O`, `⌘W`, `⌘R`, `⌘1–⌘9`, `⌘F`) e bindings de estado.
- **AppKit/Foundation:** `NSOpenPanel`, eventos de abertura do Finder, bookmarks/security scope, FSEvents ou ponte para o watcher, `Process`, permissões, integração de `WKWebView`/`PDFView`, menus e detalhes de ciclo de vida que exijam APIs macOS.
- **Fronteira:** serviços AppKit/Foundation expõem contratos orientados a sessão, paths relativos, batches, artefactos e diagnósticos; a UI não conhece detalhes de permissões nem comandos externos.

Isto não significa que SwiftUI ou AppKit esteja escolhido isoladamente. O report desktop favorece shell nativo quando a prioridade é integração macOS e permissões persistentes, mas não fornece benchmark comparativo nem prova que a divisão proposta seja a mais produtiva. A decisão deve ser testada com uma janela que abra uma pasta, restaure estado, mostre uma WebView/PDFView e execute um processo controlado ([synthesis — Matriz de decisões](research/synthesis.md); [desktop — Alternativas e recomendação condicional](research/reports/desktop-filesystem.md)).

**Trade-offs:** SwiftUI simplifica estado e composição moderna; AppKit oferece controlo mais direto das APIs legadas/nativas. Uma ponte excessiva pode tornar o estado difícil de seguir; APIs nativas diretamente espalhadas na UI anulam a separação.

### 2.3 Contratos internos

Os nomes abaixo são contratos de plano, não APIs finais:

| Componente | Responsabilidade | Invariante |
|---|---|---|
| `ProjectSession` | raiz atual, bookmark/referência, estado de acesso, projeto e configurações persistidas | o estado de autorização nunca é inferido apenas de uma string de path |
| `FileSystemGateway` | listar, enumerar, ler, metadata, resolver relativo, testar existência/tipo | a UI só acede paths autorizados através deste gateway |
| `SnapshotIndex` | visão atual da árvore, metadata e estado de acesso | eventos só atualizam o snapshot depois de re-scan/validação |
| `FileWatcher` | batches de alterações, sequência e escopo de re-scan | eventos podem ser duplicados, incompletos ou apontar para paths já inexistentes |
| `DependencyIndex` | dependências, referências não resolvidas e documento/root afetado | filtro visual da árvore não limita dependências do adapter |
| `RenderCoordinator` | gerações, debounce, filas, cancelamento e publicação | uma geração antiga nunca substitui a mais recente |
| `ProcessRunner` | processos, argumentos, ambiente, stdout/stderr, timeout e cancelamento | “terminou” não significa “artefacto válido” |
| `PreviewSink` | publicação de HTML/PDF e diagnósticos por tab/generation | rejeita updates de gerações antigas |

## 3. Filesystem, sessão, bookmarks e árvore

### 3.1 Sessão e persistência de acesso

**Requisito confirmado:** abrir uma raiz, reabrir o projeto e confirmar dependências fora da raiz.

**Recomendação técnica — confiança alta para o modelo, média para o mecanismo final:** `ProjectSession` deve guardar uma referência persistível à raiz — normalmente um security-scoped bookmark quando o modelo de permissões o exige — e estados explícitos `available`, `permissionLost`, `rootMoved`, `closed` e `stale`. Ao iniciar uma sessão, resolver a referência, renovar bookmark stale quando possível, iniciar o acesso durante a sessão e libertá-lo ao fechar.

Guardar também:

- ID local do projeto e path relativo da raiz para apresentação;
- data/estado da última resolução;
- escolha de root LaTeX por projeto;
- scopes adicionais confirmados para dependências fora da raiz;
- tabs e preferências, separados do conteúdo.

O report desktop confirma que bookmarks são o mecanismo Apple para acesso persistente, mas a implementação efetiva depende do modelo de sandbox/distribuição e deve ser testada numa build real ([desktop — E1–E2 e Contrato `ProjectSession`](research/reports/desktop-filesystem.md)). Não usar `fileResourceIdentifier` como ID persistente sem validação; o report assinala que não é estável entre reinícios.

### 3.2 Snapshot e indexação da árvore

O primeiro ciclo deve:

1. receber/validar a sessão;
2. iniciar o watcher;
3. criar o snapshot inicial;
4. construir o índice superficial da raiz;
5. carregar subpastas progressivamente;
6. calcular se cada pasta tem descendentes `.md`/`.tex` para o filtro.

O snapshot deve registar, pelo menos, path relativo, tipo, existência, acesso, tamanho, mtime e uma identidade adequada à sessão. Deve suportar enumeração lazy, pesquisa por nome/caminho e ordenação determinística sem misturar a resolução dos adapters.

Estados de erro da árvore:

- sem acesso: item visível com indicador;
- removido/renomeado: atualizar o índice e invalidar seleção se necessário;
- raiz movida/removida: sessão explícita `rootMoved`/`permissionLost`, sem crash;
- pasta vazia: mensagem “sem ficheiros compatíveis” quando o filtro o exigir, mantendo a pasta visível.

### 3.3 Watcher e snapshot/re-scan

**Recomendação técnica — confiança alta:** abstrair o backend de watch, mas adotar a semântica de FSEvents: iniciar antes do scan, agrupar eventos, tratar eventos como invalidação e fazer re-scan quando houver coalescing, dropped events, `MustScanSubDirs` ou alteração da raiz.

Um batch deve conter algo equivalente a:

```text
sessionID
sequence
paths[]
kinds: created | modified | removed | renamed
rescanScope: none | directory | subtree | root
permissionState
```

O valor do debounce e a política de estabilidade não devem ser fixados por preferência. Devem ser medidos para escritas incrementais, rename atómico, bursts, ficheiros grandes e dependências alteradas durante compilação. `NSFilePresenter` não deve ser o único mecanismo porque não cobre todas as escritas low-level ([synthesis — Invariantes de filesystem](research/synthesis.md); [desktop — E3–E5 e Debounce](research/reports/desktop-filesystem.md)).

### 3.4 Dependency index

O índice deve relacionar documento aberto, dependências observadas, referências não resolvidas, geração e estado de confirmação de acesso.

- **Markdown:** extrair links e imagens locais depois do parsing; registar `.md`/`.tex` que possam focar tabs, imagens, CSS/recursos permitidos e referências inexistentes.
- **LaTeX:** combinar root escolhido, ficheiros incluídos, outputs do recorder/`.fls`, bibliografia, estilos/classes, imagens, fontes e ferramentas que a cadeia identificar.
- **Fora da raiz:** parar a resolução e pedir confirmação explícita; depois da confirmação, associar o recurso a um scope/raiz observada segundo a política adotada.
- **Falha parcial:** manter dependências conhecidas, registar `unresolvedReferences` e mostrar diagnóstico; não assumir que a ausência de uma dependência significa que o documento não tem grafo.

Uma mudança em qualquer dependência relevante invalida o root/documento afetado. O índice deve continuar ativo mesmo quando o ficheiro auxiliar está oculto pelo filtro visual.

## 4. Render coordinator e process runner

### 4.1 Gerações, debounce e fila

**Requisito confirmado:** agrupar alterações, cancelar trabalhos obsoletos, reutilizar cache e não compilar páginas isoladas por suposição.

**Recomendação técnica — confiança alta:** cada documento/root tem uma geração monotónica. Um pedido deve conter `documentID`, `sourceRevision` e `dependencyRevision`; o resultado contém a geração usada. O coordenador:

1. recebe evento/botão manual;
2. atualiza snapshot e dependency index;
3. espera a política de estabilidade;
4. incrementa geração;
5. cancela ou deixa terminar o trabalho anterior sem lhe permitir publicar;
6. executa o adapter;
7. publica apenas se a geração ainda for atual;
8. agenda outra execução se houve alterações durante a renderização.

Deve haver no máximo uma compilação LaTeX ativa por root, para evitar outputs concorrentes. Markdown pode ter outra política, mas o sink deve aplicar a mesma validação de geração. A fila pode ser global ou por root; a escolha depende das medições.

### 4.2 Process runner

O runner deve aceitar executável identificado e argumentos separados, working directory, ambiente controlado, diretório temporário, timeout, cancelamento e captura separada de stdout/stderr. Deve devolver pelo menos:

```text
success | failed | cancelled | timeout | launchFailed
```

O resultado deve incluir duração, exit status, logs, artefactos encontrados e diagnóstico estruturado. Nunca construir uma única shell command string com partes derivadas de Markdown, LaTeX, paths ou configurações.

Para processos LaTeX, usar inicialmente opções não interativas, `halt-on-error`, `file-line-error` e recorder/dependency output quando a ferramenta os suportar. Isso melhora o diagnóstico mas não substitui análise do log: código de saída pode não distinguir todos os warnings/erros ([LaTeX — Cadeia tradicional e Erros](research/reports/latex-preview.md)).

### 4.3 Estados do preview

Cada tab deve poder representar independentemente:

- `idle`/sem preview;
- `updating` com geração;
- `ready` com hora de atualização;
- `stale` quando se mostra o último resultado válido;
- `failed` com diagnóstico e eventual artefacto anterior;
- `unavailable` por permissão/ferramenta ausente;
- `cancelled` ou `timeout`.

Erros devem apontar para ficheiro/linha quando possível, mostrar log expansível e permitir copiar. O estado não deve esconder o motivo por trás de uma mensagem genérica.

## 5. Adapter Markdown → HTML

### 5.1 Decisão de implementação ainda aberta

**Requisito confirmado:** Markdown renderizado em WebView, matemática delimitada, imagens locais/remotas, HTML raw sanitizado e links internos/externos com políticas definidas.

Os candidatos continuam abertos:

- `remark`/`unified` para AST e transformações;
- `cmark-gfm`/`swift-markdown` para integração nativa e poucas dependências;
- `markdown-it` para HTML direto e regras configuráveis;
- `micromark`/`markdown-rs` em cenários de parser mais direto ou Rust.

**Recomendação técnica — confiança média:** fazer uma fixture curta comparando `remark`/`unified` e `cmark-gfm`/`swift-markdown` primeiro; só manter `markdown-it`, `micromark` ou `markdown-rs` se o shell escolhido ou uma lacuna concreta os justificar. A recomendação não escolhe um vencedor: AST é valioso para links/diagnósticos, mas a pipeline JS tem mais dependências e pinning ([synthesis — Matriz e Conflitos](research/synthesis.md); [Markdown — Alternativas e Comparação](research/reports/markdown-html.md)).

### 5.2 Pipeline lógica

Independentemente do parser, o adapter deve seguir esta ordem conceptual:

1. ler o ficheiro através do `FileSystemGateway`;
2. parsear no dialecto explicitamente suportado;
3. transformar headings/âncoras e links internos;
4. resolver imagens e recursos relativamente ao ficheiro de origem;
5. renderizar matemática;
6. produzir HTML com classes/IDs previsíveis;
7. sanitizar depois da última transformação potencialmente insegura;
8. emitir HTML, dependências, warnings e errors;
9. entregar o HTML ao preview sem scripts do documento.

O dialecto deve ser registado no diagnóstico. GFM/footnotes não equivalem a bibliografia, includes, numeração global de equações ou referências semânticas.

### 5.3 Matemática

**Decisão aberta:** KaTeX ou MathJax.

- **KaTeX:** testar primeiro se as fórmulas são comuns e HTML estático previsível é mais importante; o report regista limitações em `\\label`, `\\ref` e `\\eqref`.
- **MathJax:** testar se a tese/Markdown precisa de maior cobertura TeX e referências; aceitar pipeline mais assíncrona/pesada.

O renderer deve correr localmente, sem CDN, com limites de tamanho/expansão e erros por bloco sempre que possível. A compatibilidade real entre `remark-math`/renderer e as versões empacotadas deve ser fixada antes de implementação estável; o report encontrou desalinhamentos entre versões observadas ([Markdown — Matemática e Conflitos](research/reports/markdown-html.md)).

### 5.4 Imagens locais e remotas

**Requisitos diferentes, ambos válidos:** imagens locais devem funcionar; imagens remotas podem ser carregadas e falhar offline.

- Localizar paths relativamente ao Markdown, não ao diretório de execução.
- Canonicalizar e verificar que o path fica dentro da raiz ou de um recurso explicitamente autorizado.
- Definir comportamento para `..`, paths absolutos, symlinks, nomes Unicode/espaços e ficheiros inexistentes.
- Registar imagens locais como dependências para re-render quando mudam.
- Para URL remota, distinguir explicitamente imagem de navegação. A URL pode ser permitida como `img` segundo uma política própria; isso não autoriza scripts, CSS remoto, frames, downloads ou navegação automática.
- Mostrar erro/placeholder sem invalidar todo o documento quando uma imagem remota não estiver disponível, conforme a UX a confirmar no protótipo.

O report de segurança alerta que imagens/CSS podem gerar pedidos passivos; portanto, permitir imagens remotas é uma decisão já confirmada de produto com custo de privacidade, rede e segurança. CSP e sanitização devem permitir somente os tipos de recurso realmente necessários ([vision — Preview e atualização](vision.md); [segurança — HTML, recursos e navegação](research/reports/preview-security-distribution.md)).

### 5.5 HTML raw, sanitização e WebView

O HTML raw deve ser aceito apenas após sanitização e a WebView deve receber conteúdo final sem JavaScript do documento.

**Recomendação técnica — confiança alta para defesa em profundidade:**

- desativar JavaScript de conteúdo;
- sanitizar depois de matemática e outras transformações que gerem HTML/SVG/MathML;
- usar allow-list pequena e versionada, expandindo-a só para elementos necessários;
- bloquear scripts, handlers `on*`, `iframe`, `object`, `embed`, forms, `base` e esquemas `javascript:`, `file:`, `data:`, `blob:` ou equivalentes não necessários;
- aplicar CSP compatível com imagens remotas, se a política as permitir, mas sem `script`/`object`/`connect` desnecessários;
- interceptar navegação, redirects, novas janelas e downloads;
- não expor bridge nativa ao conteúdo renderizado;
- testar CSS fornecido, SVG, HTML raw e recursos remotos — DOMPurify não resolve sozinho CSS/leaks HTTP.

A forma exata de carregar HTML (`loadHTMLString` com base URL, `loadFileURL` ou esquema app-owned) fica aberta até ao teste de paths e segurança. A opção mais controlada pode exigir mais código nativo ([synthesis — Guardrails](research/synthesis.md); [segurança — Recomendações e lacunas](research/reports/preview-security-distribution.md)).

## 6. Adapter LaTeX local → PDF

### 6.1 Cadeia de execução

**Requisitos confirmados:** usar instalação local, apresentar PDF na app, compilar root completo, memorizar a escolha, suportar confirmação de dependências fora da raiz e permitir configurações avançadas discretas.

**Recomendação técnica — confiança alta para a ordem; confiança média para a ferramenta:**

1. resolver o ficheiro aberto como candidato a capítulo;
2. encontrar roots candidatos por sinais verificáveis — preâmbulo, `\\documentclass`, `\\begin{document}`, relação de includes e configuração guardada;
3. se zero/mais de um, pedir escolha e memorizar por projeto;
4. construir workspace temporário e manifestar fontes/dependências;
5. detetar engine e ferramentas disponíveis;
6. executar a cadeia configurada, com outputs fora da raiz;
7. analisar exit status, log e PDF produzido;
8. extrair dependências/recorder e publicar PDF apenas para a geração atual;
9. mostrar PDF anterior como stale se a nova compilação falhar e o utilizador pedir essa visualização.

O report LaTeX favorece validar primeiro TeX Live/MacTeX/MiKTeX + `latexmk` para fidelidade e admite Tectonic como alternativa de menor custo operacional. Como a `vision.md` fixa instalação externa e tese concreta, o plano não transforma essa recomendação em escolha de ferramenta ([LaTeX — Recomendação condicional](research/reports/latex-preview.md); [synthesis — Matriz](research/synthesis.md)).

### 6.2 Root discovery e tabs

O algoritmo deve produzir evidência para o utilizador: candidatos encontrados, razão da seleção e projeto em que a escolha ficou guardada. Um capítulo aberto deve apontar para:

```text
selectedPath = chapters/methods.tex
previewRoot  = main.tex
tabIdentity  = projeto + previewRoot
context      = selectedPath
```

Isto satisfaz a regra de não criar uma tab duplicada do capítulo sem perder o contexto do ficheiro selecionado. A forma final de exibir esse contexto é UX confirmada; a estrutura acima é uma recomendação de modelo, a validar com tabs e links.

### 6.3 Bibliografia, TikZ/PGFPlots, fontes e ferramentas

O fixture LaTeX deve incluir, se a tese os usar:

- BibTeX clássico;
- BibLaTeX + Biber com versões compatíveis;
- referências cruzadas e bibliografia por capítulo/global;
- TikZ/PGFPlots e conversores de imagem;
- `fontspec`, fontes do sistema e fontes referenciadas por path;
- `.sty`, `.cls`, `.bst`, `.bib`, SVG/EPS/PNG/JPEG/PDF;
- ferramentas externas detetadas pelo log/recorder.

O runner deve distinguir “Biber ausente”, “versão incompatível”, “fonte ausente”, “ferramenta ausente” e erro TeX. Não instalar automaticamente pacotes no primeiro caminho. A visão permite configurações avançadas e reconhece `shell escape`/ferramentas externas; o modo de ativação continua a exigir decisão e teste.

### 6.4 Shell escape e segurança

**Recomendação técnica — confiança alta como guardrail, compatibilidade média:** começar com shell escape desativado ou restrito, nunca habilitado silenciosamente. Se a tese realmente depender dele, a app deve mostrar diagnóstico e a configuração avançada deve exigir opt-in explícito por projeto, com risco visível.

Mesmo restricted shell escape não torna macros, pacotes, ficheiros auxiliares ou conversores confiáveis. Compilar em workspace temporário, limitar tempo/output/processos, fixar ambiente e evitar escrita na pasta raw. O report de segurança recomenda cautela adicional com input não confiável; o report LaTeX lista as capacidades que só testes com a tese resolvem ([LaTeX — Segurança e próximos testes](research/reports/latex-preview.md); [segurança — Compilação LaTeX](research/reports/preview-security-distribution.md)).

### 6.5 Caches e recompilação

Reutilizar cache por projeto/root apenas quando a identidade da cadeia, engine, configurações e dependências forem compatíveis. A cache não pode permitir que output de outra geração seja publicado. Não assumir compilação incremental por página: watch mode de `latexmk`/Tectonic não resolve root discovery, agrupamento, cancelamento ou publicação segura.

## 7. PDF viewer

**Requisito confirmado:** PDF compilado dentro da app, scroll contínuo por defeito, seleção/cópia, pesquisa, zoom, outline quando disponível e posição de leitura preservada na medida do possível.

**Recomendação técnica — confiança média-alta:** começar por `PDFView`/PDFKit integrado no shell nativo. O report LaTeX confirma seleção, cópia, pesquisa e navegação; o report de segurança alerta que PDF não é apenas desenho e pode conter annotations/actions.

Política inicial a validar:

- renderizar o PDF em modo contínuo;
- preservar por tab a página/posição e tentar reencontrá-la após recompilação;
- expor pesquisa, zoom e cópia através da superfície nativa;
- construir outline apenas quando o PDF o fornecer;
- bloquear ou confirmar explicitamente URLs, `Launch`, remote go-to, attachments, forms e outras actions externas;
- diagnosticar PDF inválido/corrompido sem apagar o último preview válido.

Quick Look é fallback possível, não equivalente em controlo. O comportamento efetivo de actions deve ser testado na versão atual do macOS, não inferido apenas da documentação ([preview, segurança e distribuição — PDF](research/reports/preview-security-distribution.md)).

## 8. Workspace temporário, permissões e distribuição fora da App Store

### 8.1 Workspace temporário

Para cada projeto/root e geração, criar uma área fora da pasta raw, com subpastas separadas para:

- inputs copiados ou referências controladas;
- outputs finais e intermediários;
- logs/stdout/stderr;
- dependency recorder;
- cache reutilizável;
- estado de cancelamento/execução.

O workspace deve ser identificado por projeto/root, cadeia/versão e geração. Limpar após sucesso/erro/cancelamento por operação controlada; um crash posterior não pode deixar ficheiros na tese. Se a cadeia exigir ler dependências fora da raiz, copiar apenas após confirmação explícita e registar o scope concedido.

### 8.2 Permissões

**Requisito confirmado:** o macOS controla as permissões efetivas; a app não deve impor restrições artificiais aos ficheiros pessoais; recursos fora da raiz exigem confirmação explícita.

**Recomendação técnica — confiança alta para a separação:** a aplicação deve pedir acesso apenas através de ações explícitas do utilizador, guardar a referência de sessão adequada e passar permissões ao componente que realmente lê/compila. Não espalhar caminhos autorizados como strings por UI, adapters e processos.

O processo auxiliar não deve presumir que herdou automaticamente todas as permissões dinâmicas. A passagem de bookmarks/scopes e o funcionamento de helpers devem ser testados numa build distribuída. A política de raiz, symlinks, `..`, paths absolutos e volumes de rede deve ser explícita.

### 8.3 Distribuição fora da App Store

**Requisito confirmado:** distribuição inicial fora da App Store, por build local ou pacote direto.

Isto permite começar com a instalação local de LaTeX do Mac, sem prometer que o cenário seria compatível com Mac App Store. Para uma distribuição direta a terceiros, o plano deve validar:

- assinatura dos binários e helpers;
- Hardened Runtime e notarização, se o pacote for distribuído;
- deteção clara de instalações externas de LaTeX;
- versões mínimas e ferramentas requeridas;
- licenças de qualquer dependência redistribuída;
- comportamento offline dos componentes empacotados.

**Decisão aberta:** o MVP pode continuar como build pessoal não distribuída; a política de Developer ID/notarização e eventual empacotamento de helpers pode ser uma fase posterior. Se a distribuição mudar para App Store, a premissa de LaTeX externo tem de ser reavaliada desde o início. Esta incompatibilidade é material nos reports ([synthesis — Conflitos](research/synthesis.md); [segurança — Condicional decisiva](research/reports/preview-security-distribution.md)).

## 9. Restauração de tabs e estado local

### 9.1 Modelo recomendado

Guardar localmente, por projeto:

- referência persistente da raiz;
- lista ordenada de tabs;
- referência do ficheiro e, para LaTeX, root de preview/contexto de capítulo;
- tab ativa;
- posição de leitura por tab;
- pastas expandidas;
- tema;
- tamanho da janela e largura da sidebar;
- root LaTeX escolhido e configurações avançadas explicitamente opt-in.

Guardar referências/estado, nunca conteúdo raw ou cópias de fontes. O formato de persistência deve aceitar campos desconhecidos/futuros e falhas parciais: um ficheiro removido aparece como indisponível; uma raiz inacessível pede recuperação; uma tab inválida não deve impedir as restantes.

### 9.2 Ordem segura de restauração

1. abrir o estado local;
2. resolver a raiz e autorização;
3. reconstruir snapshot/árvore;
4. restaurar pastas expandidas e tabs que ainda possam ser identificadas;
5. restaurar tab ativa e posição de leitura depois do preview estar disponível;
6. iniciar renderizações necessárias;
7. marcar referências inválidas sem apagar silenciosamente o estado guardado.

O menu de pastas recentes e as ações de Finder devem reutilizar o mesmo modelo de sessão, para não criarem uma segunda forma de resolver permissões.

## 10. Performance e recompilação

### 10.1 Princípios

- lazy loading da árvore e pesquisa indexada, sem enumerar toda a subárvore em cada interação;
- debounce configurável e medido, não um valor presumido;
- re-scan apenas do escopo invalidado quando os eventos permitem, e re-scan amplo quando são dropped/coalesced;
- um root LaTeX ativo de cada vez;
- cancelamento ou descarte por geração;
- cache por projeto/root/cadeia, invalidada por dependências e configuração;
- não renderizar repetidamente estados incompletos de uma escrita em blocos;
- preservar posição de leitura sem bloquear publicação do novo preview.

### 10.2 Métricas do protótipo

Medir no Mac atual com fixtures e tese real, pelo menos:

- tempo para abrir sessão e primeiro snapshot;
- tempo para a árvore mostrar a primeira camada e responder à pesquisa;
- tempo de primeiro preview Markdown e LaTeX;
- tempo de recompilação após source, include, imagem, `.bib`, `.sty` e fonte alterados;
- tempo até diagnóstico em erro;
- CPU/memória durante burst de alterações;
- número de renders iniciados/publicados/cancelados por burst;
- tamanho e tempo de limpeza do workspace/cache;
- comportamento com documentos Markdown de 10 KB/100 KB/500 KB e tese com dependências reais, conforme a matriz dos reports.

Não usar estes valores para declarar vencedor entre frameworks sem condições reproduzíveis. O report desktop não encontrou benchmark primário comparável suficiente.

### 10.3 Critério de atualização correta

Para um burst de N alterações, é aceitável iniciar vários trabalhos se necessário, mas só a geração final pode chegar ao sink. Uma compilação antiga pode terminar com sucesso e ainda assim ser descartada. O teste deve verificar o resultado publicado, não apenas que o processo terminou.

## 11. Decisões técnicas ainda abertas

| Decisão | Estado atual | Opções a manter | Teste/critério para fechar |
|---|---|---|---|
| SwiftUI, AppKit ou divisão híbrida | Requisito de app nativa; divisão não fechada | SwiftUI para UI + AppKit para serviços; AppKit mais amplo | vertical slice com janela, Finder, WebView/PDFView, permissões e tabs |
| Mecanismo exato de bookmarks/scopes | Modelo de sessão necessário; entitlement final aberto | security-scoped bookmark; abstração equivalente no build pessoal | reinício, stale, rename da raiz, dependência externa e build assinada |
| Backend do watcher | Semântica fechada; backend aberto | FSEvents direto, camada Rust/Node se aplicável, Watchman só se necessário | fixture de snapshots, dropped/coalesced, rename atómico e volume real |
| Parser Markdown | Aberto | `remark`/`unified`; `cmark-gfm`/`swift-markdown`; outros só com razão | corpus real e custo de renderer/diagnósticos/sanitização |
| Renderer matemático | Aberto | KaTeX; MathJax; adiamento limitado | fórmulas reais, referências, erros, tempo e compatibilidade de versões |
| Carregamento HTML | Aberto | `loadHTMLString`/base URL; `loadFileURL`; esquema app-owned | paths, symlinks, imagens remotas, CSP, navegação e segurança |
| Política de CSS permitido | HTML raw já condicionado a sanitização | CSS próprio apenas; CSS do documento limitado; CSS removido | fixtures de temas, tabelas, matemática e ataque CSS/leak |
| Root discovery | Escolha manual e memória confirmadas; heurística aberta | sinais de preâmbulo/includes; configuração manual prevalecente | tese real com zero/um/vários roots e capítulos |
| Cadeia LaTeX | instalação local e PDF confirmados | engine atual + wrapper tradicional; Tectonic como comparação | biber, TikZ/PGFPlots, fontes, tools, offline e recompilação |
| Política de shell escape | Tese pode precisar; segurança exige cautela | off; restricted allow-list; opt-in por projeto | fixture que exige shell escape, risco, timeout e diagnóstico |
| Cache de compilação | Reutilização desejada; formato aberto | cache por root/cadeia; limpeza manual/automática | invalidar corretamente após cada tipo de dependência |
| PDF actions | Ler PDF confirmado; política ainda aberta | bloquear; confirmação explícita; permitir limitado | PDF malicioso/legítimo em macOS atual |
| Grau de empacotamento | MVP usa ferramentas externas | apenas build local; pacote direto com ferramentas detetadas; helpers empacotados futuro | assinatura, notarização, licenças e paths reais |
| Metadados persistidos | tabs/posição/janela/tema confirmados; esquema aberto | documento versionado e tolerante a falhas | restart, ficheiros removidos, mudança de raiz e migração futura |

Nenhuma linha acima deve ser fechada por preferência estética ou popularidade de uma ferramenta. O critério é o corpus, as permissões, a distribuição e os testes do MVP.

## 12. Riscos, incompatibilidades e validações locais necessárias

| Risco/incompatibilidade | Porque importa | Validação necessária | Mitigação provisória |
|---|---|---|---|
| FSEvents coalesce/perde eventos | árvore ou preview ficam obsoletos | forçar bursts, dropped events e root changes | snapshot/re-scan e batches com sequência |
| watcher observa só ficheiro aberto | imagens/includes/bibliografia não atualizam | alterar cada classe de dependência | `DependencyIndex` por adapter |
| escrita incremental publica estado parcial | preview mostra documento incompleto | escrever em blocos e rename atómico | estabilidade + debounce + geração |
| render antigo vence render novo | preview regressa no tempo | processo lento + alteração posterior | rejeitar por generation |
| root LaTeX errado | capítulo não compila ou mostra documento errado | tese com vários candidatos e capítulos | pedir escolha, guardar por projeto, explicar candidatos |
| `biber`/BibLaTeX incompatível | compilação falha fora do parser TeX | fixture BibLaTeX+Biber e versões reais | diagnóstico específico e deteção prévia |
| TikZ/PGFPlots/conversores ausentes | tese real falha apesar de engine instalado | fixture com ferramentas reais | reportar ferramenta ausente; não instalar silenciosamente |
| fontes especiais inacessíveis | PDF difere ou falha | `fontspec`, fontes do sistema e paths | diagnóstico e configuração avançada explícita |
| shell escape perigoso/incompatível | execução arbitrária ou tese quebrada | off/restricted/full com fixture | off/restricted por defeito, opt-in informado, temp/limits |
| TeX externo vs distribuição futura | app pessoal funciona mas pacote não | build assinada/notarizada e helper | separar `ProcessRunner`; adiar App Store; documentar requisito |
| KaTeX não suporta matemática real | fórmulas/referências incorretas | `\\label`, `\\ref`, `\\eqref`, macros e ambientes | manter MathJax como alternativa aberta |
| sanitização incompleta | XSS, pedidos ou navegação indesejada | HTML raw, SVG, CSS, URLs, handlers | allow-list + CSP + JS off + navigation policy |
| imagens remotas vazam/ficam indisponíveis | privacidade/offline/preview partido | URLs remotas com e sem rede | limitar a imagens, placeholder e diagnóstico |
| PDF actions perigosas | abrir URL/app/ficheiro sem intenção | PDF com actions/attachments/forms | bloquear ou confirmação explícita |
| bookmark stale/permissão perdida | tabs/raiz não reabrem | restart, rename, ACL/TCC, build distribuída | estados explícitos e recuperação |
| árvore grande bloqueia UI | UX não responde | tese real e árvores profundas | lazy loading, snapshot incremental, métricas |
| cache incorreta | output de projeto/versão errada | mudar engine/config/dependência | chave por root/cadeia/configuração e geração |
| versões JS incompatíveis | build funciona só no ambiente do agente | build offline com versões fixadas | lockfile, fixture e teste de compatibilidade |

### Matriz mínima de validação do protótipo

#### Filesystem e sessão

- pasta vazia, árvore profunda e pasta com muitos ficheiros;
- root renomeada/removida, subpasta ilegível, bookmark stale e recuperação;
- paths com espaços, Unicode, nomes longos, case-only rename e symlinks/ciclos;
- criação, remoção, rename e substituição atómica;
- alterações incrementais e bursts;
- dependência fora da raiz com confirmação e sem confirmação;
- restart com tabs, expansão, posição, tema, janela e sidebar.

#### Markdown e WebView

- headings, GFM, tabelas, footnotes, código, links/âncoras e Unicode;
- `$...$`, `$$...$$`, referências matemáticas, macros e erro de fórmula;
- imagem local alterada/removida, paths `../`, symlink, URL absoluta e ficheiro inexistente;
- imagem remota com rede e sem rede;
- HTML raw, script, handlers, SVG, CSS, iframe, `javascript:`, `file:`, `data:` e redirects;
- links internos para `.md`/`.tex`, links para ficheiros não suportados e links externos por ação explícita;
- pesquisa, seleção, cópia, zoom, tema, outline e preservação de scroll.

#### LaTeX e PDF

- root simples, múltiplos roots, capítulo incluído por `\\input`/`\\include`;
- BibTeX, BibLaTeX+Biber, cross-references, bibliografia global/por capítulo;
- TikZ/PGFPlots, imagens, `.sty`/`.cls`, fontes especiais e ferramentas externas;
- pacote/fonte/imagem ausente, input interativo, erro sintático e log longo;
- shell escape off/restricted/opt-in;
- alteração em capítulo, imagem, `.bib`, `.sty`, fonte e múltiplos eventos durante compilação;
- timeout, cancelamento, descendentes, limpeza do workspace e PDF parcial/anterior;
- seleção/cópia/pesquisa/outline/scroll e actions PDF.

#### Distribuição e performance

- build local com instalação LaTeX externa ausente/presente;
- build direto assinada/notarizada, se houver pacote distribuído;
- ferramentas e licenças realmente exigidas;
- build sem rede para a pipeline Markdown e, na medida suportada, para LaTeX/cache;
- métricas de arranque, primeiro preview, re-render, CPU, memória e responsividade.

## 13. Fases do protótipo/implementação e critérios de saída

As fases não significam que todas as features abaixo devam ser implementadas antes de validar o risco correspondente. Cada fase deve deixar uma decisão, um resultado ou uma lacuna documentada.

### Fase 0 — Corpus, ambiente e critérios

**Objetivo:** criar fixtures mínimos e recolher uma cópia controlada da tese.

**Trabalho:** inventariar engine/instalação LaTeX, `biber`, TikZ/PGFPlots, fontes, ferramentas externas e três ficheiros Markdown representativos; definir macOS atual, modo de build pessoal e políticas temporárias de links/imagens.

**Saída:** corpus versionado fora da pasta raw, matriz de comandos/versões, critérios de fidelidade/tempo/erro e lista de decisões de Bernardo ainda necessárias.

**Bloqueio:** sem root/fixtures representativos, não fechar parser, engine ou debounce.

### Fase 1 — Vertical slice nativa do shell

**Objetivo:** provar a app nativa e a divisão SwiftUI/AppKit sem adapters completos.

**Trabalho:** janela, sidebar, tab, `NSOpenPanel`, abertura do Finder, sessão mínima, placeholder de HTML/PDF, comandos básicos e restauração simples.

**Critério de saída:** abrir pasta/ficheiro, mostrar estado de permissão, fechar/reabrir, preservar referências e não bloquear ao existir trabalho simulado. A decisão SwiftUI/AppKit deve ser registada como “adequada”, “adequada com ponte” ou “reconsiderar”, com evidência de teste.

### Fase 2 — Session, bookmarks, snapshot e árvore

**Objetivo:** tornar a navegação correta antes de renderizar documentos.

**Trabalho:** `ProjectSession`, referência persistente, FileSystemGateway, SnapshotIndex, lazy tree, filtro, pesquisa, ordenação, estados sem acesso e pastas recentes.

**Critério de saída:** todas as regras de árvore confirmadas em `vision.md` funcionam com restart, root renomeada/indisponível, filtro e paths complexos; nenhum acesso cru da UI fora do gateway.

### Fase 3 — Watcher, dependency index e concorrência controlada

**Objetivo:** provar atualização externa e correção de gerações.

**Trabalho:** backend abstrato, batch/rescan, debounce configurável, índice de dependências fictício, RenderCoordinator com adapter fake lento, cancelamento/descarte e PreviewSink.

**Critério de saída:** testes de escrita incremental, rename atómico, bursts, coalescing/dropped e render fora de ordem publicam apenas a geração atual. O valor inicial de debounce deve ser acompanhado de medição, não de uma afirmação de universalidade.

### Fase 4 — Markdown vertical slice seguro

**Objetivo:** fechar a primeira pipeline Markdown e WebView com o corpus real.

**Trabalho:** comparar candidatos, fixar dialecto; links/âncoras, imagens locais/remotas, matemática, sanitização, CSP, JS desligado, navegação e diagnósticos.

**Critério de saída:** a pipeline escolhida reproduz o corpus prioritário dentro das limitações documentadas; ataques/paths fora da política são bloqueados/diagnosticados; dependências de imagens/links invalidam corretamente; pesquisa/cópia/zoom/tema/scroll funcionam.

**Se falhar:** manter a decisão do parser aberta ou limitar explicitamente o dialecto; não esconder incompatibilidades com pós-processamento ad hoc.

### Fase 5 — LaTeX → PDF com instalação externa

**Objetivo:** validar o caminho de maior risco com a tese real.

**Trabalho:** root discovery, escolha persistida, workspace temporário, ProcessRunner, engine atual, wrapper necessário, BibTeX/Biber, TikZ/PGFPlots, fontes, ferramentas, shell escape, logs, PDFKit e tabs de capítulo/root.

**Critério de saída:** o root prioritário compila e recompila no Mac atual; alterações em dependências chegam ao root; outputs não poluem a tese; erros são legíveis; PDF é navegável/copiável; timeout/cancelamento deixam o sistema recuperável.

**Se falhar:** registar qual capacidade da tese está fora do MVP e se a instalação/engine precisa de reconsideração; não trocar automaticamente para HTML ou Tectonic.

### Fase 6 — Tabs, restauração e integração de UX

**Objetivo:** integrar sessões, tabs e previews independentes.

**Trabalho:** tabs únicas, root/contexto LaTeX, ordem/ativa, posição, expansão, tema, janela/sidebar, links internos, Finder, comandos e fechamento durante compilação.

**Critério de saída:** restart e mudanças de projeto não corrompem estado; tabs inválidas tornam-se recuperáveis; escolher capítulo não cria duplicate root; cada tab mostra diagnóstico/preview próprio conforme requerido.

### Fase 7 — Performance, segurança e recuperação

**Objetivo:** testar o sistema integrado sob carga e conteúdo hostil.

**Trabalho:** medir métricas, bursts, árvore grande, documentos grandes, PDF/HTML hostil, imagens remotas, paths externos, cancelamentos e falhas de permissão.

**Critério de saída:** limites, debounce, cache e política de recursos estão documentados; não há regressão obvia para geração antiga; a UI permanece utilizável; riscos aceites têm owner/decisão explícita.

### Fase 8 — Build pessoal e pacote direto

**Objetivo:** confirmar o modo de distribuição inicialmente decidido.

**Trabalho:** deteção de ferramentas locais, mensagens de configuração, assinatura/notarização se o pacote for distribuído, inventário de licenças, Apple Silicon e comportamento sem rede para componentes que prometem offline.

**Critério de saída:** o build pessoal/pacote direto abre a pasta, encontra ou explica a ausência do LaTeX, preserva permissões e não depende de paths do ambiente de desenvolvimento.

## 14. Estado de decisão após este plano

### Fechado por `vision.md`

- produto pessoal macOS-first;
- app nativa como prioridade;
- preview Markdown e PDF LaTeX dentro da app;
- instalação LaTeX externa;
- raiz, tabs, Finder, links internos, imagens locais/remotas, atualização automática e restauração conforme a secção 1;
- distribuição inicial fora da App Store;
- tese real como primeiro corpus;
- confirmação explícita para dependências fora da raiz;
- ficheiros raw sem edição e sem cópia de conteúdo persistida.

### Recomendado como base de protótipo, sem decisão final de Bernardo

- divisão SwiftUI/AppKit com serviços nativos atrás de contratos;
- session/bookmark explícito, snapshot como fonte de verdade e watcher como invalidação;
- dependency index e geração monotónica;
- ProcessRunner com workspace temporário, logs, timeout e argumentos separados;
- JavaScript de conteúdo desligado, sanitização/CSP e navegação controlada;
- PDFKit como primeira superfície PDF a testar;
- shell escape off/restricted por defeito, com opt-in avançado se o corpus exigir;
- validação inicial da cadeia LaTeX tradicional da tese, sem assumir Tectonic ou outro candidato.

### Ainda depende de decisão/teste

- divisão final SwiftUI/AppKit e detalhes do shell;
- parser Markdown e renderer matemático;
- estratégia de carregamento HTML e política de CSS;
- backend do watcher e valores de debounce;
- root discovery exato;
- engine/wrapper LaTeX e compatibilidade Biber/TikZ/fontes;
- política final de shell escape e cache;
- PDF actions;
- forma de assinatura/notarização e qualquer distribuição além do uso pessoal.

## Ficheiros alterados

- Criado: `docs/technical-plan.md`

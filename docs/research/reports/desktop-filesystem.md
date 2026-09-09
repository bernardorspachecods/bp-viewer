# Relatório de investigação: desktop e filesystem

Data de acesso: 9 setembro 2026  
Escopo: shell desktop macOS, acesso local, observação de alterações, processos, contratos e testes.  
Sem alterações na repo, código ou protótipo.

## 1. Resumo executivo

A arquitetura mínima viável deve separar claramente:

1. shell e permissões;
2. gateway de filesystem;
3. watcher;
4. coordenador de renderizações;
5. adapters;
6. superfície de preview.

A escolha do watcher não deve transformar eventos em verdade absoluta. No macOS, FSEvents pode coalescer eventos, perder eventos ou sinalizar apenas que uma hierarquia precisa de ser reanalisada. A fonte de verdade deve ser sempre um novo snapshot do filesystem.

A recomendação condicional é:

- shell nativo SwiftUI/AppKit se a prioridade for integração macOS, permissões persistentes e menor número de camadas;
- Tauri 2 se a prioridade for uma UI web reutilizável mantendo um core local em Rust, desde que seja aceite código nativo adicional para permissões persistentes e integração macOS;
- Electron 44 se a prioridade for produtividade no ecossistema web e compatibilidade com ferramentas Node, aceitando maior bundle e ciclo de atualização Chromium/Node;
- Flutter permanece plausível, mas não oferece uma vantagem clara para este MVP macOS-first com preview baseado em WebView.

Não há evidência comparativa primária suficiente para afirmar valores concretos de memória, arranque ou desempenho entre estas opções.

## 2. Pergunta e decisão suportada

Foi investigado:

- como abrir e navegar por pastas locais;
- como manter acesso depois de reiniciar;
- como observar renomeações, remoções, escritas atómicas e alterações rápidas;
- como reagir a eventos coalescidos ou perdidos;
- como descobrir e observar dependências;
- como lançar, cancelar e supervisionar processos externos;
- como comunicar shell, adapters e preview;
- quais os custos de empacotamento e manutenção das opções principais.

A pesquisa suporta uma arquitetura de contratos independentes, mas não fecha a framework nem a estratégia dos adapters.

## 3. Escopo e pressupostos

Incluído:

- macOS;
- projetos locais com subpastas;
- leitura sem edição dos ficheiros-fonte;
- alterações externas, incluindo substituição atómica;
- compiladores ou ferramentas locais;
- preview HTML, PDF ou outro artefacto, sem escolher o formato.

Fora do escopo:

- parser Markdown;
- estratégia LaTeX;
- segurança detalhada de WebViews e PDFs;
- Windows/Linux;
- Finder replacement;
- protótipo ou implementação.

Assume-se que a pasta do projeto pode conter muitos ficheiros, mas não necessariamente milhões, e que a app não precisa de suportar volumes de rede no MVP.

## 4. Critérios de avaliação

- integração com APIs nativas de seleção e permissões;
- funcionamento offline;
- consistência perante eventos incompletos;
- atualização após alterações externas;
- suporte a dependências;
- cancelamento e isolamento de renderizações;
- custo de runtime e empacotamento;
- manutenção de dependências;
- compatibilidade com macOS;
- capacidade de manter os adapters independentes do shell.

## 5. Matriz de claims

| Claim | Importância | Estado | Evidência | Limitações |
|---|---:|---|---|---|
| C1. `NSOpenPanel`/SwiftUI permitem selecionar pastas e o macOS concede acesso ao recurso escolhido. | Alta | Suportado | E1 | O acesso persistente exige tratamento adicional. |
| C2. Security-scoped bookmarks são o mecanismo Apple para conservar acesso entre lançamentos. | Alta | Suportado | E2 | Requer entitlements e gestão correta de `start/stopAccessing`. |
| C3. FSEvents pode coalescer alterações e exige re-scan quando recebe `MustScanSubDirs`. | Alta | Suportado | E3, E4 | O comportamento detalhado deve ser testado na versão de macOS alvo. |
| C4. Eventos perdidos ou descartados exigem re-scan completo da hierarquia observada. | Alta | Suportado | E4 | Um re-scan pode ser caro em árvores grandes. |
| C5. A inicialização correta deve começar o watcher antes do primeiro scan. | Alta | Suportado | E3 | É uma regra de consistência, não uma garantia de baixa latência. |
| C6. `NSFilePresenter` não é suficiente para detetar todas as escritas externas. | Alta | Suportado | E5 | Só cobre alterações coordenadas por `NSFileCoordinator`. |
| C7. `Process` permite executar e monitorizar subprocessos; em sandbox, os filhos herdam a sandbox. | Alta | Suportado | E6 | A árvore real de processos do LaTeX precisa de teste local. |
| C8. Tauri 2 separa um core Rust com acesso ao sistema de WebViews do sistema; no macOS usa WKWebView. | Alta | Suportado | E7 | A versão do WebKit depende das atualizações do macOS. |
| C9. O plugin fs do Tauri fornece watch recursivo e debounce. | Alta | Suportado | E8 | A semântica concreta no macOS deve ser validada com os cenários do MVP. |
| C10. O dialog plugin do Tauri adiciona scopes durante a execução, mas documenta que estes não persistem após reinício. | Alta | Suportado | E9 | Pode exigir integração nativa própria para bookmarks. |
| C11. O shell plugin do Tauri suporta spawn, stdout/stderr e kill com permissões configuráveis. | Alta | Suportado | E10 | `kill` não prova, por si só, encerramento de descendentes. |
| C12. Electron 44 inclui Chromium 152, Node 24.18.1 e V8 15.2; requer macOS 13+. | Média | Suportado | E11 | A versão estável muda rapidamente. |
| C13. Electron separa main/renderer e requer IPC para APIs nativas. | Alta | Suportado | E12 | A superfície IPC deve ser explicitamente limitada. |
| C14. `fs.watch` usa FSEvents para diretórios no macOS, mas tem semântica limitada e problemas possíveis em filesystems de rede. | Alta | Suportado | E13 | A documentação consultada é Node 26, não exatamente o Node embebido no Electron 44. |
| C15. Chokidar 5 normaliza eventos, suporta escritas atómicas e `awaitWriteFinish`. | Alta | Suportado | E14 | É ESM-only e exige Node 20; não elimina a necessidade de revalidar o conteúdo. |
| C16. `notify` 8.2.0 disponibiliza backend FSEvents no macOS e debouncers separados. | Média | Suportado | E15 | Network filesystems continuam limitados. |
| C17. Watchman oferece recrawl, settle, clocks e queries incrementais, mas introduz um serviço externo. | Média | Suportado | E16 | A documentação operacional contém páginas antigas. |
| C18. Flutter 3.47.2 suporta macOS desktop e o plugin oficial `file_selector` seleciona diretórios. | Média | Suportado | E17 | A integração macOS, sandbox e aparência nativa exigem trabalho adicional. |
| C19. Não existe benchmark primário comparável suficiente para declarar vencedor em memória ou arranque. | Alta | Não demonstrado | Q1–Q10 | Deve ser resolvido por medição local, não por documentação. |

## 6. Alternativas investigadas

### Shell nativo SwiftUI/AppKit

Capacidades:

- `NSOpenPanel` para escolher diretórios;
- security-scoped bookmarks para acesso persistente;
- FSEvents diretamente;
- `FileManager` para enumeração;
- `Process` para ferramentas externas;
- Uniform Type Identifiers e `Info.plist` para associação de ficheiros;
- integração direta com menus, drag-and-drop e ciclo de vida macOS.

Custos:

- UI e infraestrutura em Swift;
- maior responsabilidade direta por bridging para preview;
- event streams e permissões têm de ser modelados explicitamente;
- mudanças nas APIs Apple exigem manutenção própria.

### Tauri 2

Capacidades:

- frontend web;
- core Rust;
- WKWebView fornecido pelo macOS;
- plugins oficiais para filesystem, dialogs e shell;
- IPC assíncrono entre frontend e core;
- bundle pequeno por não incluir um browser completo.

Custos:

- introduz Rust e uma camada de plugins;
- scopes e permissões são configuráveis, mas precisam de ser compreendidos;
- o dialog plugin documenta scopes não persistentes;
- a API de acesso security-scoped documentada pelo plugin fs é efetivamente específica de iOS, deixando a integração macOS como ponto a validar;
- Tauri documenta que o desenvolvimento não reproduz integralmente as condições de App Sandbox de distribuição.

### Electron 44

Capacidades:

- frontend web e Chromium controlado pela aplicação;
- Node.js embebido;
- APIs maduras para dialogs, IPC, subprocessos e filesystem;
- Chokidar pode normalizar watching e escritas atómicas;
- utilitários de processo para isolar trabalho pesado ou frágil.

Custos:

- Chromium, Node e V8 são empacotados;
- ciclo frequente de releases;
- maior bundle de distribuição;
- main/renderer/preload aumentam a superfície arquitetural;
- integração persistente com sandbox macOS é mais sensível, sobretudo para Mac App Store.

### Flutter

Capacidades:

- aplicação desktop compilada para macOS;
- plugin oficial para selecionar diretórios;
- possibilidade de código nativo Swift/Objective-C;
- distribuição via `.app` ou App Store.

Custos:

- não é naturalmente uma UI WebKit;
- integração com aparência macOS exige adaptação;
- permissões e integração nativa continuam necessárias;
- não apresentou uma vantagem específica sobre SwiftUI/Tauri para este fluxo.

### Watchman como serviço externo

É tecnicamente forte para árvores grandes ou muito ativas, com:

- estado incremental;
- clocks;
- settle periods;
- recuperação através de recrawl;
- queries desde uma posição anterior.

Contudo, exige distribuir, iniciar, supervisionar e diagnosticar outro processo. Para uma app pessoal, deve ser reservado para o caso de os testes demonstrarem que FSEvents direto ou `notify`/Chokidar são insuficientes.

## 7. Comparação fundamentada

| Critério | SwiftUI/AppKit | Tauri 2 | Electron 44 | Flutter |
|---|---|---|---|---|
| Integração macOS | Mais direta | Boa, com bridging quando necessário | Boa, via APIs Electron/Node | Boa, mas frequentemente via plugins/native code |
| Permissões persistentes | Melhor suporte direto com bookmarks Apple | Ponto de risco; requer validação/bridge | Suporte documentado sobretudo para MAS bookmarks | Requer configuração Xcode/entitlements |
| Filesystem local | `FileManager`/FSEvents | Rust ou plugins | Node/Chokidar | Dart/plugin/native |
| Processos externos | `Process` | Shell plugin/Rust | Node utility process/child process | Dart/native |
| Preview baseado em web | Requer WKWebView explicitamente | Natural | Natural | Exige componente adicional |
| Bundle | Sem runtime web adicional | Pequeno relativamente ao Electron, segundo documentação do fornecedor | Grande; Chromium/Node embebidos | Inclui engine Flutter |
| Dependências | Xcode/SDK Apple | Rust + Node frontend | Node/npm + Electron | Flutter/Dart + Xcode |
| Ciclo de atualização | APIs do OS | Tauri + Rust + WebKit do OS | Releases frequentes de Chromium/Node | Flutter SDK/plugins |
| Complexidade operacional | Alta no início, baixa no runtime | Média | Média/alta | Média |
| Confiança para este MVP | Alta | Média/alta, condicional | Média/alta | Média |

A tabela não é uma pontuação nem fecha a decisão. Resume adequação inferida a partir das capacidades documentadas.

## 8. Evidência

### E1 — seleção de pastas

A documentação Apple indica que `NSOpenPanel` pode escolher diretórios e que, quando o utilizador seleciona uma pasta, o macOS estende o sandbox aos seus conteúdos recursivamente.

Fonte: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) e [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel).

Estabelece:

- seleção nativa de uma pasta;
- acesso aos itens dentro da pasta selecionada durante a sessão.

Não estabelece:

- que o acesso sobreviva ao reinício;
- que todas as subpastas estejam acessíveis por razões de POSIX, ACL ou TCC.

### E2 — acesso persistente

A Apple documenta security-scoped bookmarks para preservar a intenção do utilizador entre lançamentos. O bookmark deve ser resolvido, atualizado se estiver stale, ativado com `startAccessingSecurityScopedResource` e libertado com `stopAccessingSecurityScopedResource`.

Fonte: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) e [NSURL bookmarks](https://developer.apple.com/documentation/foundation/nsurl).

Estabelece:

- mecanismo oficial para reabrir uma pasta selecionada;
- necessidade de tratar bookmarks stale;
- custo de gestão de recursos/kernel.

### E3 — coalescing e snapshot

A documentação Apple do FSEvents afirma que eventos podem ser coalescidos hierarquicamente, sinalizados por `MustScanSubDirs`, e recomenda combinar notificações com um snapshot da hierarquia.

Fonte: [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html).

Estabelece:

- o evento é uma indicação de que algo mudou;
- o snapshot deve ser comparado com o estado atual;
- o watcher deve ser iniciado antes do scan inicial.

### E4 — eventos descartados e raiz alterada

A documentação atual dos flags FSEvents especifica `MustScanSubDirs`, `UserDropped`, `KernelDropped` e `RootChanged`. Eventos descartados exigem um scan completo; `WatchRoot` permite detetar renomeação ou remoção da raiz.

Fontes: [FSEventStreamEventFlags](https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags), [MustScanSubDirs](https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags/kfseventstreameventflagmustscansubdirs) e [WatchRoot](https://developer.apple.com/documentation/coreservices/kfseventstreamcreateflagwatchroot).

Estabelece:

- necessidade de re-scan defensivo;
- necessidade de representar root moved/deleted como estado explícito;
- impossibilidade de depender apenas de notificações individuais.

### E5 — limitação de `NSFilePresenter`

A Apple documenta que `NSFilePresenter` só recebe notificações para alterações feitas através de `NSFileCoordinator`, não para escritas low-level.

Fonte: [NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter).

Estabelece:

- não é adequado como watcher único para alterações feitas por LLMs, editores ou scripts arbitrários.

### E6 — subprocessos nativos

`Process` permite executar, observar estado, capturar terminação e enviar interrupção/terminação. Em App Sandbox, os filhos herdam o sandbox do processo pai.

Fontes: [Process](https://developer.apple.com/documentation/foundation/process), [Process.run](https://developer.apple.com/documentation/foundation/process/run%28_%3Aarguments%3Aterminationhandler%3A%29) e [terminationHandler](https://developer.apple.com/documentation/foundation/process/terminationhandler).

Estabelece:

- base suficiente para um runner local;
- necessidade de distinguir saída normal, erro e cancelamento;
- relevância das entitlements na distribuição sandboxed.

### E7 — arquitetura Tauri

Tauri documenta um core Rust com acesso ao sistema e WebViews separadas; no macOS utiliza WKWebView do sistema. A WebView não é incluída no executável final.

Fontes: [Tauri Process Model](https://v2.tauri.app/concept/process-model/), [Tauri IPC](https://v2.tauri.app/concept/inter-process-communication/) e [Tauri App Size](https://v2.tauri.app/concept/size/).

Versão verificada: release listing com Tauri 2.11.5 como latest em julho de 2026; [releases oficiais](https://github.com/tauri-apps/tauri/releases).

Estabelece:

- separação adequada para manter filesystem/processos fora da UI;
- dependência da versão WebKit do macOS;
- potencial de bundle menor.

Não estabelece:

- memória ou arranque concretos;
- que todos os plugins resolvem as necessidades de sandbox macOS.

### E8 — watching no Tauri

O plugin fs documenta `watch`, `watchImmediate`, debounce configurável e watch recursivo opcional.

Fonte: [Tauri File System plugin](https://v2.tauri.app/plugin/file-system/).

Estabelece:

- API suficiente para um primeiro watcher;
- debounce disponível;
- recursividade explícita.

Não estabelece:

- garantias específicas para substituição atómica;
- recuperação completa após FSEvents dropped events.

### E9 — scopes e persistência no Tauri

O plugin dialog documenta que paths escolhidos são adicionados aos scopes durante a execução, mas que essa alteração não é persistida após reinício. O plugin fs documenta `startAccessingSecurityScopedResource` como operação específica de iOS e no-op nas outras plataformas.

Fontes: [Tauri Dialog plugin](https://v2.tauri.app/reference/javascript/dialog/) e [Tauri FS reference](https://v2.tauri.app/reference/javascript/fs/).

Estabelece:

- risco material para “abrir pasta e reabrir depois” em aplicação sandboxed;
- necessidade de bridge nativa ou de validação numa build distribuída.

### E10 — processos no Tauri

O shell plugin oferece `execute`, `spawn`, stdout, stderr, eventos de fecho/erro e `kill`. As permissões devem declarar programas e argumentos permitidos.

Fonte: [Tauri Shell plugin](https://v2.tauri.app/plugin/shell/) e [Shell JavaScript reference](https://v2.tauri.app/reference/javascript/shell/).

Estabelece:

- suporte funcional para compiladores locais;
- possibilidade de restringir executáveis e argumentos;
- necessidade de decidir se ferramentas serão instaladas pelo utilizador ou empacotadas.

### E11 — Electron atual

Electron 44.0.0 foi publicado em 25 agosto 2026 e inclui Chromium 152.0.7977.54, Node 24.18.1 e V8 15.2. Electron 44 requer macOS 13 ou posterior. A política oficial suporta as três versões estáveis mais recentes.

Fontes: [Electron 44](https://www.electronjs.org/blog/electron-44-0), [Electron v44 release](https://releases.electronjs.org/release/v44.0.0), [release schedule](https://releases.electronjs.org/schedule) e [breaking changes](https://www.electronjs.org/docs/latest/breaking-changes).

### E12 — processos e IPC no Electron

Electron separa main process e renderer process; APIs nativas e filesystem devem ser expostas através de preload/IPC. O `utilityProcess` permite executar trabalho isolado com stdout/stderr e `kill`.

Fontes: [Electron Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model), [Electron IPC](https://www.electronjs.org/docs/latest/tutorial/ipc) e [utilityProcess](https://www.electronjs.org/docs/latest/api/utility-process).

### E13 — Node `fs.watch`

A documentação Node especifica que, no macOS, `fs.watch` usa kqueue para ficheiros e FSEvents para diretórios. A API só fornece eventos `rename`/`change`, pode ser pouco fiável em alguns filesystems e não é recomendada como garantia absoluta em filesystems de rede.

Fonte: [Node.js `fs.watch`](https://nodejs.org/api/fs.html#fswatchfilename-options-listener).

### E14 — Chokidar

A versão 5.0.0 documenta:

- normalização de eventos;
- suporte a escritas atómicas;
- `awaitWriteFinish`;
- `add`, `change`, `unlink` e eventos de erro;
- dependência mínima de Node 20 e ESM-only.

Fonte: [Chokidar package documentation](https://www.npmjs.com/package/chokidar).

Isto melhora a ergonomia, mas não transforma o watcher numa fonte de verdade: o conteúdo deve ser reaberto e validado depois do evento.

### E15 — Rust `notify`

`notify` 8.2.0 documenta FSEvents como backend macOS por defeito, kqueue como alternativa, polling e debouncers separados. Também documenta limitações em filesystems de rede.

Fontes: [notify 8.2.0](https://docs.rs/notify/latest/notify/) e [repository oficial](https://github.com/notify-rs/notify).

### E16 — Watchman

Watchman 2026.08.10.00 é a release latest observada em 10 agosto 2026. A documentação descreve:

- `watch-project`;
- clocks;
- `since`;
- settle period;
- recrawl após perda de sincronização;
- serviço persistente por utilizador.

Fontes: [Watchman releases](https://github.com/facebook/watchman/releases), [watch-project](https://facebook.github.io/watchman/docs/cmd/watch-project), [clockspec](https://facebook.github.io/watchman/docs/clockspec) e [triggers](https://facebook.github.io/watchman/docs/cmd/trigger).

### E17 — Flutter

A documentação Flutter atualmente reflecte Flutter 3.47.2. O desktop macOS é suportado e o `file_selector` oficial suporta seleção de diretórios e exige entitlements de acesso a ficheiros selecionados.

Fontes: [Flutter release notes](https://docs.flutter.dev/release/release-notes), [desktop support](https://docs.flutter.dev/platform-integration/desktop), [macOS building](https://docs.flutter.dev/platform-integration/macos/building) e [file_selector](https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector).

## 9. Contratos entre componentes

Os contratos abaixo são recomendações arquiteturais, não decisões de produto.

### `ProjectSession`

Responsável por:

- raiz atualmente aberta;
- URL/bookmark e estado de acesso;
- estado `available`, `permissionLost`, `rootMoved`, `closed`;
- associação entre caminhos relativos e recursos atuais.

A API deve preferir caminhos relativos à raiz e identificadores opacos. Um identificador de filesystem pode ajudar durante a sessão, mas a Apple documenta que não é persistente entre reinícios.

Fonte: [fileResourceIdentifier](https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey).

### `FileSystemGateway`

Deve expor:

- abrir pasta;
- listar filhos imediatos;
- enumerar subárvores;
- ler bytes/texto;
- obter metadata;
- resolver caminho relativo;
- verificar existência e tipo;
- retornar erros de permissão, remoção ou corrida.

A árvore visual deve poder fazer lazy loading. `FileManager` suporta tanto enumeração superficial como profunda.

Fontes: [FileManager](https://developer.apple.com/documentation/foundation/filemanager) e [contentsOfDirectory](https://developer.apple.com/documentation/foundation/filemanager/contentsofdirectory%28at%3Aincludingpropertiesforkeys%3Aoptions%3A%29).

### `FileWatcher`

Entrada:

- raiz;
- modo recursivo;
- política de exclusões;
- token de sessão.

Saída:

```text
ChangeBatch {
  sessionID
  sequence
  paths[]
  kinds: created | modified | removed | renamed
  rescanScope: none | directory | subtree | root
  permissionState
}
```

Regras:

- eventos podem ser duplicados;
- caminhos podem já não existir;
- `rescanScope != none` invalida conclusões incrementais;
- uma mudança de raiz deve ser representada explicitamente;
- o watcher não deve entregar diretamente “conteúdo novo”; deve apenas invalidar snapshots.

### `DependencyIndex`

O adapter pode devolver, depois de uma renderização:

```text
DependencyManifest {
  documentID
  dependencies[]
  unresolvedReferences[]
  generation
}
```

Para dependências dentro da raiz, o watcher da raiz é normalmente suficiente. Para dependências fora da raiz, é necessário decidir entre:

- pedir acesso adicional;
- observar outra raiz;
- marcar a dependência como não observável;
- revalidar sob procura.

Esta decisão depende dos adapters e permanece aberta.

### `RenderCoordinator`

Contrato:

```text
render(documentID, sourceRevision, dependencyRevision) -> CancellableRender
```

Comportamento recomendado:

- no máximo uma renderização ativa por documento;
- novas alterações incrementam uma geração;
- a renderização anterior pode ser cancelada;
- se não for cancelada, o resultado antigo é descartado;
- só a geração mais recente pode atualizar o preview;
- alterações durante a compilação deixam uma nova renderização pendente;
- outputs temporários ficam fora da pasta do projeto;
- falhas produzem erro estruturado, não apenas texto bruto.

### `ProcessRunner`

Deve aceitar:

- executável identificado;
- argumentos separados, nunca uma shell command string;
- working directory;
- environment;
- diretório temporário;
- captura separada de stdout/stderr;
- timeout opcional;
- cancelamento;
- estado final: success, failed, cancelled, launchFailed.

O contrato deve distinguir “processo terminado” de “artefacto válido produzido”.

### `PreviewSink`

Recebe:

```text
PreviewUpdate {
  documentID
  generation
  artifact
  diagnostics[]
}
```

O sink rejeita updates de gerações antigas. O tipo de artefacto permanece abstrato: HTML, PDF ou outro formato pode ser escolhido pelo adapter.

### Comunicação shell–UI

A UI deve receber:

- árvore de ficheiros;
- mudanças de seleção;
- estado de acesso;
- progresso;
- diagnóstico;
- preview aprovado.

A UI não deve:

- ler arbitrariamente paths;
- iniciar compiladores diretamente;
- decidir que um evento representa conteúdo final;
- substituir o mecanismo de permissões do shell.

## 10. Debounce, filas e condições de corrida

Fluxo recomendado:

1. iniciar o watcher;
2. criar o snapshot inicial;
3. abrir a pasta na árvore;
4. ao receber eventos, agrupar alterações próximas;
5. reanalisar diretórios afetados;
6. calcular documentos afetados através do índice de dependências;
7. incrementar a geração;
8. aguardar a política de estabilidade escolhida;
9. cancelar ou deixar terminar a renderização anterior;
10. publicar apenas o resultado cuja geração continua atual.

Uma única janela fixa de debounce não deve ser considerada universalmente correta. Deve ser validada para:

- ficheiros pequenos substituídos atomicamente;
- ficheiros escritos em blocos;
- compilação lenta;
- muitas alterações consecutivas;
- alterações em dependências.

A correção depende mais da validação por geração e do re-scan do que do valor exato do debounce.

## 11. Conflitos e refutações

### “Basta observar o ficheiro aberto”

Refutado. Um documento pode depender de imagens, includes, bibliografia, macros ou outros ficheiros. O contrato deve permitir ao adapter declarar dependências.

### “FSEvents entrega exatamente todos os eventos”

Refutado. A Apple documenta coalescing, eventos descartados e necessidade de re-scan.

### “`NSFilePresenter` resolve atualizações externas”

Refutado para este caso. Não cobre alterações low-level que não passem por `NSFileCoordinator`.

### “Chokidar elimina o problema de escritas atómicas”

Parcialmente refutado. Chokidar oferece tratamento específico, mas a aplicação ainda deve reabrir o ficheiro, confirmar o estado e lidar com mudanças durante a renderização.

### “Watchman é automaticamente melhor”

Não demonstrado. Watchman oferece mais infraestrutura, mas introduz um daemon, estado adicional e custo de distribuição. Só deve ser preferido se os testes justificarem.

### “Tauri é automaticamente a opção mais leve”

Parcialmente suportado apenas em bundle. A documentação Tauri afirma que não inclui a WebView e que uma app mínima pode ser pequena; não há aqui benchmark comparável de memória, arranque ou desempenho para o bp-viewer.

### “Electron é inviável por ser pesado”

Não demonstrado como afirmação de runtime. A documentação Electron confirma que Chromium/Node são embebidos e que as apps tendem a ser maiores em disco, mas não prova que a experiência seja inadequada para esta aplicação pessoal.

## 12. Recomendação condicional

A opção preferida para investigação adicional é o shell nativo SwiftUI/AppKit quando:

- macOS é a única plataforma relevante;
- permissões persistentes são prioritárias;
- a aplicação deve comportar-se como uma app Mac;
- o custo de implementar a camada UI nativa é aceitável.

Tauri 2 é uma alternativa forte quando:

- a UI web é uma vantagem importante;
- o core Rust é aceitável;
- se aceita validar ou implementar a integração macOS para bookmarks e sandbox;
- o tamanho de distribuição é importante.

Electron 44 é adequado quando:

- a equipa quer permanecer em TypeScript/Node;
- a maior integração com ferramentas web compensa o bundle;
- se aceita acompanhar Chromium, Node e releases frequentes;
- o alvo mínimo macOS 13+ é aceitável.

Flutter só ganha vantagem se a prioridade for uma UI compilada e multiplataforma futura. Para o MVP macOS-first com hipótese de preview via WebView, a evidência não mostra uma vantagem específica.

Confiança: média.  
A conclusão é uma inferência de adequação; não é benchmark nem decisão final.

## 13. Implicações para o MVP

- O watcher deve invalidar e provocar re-scan; não deve transportar a responsabilidade de determinar o conteúdo final.
- A raiz aberta precisa de um estado de permissões explícito.
- O caminho persistente deve ser tratado como bookmark ou equivalente, não apenas como string.
- A árvore deve suportar enumeração superficial e carregamento incremental.
- A renderização deve ser versionada por geração.
- O resultado de uma compilação antiga nunca deve substituir um preview mais recente.
- Dependências declaradas pelo adapter devem poder invalidar o documento aberto.
- Artefactos temporários e logs devem ficar fora da pasta do utilizador.
- O contrato do adapter não deve assumir HTML, PDF ou outro formato.
- A distribuição sandboxed deve ser testada separadamente da execução em desenvolvimento.

## 14. Testes de filesystem antes de congelar a arquitetura

| Teste | Resultado esperado |
|---|---|
| Abrir pasta com árvore profunda e muitos ficheiros | A UI permanece responsiva; a árvore pode carregar progressivamente. |
| Abrir pasta vazia | Estado válido, sem confundir “vazia” com “sem permissão”. |
| Criar ficheiro Markdown/LaTeX | Entrada aparece sem reiniciar a app. |
| Remover ficheiro | Entrada desaparece; se estava selecionado, preview passa a estado explícito de indisponível. |
| Renomear ficheiro | Árvore atualiza; seleção é preservada apenas se a identidade puder ser confirmada. |
| Renomear diretório pai | Caminhos relativos e seleção são recalculados corretamente. |
| Substituir atomicamente o ficheiro aberto | O conteúdo final é lido; não fica preso ao ficheiro temporário nem a um estado vazio. |
| Escrever o mesmo ficheiro em blocos | A app não renderiza repetidamente estados incompletos ou, se renderizar, nunca publica estado obsoleto. |
| Fazer várias alterações durante compilação | Existe no máximo um preview publicado para a geração mais recente. |
| Cancelar compilação | O processo e descendentes relevantes terminam ou são diagnosticados; artefactos temporários são limpos. |
| Alterar dependência incluída | O documento aberto é invalidado e renderizado novamente. |
| Adicionar/remover dependência | O índice é atualizado e referências antigas não continuam a provocar renders. |
| Forçar coalescing de eventos | O re-scan reconstrói o estado correto. |
| Provocar `UserDropped`/`KernelDropped`, se possível | É feito re-scan completo, sem depender da lista parcial de paths. |
| Remover ou mover a raiz observada | O estado passa a `rootMoved`/`unavailable`, sem crashes. |
| Reabrir após renomear a raiz | O bookmark ou mecanismo escolhido encontra a raiz atual, ou pede nova seleção. |
| Tornar subpasta ilegível | O erro é localizado; o resto da árvore continua utilizável quando possível. |
| Recuperar permissões | Após nova autorização, a árvore e o watcher são restabelecidos. |
| Reiniciar a app | A pasta escolhida é reaberta sem exigir seleção, se essa for a política escolhida. |
| Bookmark stale | É detetado, recriado e persistido novamente. |
| Ficheiros com Unicode e nomes longos | Identidade, leitura e ordenação permanecem corretas. |
| Case-insensitive filesystem | Renomeações apenas de capitalização não corrompem a árvore. |
| Symlinks e ciclos | A política — seguir, mostrar ou ignorar — é consistente e não causa recursão infinita. |
| Crash durante compilação | Não ficam outputs dentro do projeto nem locks permanentes. |
| Volume de rede/SMB opcional | O comportamento é diagnosticado como suportado, degradado ou fora do MVP; não é assumido. |

## 15. Lacunas e próximos testes

Só testes locais podem resolver:

- memória e arranque reais;
- custo da enumeração em pastas semelhantes às teses;
- semântica exata de Tauri fs watch no macOS;
- persistência de permissões em builds assinadas e sandboxed;
- encerramento de toda a árvore de processos LaTeX;
- comportamento com ferramentas instaladas via MacTeX/Homebrew;
- estabilidade de WebKit na versão mínima de macOS escolhida;
- valores adequados de debounce e estabilidade;
- custo real de manter um índice de dependências.

A pesquisa web não resolveu estes pontos sem protótipo ou instalação local.

## 16. Ledger de fontes

| Fonte | Estado | Versão/data | Uso |
|---|---|---|---|
| Apple App Sandbox | Usada | Documentação atual, consultada em 2026-09-09 | Seleção de pastas e bookmarks |
| Apple NSOpenPanel | Usada | Documentação atual | Dialog nativo |
| Apple FSEvents API/reference | Usada | Documentação atual | Flags e lifecycle |
| Apple FSEvents Programming Guide | Usada com ressalva | Guia arquivado, conteúdo estável | Coalescing, snapshot, ordem inicial |
| Apple NSFilePresenter | Usada | Documentação atual | Refutar mecanismo incompleto |
| Apple Foundation Process | Usada | Documentação atual | Subprocessos |
| Apple FileManager | Usada | Documentação atual | Enumeração |
| Tauri v2 docs | Usada | Docs atuais; conceitos atualizados em 2026 | Core, IPC, fs, shell |
| Tauri releases | Usada | 2.11.5 observado em 2026-07 | Verificação de versão |
| Electron 44 docs/releases | Usada | 44.0.0, 2026-08-25 | Runtime e compatibilidade |
| Node.js fs docs | Usada com ressalva | Docs Node 26.8.1 | Semântica de `fs.watch` |
| Chokidar package docs | Usada | 5.0.0 | Normalização e escritas atómicas |
| Rust notify | Usada | 8.2.0 | Alternativa Rust |
| Watchman | Usada com ressalva | 2026.08.10.00 | Alternativa para árvores grandes |
| Flutter docs/file_selector | Usada | Docs reflectem 3.47.2 | Alternativa adicional |
| Blogs, snippets, Stack Overflow e rankings | Rejeitados | — | Não são evidência primária suficiente |
| Benchmarks não reproduzíveis | Rejeitados | — | Condições incompatíveis com o bp-viewer |
| Marketing de fornecedores | Limitado | — | Usado apenas para descrever arquitetura própria, não superioridade |

## 17. Registo de pesquisa

| ID | Pesquisa/caminho | Resultado |
|---|---|---|
| Q1 | Apple App Sandbox, NSOpenPanel, security-scoped bookmarks | Confirmou seleção e persistência condicional |
| Q2 | Apple FSEvents e flags atuais | Confirmou coalescing, dropped events e root changes |
| Q3 | Apple FileManager e NSFilePresenter | Confirmou snapshot/enumeration e limitação de coordination |
| Q4 | Apple Foundation Process | Confirmou execução e terminação |
| Q5 | Tauri process model, fs, dialog e shell | Confirmou capacidades e lacuna de scopes persistentes |
| Q6 | Tauri releases/distribution | Confirmou versão e custos operacionais |
| Q7 | Electron release schedule, process model, IPC e dialog | Confirmou runtime, compatibilidade e contratos |
| Q8 | Node `fs.watch` e Chokidar | Confirmou limitações e normalização de eventos |
| Q9 | Rust notify e Watchman | Comparou watcher embebido com serviço externo |
| Q10 | Flutter desktop/macOS/file_selector | Avaliou alternativa adicional |

## 18. Razão para parar

A pesquisa já fornece evidência suficiente para:

- comparar shells;
- definir contratos independentes;
- estabelecer a semântica mínima do watcher;
- especificar testes antes de congelar a arquitetura.

Os restantes pontos relevantes são empíricos — permissões sandboxed, performance, cancelamento de processos e debounce — e exigem teste local. Continuar a pesquisa web tenderia a repetir documentação dos fornecedores sem reduzir essas incertezas.

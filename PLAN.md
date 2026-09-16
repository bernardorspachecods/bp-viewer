# Plano final de refatoração da concentração de código

## Objetivo

Reduzir o `AppModel` a uma camada fina de estado observado pela UI, intents e
aplicação de eventos. A lógica de sessão deve ser independente de
SwiftUI/AppKit e preparada para o crescimento futuro da aplicação.

A refatoração deve preservar o comportamento observável, a compatibilidade do
schema de persistência e as garantias de cancelamento, watchers, previews,
edição, tabs e snapshots. Não se pretende apenas reduzir linhas: cada módulo
novo deve possuir responsabilidades e invariantes próprios, interfaces baseadas
em valores/eventos e seams testáveis.

## Decisões arquiteturais

- `BPViewerCore` é a fronteira para modelos e lógica sem dependências visuais.
- SwiftUI, AppKit, WebKit e PDFKit permanecem no target macOS quando forem
  necessários à integração da plataforma.
- `AppModel` mantém estado publicado pela UI, intents de alto nível e
  aplicação de eventos; não possui implementações completas de subsistemas.
- Os coordenadores não conhecem nem mutam `AppModel`; comunicam por
  transições, snapshots e eventos.
- Não serão criados módulos artificiais apenas para baixar a contagem de linhas.
- Cada fase é validada antes da seguinte.
- A documentação canónica deste trabalho é este ficheiro.

## Estado

- Planos anteriores — concluídos: árvore, rendering, edição, editor source e
  ponte WebKit já foram separados.
- Plano 3 — concluído: modelos puros, persistência base e sessão de tabs vivem
  em `BPViewerCore`, com contratos determinísticos.
- Plano 4 — concluído: persistência/workspace, abertura de documentos e
  watchers foram separados; o `AppModel` ficou como projeção observável e
  orquestração específica da UI.
- A divisão foi encerrada onde começaria a criar módulos rasos: lifecycle de
  confirmação, aplicação de eventos de render/edição e ações AppKit continuam
  no `AppModel` porque precisam coordenar diretamente estado publicado e janela.
- Todas as fases foram validadas pelos critérios indicados no fim.

## Plano 3 — Reforçar a fronteira `BPViewerCore`

### Resultado desejado

Os modelos puros da sessão e a lógica de tabs podem ser testados sem criar a
janela da app. O target macOS fica responsável apenas pela apresentação e pela
integração de plataforma.

### Trabalho

1. Registar o comportamento atual com `swift test`,
   `BPViewerContractRunner` e `BPViewerFoundationRunner`. Identificar os
   invariantes de tabs, persistência, edição e estado de preview que não podem
   mudar.
2. Mover para `BPViewerCore` os modelos sem dependências visuais:
   `DocumentTab`, o estado de preview, `MarkdownEditSession`, conflitos,
   posições de leitura, `AppState`, `WorkspaceState`,
   `DocumentState`, `GlobalState`, snapshots e `AppStateStore`.
3. Manter no target da app apenas extensões ou adaptadores visuais para labels,
   cores, SF Symbols e `ColorScheme`.
4. Criar `DocumentTabSession` no Core para abrir, selecionar, fechar,
   reordenar, restaurar, fechar à direita/outros e manter a tab ativa.
5. Fazer o `AppModel` consumir transições/estados da sessão, sem manipular
   diretamente as regras de tabs.
6. Acrescentar testes determinísticos para modelos, persistência e sessão de
   tabs, mantendo os runners como contratos de regressão.

### Critérios de conclusão

- `BPViewerCore` não importa SwiftUI, AppKit, WebKit ou PDFKit.
- `DocumentTabSession` não conhece `AppModel` nem a janela.
- O schema e as chaves de persistência existentes continuam compatíveis.
- Os testes de tabs, persistência e modelos cobrem as transições relevantes.
- Os testes e runners passam antes de iniciar o Plano 4.
- A build da app passa e `./scripts/restart-app.sh` abre a versão nova.

## Plano 4 — Finalizar o `AppModel` fino

### Resultado desejado

O `AppModel` coordena a UI sem ser dono das operações de workspace,
documentos, watchers, persistência ou contexto LaTeX.

### Trabalho

1. Criar `WorkspaceSessionCoordinator` para trocar e restaurar workspaces,
   gerir URLs pendentes, persistir estado de workspace e gerir roots e
   autorizações LaTeX; separar a resolução pura de documentos em
   `DocumentOpenCoordinator`.
2. Criar `ActiveDocumentWatcher` para observar ficheiros ativos e dependências
   de previews, com debounce, gerações e eventos de alteração.
3. Retirar do `AppModel` acesso direto a `AppStateStore`, criação de watchers,
   descoberta de roots LaTeX, manipulação direta de `DocumentTabSession`,
   abertura operacional de documentos e regras de persistência; manter no
   `AppModel` apenas o lifecycle AppKit que aplica confirmações e eventos.
4. Rever preferências de apresentação: mover normalização de zoom e regras
   puras para o Core; manter no `AppModel` apenas intents visuais. Não criar
   um módulo de forwarding se não houver coesão suficiente.
5. Simplificar a integração de snapshots: manter `SnapshotSupport` na camada
   AppKit e retirar do `AppModel` a lógica de persistência/coordenação que
   possa viver num seam próprio.
6. Remover helpers e callbacks que se tornem redundantes e rever as interfaces
   dos coordenadores para que cada evento tenha um consumidor claro.

### Critérios de conclusão

- `AppModel` fica substancialmente menor, idealmente abaixo de 1.000 linhas,
  sem usar a contagem como único critério.
- Não contém subsistemas operacionais completos de tabs, persistência,
  workspace, watchers ou LaTeX.
- Os novos módulos não conhecem nem mutam `AppModel`.
- O schema de persistência continua compatível com estados existentes.
- Existem testes para tabs, modelos, persistência e transições relevantes.
- `swift test`, `BPViewerContractRunner` e
  `BPViewerFoundationRunner` passam.
- A build termina com sucesso e `./scripts/restart-app.sh` abre a versão nova
  para teste manual.

## Sequência de execução

### Fase 0 — Baseline

- Confirmar documentação e regras da repo.
- Executar os testes e runners atuais.
- Registar os invariantes e o estado inicial do código.

### Fase 1 — Plano 3

- Migrar modelos puros para o Core.
- Criar e testar `DocumentTabSession`.
- Adaptar o `AppModel` e as views sem alterar comportamento.
- Build, runners e restart obrigatório.

### Fase 2 — Plano 4: workspace e abertura de documentos

- Extrair o lifecycle da raiz, abertura de documentos, persistência de workspace
  e contexto/autorização LaTeX.
- Introduzir eventos/valores para pedidos de confirmação e resultados.
- Validar abertura, restauração, troca de workspace e tabs.

### Fase 3 — Plano 4: watchers e apresentação

- Extrair watchers de ficheiros/dependências.
- Mover regras puras de preferências quando houver seam profundo.
- Simplificar snapshots sem duplicar o `SnapshotWindowManager`.
- Validar alterações externas, refresh, zoom, tema, pesquisa e snapshots.

### Fase 4 — Limpeza e aceitação — concluída

- Remover forwarding e estado duplicado sem fonte de verdade.
- Rever imports e fronteiras Core/App.
- Confirmar documentação arquitetural.
- Executar a matriz completa de validação e abrir a app.

## Decisão de fecho

O `AppModel` permanece acima da meta indicativa de 1.000 linhas porque ainda
aplica eventos assíncronos à propriedade `@Published`, encaminha ações AppKit
e mantém os pedidos de confirmação visíveis pela UI. Extrair esse código para
mais um coordenador obrigaria a expor a mesma lista de mutações e produziria
um módulo raso. A métrica relevante para este plano é que os subsistemas Core,
renderização, edição, árvore, watcher e snapshots têm seams próprios e
testáveis; essa condição está cumprida.

## Testes e validação

Em cada fase que altere a app:

```bash
swift build --target BPViewerApp
./scripts/restart-app.sh
```

Na aceitação final:

```bash
swift test
swift run BPViewerContractRunner
swift run BPViewerFoundationRunner
swift build --target BPViewerApp
./scripts/restart-app.sh
git diff --check
```

A validação deve mencionar explicitamente qualquer fixture opcional ignorada,
qualquer warning do toolchain e qualquer falha do script de restart.

## Fora de escopo

- Redesign da UI ou alteração de comportamento observável.
- Arquitetura genérica de plugins/renderers.
- Divisão cosmética de `LatexAdapter.swift`, `SnapshotSupport.swift` ou
  `WorkspaceView.swift` sem um seam real.
- Reescrita dos runners em paralelo à lógica da app.

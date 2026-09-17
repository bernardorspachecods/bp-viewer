# Plano: editor LaTeX equivalente ao editor Markdown

## Estado

Plano confirmado para implementação. O `go` do utilizador já foi dado.

## Objetivo

Fazer o editor LaTeX oferecer o mesmo fluxo de edição source do Markdown:
duplo clique no preview, source/split view, preview live, Undo/Redo, Save,
Discard Changes, conflitos externos, Disk Diff, Git Diff, pesquisa e
navegação entre preview e source.

O preview LaTeX continuará a ser PDFKit. Neste contexto, “preview live”
significa recompilar assincronamente depois de aproximadamente dois segundos
sem alterações, preservando o último PDF válido enquanto a compilação corre ou
falha.

## Decisões de produto

- A edição começa por duplo clique no PDF LaTeX.
- Se a tab tiver um ficheiro contextual, esse ficheiro é o source editado;
  caso contrário, é editado o root principal.
- O preview compila sempre o root principal, incorporando o rascunho do source
  contextual.
- O debounce inicial do preview live é de aproximadamente dois segundos.
- Compilações obsoletas são canceladas ou ignoradas; nunca podem substituir um
  PDF produzido por um rascunho mais recente.
- SyncTeX é gerado quando possível e o duplo clique posiciona o cursor na
  linha/coluna correspondente. Sem mapa disponível, o editor usa um fallback
  seguro de posição.
- Âncoras e referências internas permanecem navegáveis no PDF. Links externos
  abrem no browser e links para ficheiros suportados passam pelo router da app.
- O source pode ser guardado mesmo quando a compilação falha. O último PDF
  válido permanece visível e o diagnóstico de compilação é apresentado.
- Uma alteração externa no source editado abre o painel de conflito. Uma
  alteração externa noutra dependência apenas dispara nova compilação mantendo
  o rascunho.
- Disk Diff e Git Diff comparam sempre o ficheiro efetivamente editado, não
  necessariamente o root representado pela tab.
- `Discard Git Changes` repõe apenas o ficheiro editado para `HEAD`, numa única
  confirmação, e recompila o projeto pelo root.
- O source LaTeX usa highlighting específico para comandos, comentários,
  ambientes, argumentos e matemática, com fallback monoespaçado.

## Desenho técnico

### Sessão source comum

A sessão atualmente chamada `MarkdownEditSession` já é usada por Markdown e
JSON. Deve ser aprofundada para uma sessão source comum, evitando uma segunda
implementação paralela para LaTeX. A sessão concentra source base/atual,
Undo/Redo, estado de gravação, conflito e modo source/split/diff.

Markdown mantém o merge estrutural que já conhece blocos Markdown; LaTeX usa
merge de texto apropriado ao source TeX. A UI e o diff não devem conhecer essas
diferenças.

### Compilação com rascunho

`LocalLatexAdapter` deverá aceitar um override em memória para o ficheiro
editado. O adapter prepara uma sobreposição temporária com paths relativos
estáveis, compila o root nessa sobreposição, mantém o projeto original
intocado e devolve:

- PDF válido;
- dependências observadas pelo recorder;
- diagnóstico de compilação;
- dados SyncTeX suficientes para mapear posição PDF para source.

O pipeline existente de roots, engines, bibliografia, permissões externas,
shell escape, timeout e cache mantém-se. Previews de rascunho não devem
contaminar o cache persistente de previews guardados.

### Estado da tab e coordenação

`DocumentTab` passa a representar também a sessão LaTeX e o URL do source
contextual. `presentationMode` e `DocumentDiffCoordinator` deixam de assumir
que o source é sempre `tab.url`.

`AppModel` coordena o ciclo de vida: entrada por duplo clique, source/split,
alterações, debounce, gravação, descarte, conflitos, diffs e re-renderização.
O watcher observa o source editado, o root, dependências locais e dependências
externas autorizadas.

### UI

O editor LaTeX reutiliza a toolbar, action bar, diff view, gutter, pesquisa e
editor AppKit já usados pelo Markdown. A split view apresenta o source à
esquerda e o PDF à direita. O PDF recebe callbacks para duplo clique com
posição e routing de links.

## Fatias de implementação

Cada fatia começa por um teste focado, passa por uma implementação mínima e
termina com os testes relevantes e validação manual.

1. Generalizar a sessão source e os modos de apresentação para LaTeX.
2. Adicionar o URL editável contextual e baselines de Disk/Git baseados nesse
   URL.
3. Adicionar overrides temporários ao adapter LaTeX, preservando includes,
   imagens e bibliografia sem alterar a pasta do utilizador.
4. Gerar e interpretar SyncTeX, incluindo fallback quando a ferramenta/mapa
   não estiver disponível.
5. Adicionar highlighting LaTeX ao `SourceEditorView`.
6. Ligar o PDF à entrada por duplo clique, ao source editor e à split view.
7. Implementar preview live com debounce, cancelamento/gerações e último PDF
   válido.
8. Implementar Save, Esc, Discard Changes, conflitos externos e alterações em
   dependências.
9. Ligar Disk Diff, Git Diff e Discard Git Changes ao source contextual.
10. Ligar links internos, externos e ficheiros ao comportamento definido.
11. Atualizar o estado atual, arquitetura técnica, UI architecture e fixtures
    depois do comportamento estar implementado e validado.

## Testes

Os contratos puros ficam em `BPViewerCore` e são exercitados pelos testes e
pelos runners existentes. A ordem test-first cobre:

- transições source/split/diff e histórico Undo/Redo;
- root `main.tex` com capítulo incluído editado por override;
- garantia de que preview live não escreve no projeto original;
- preservação do PDF anterior em compilação falhada;
- dependências e bibliografia com source contextual;
- parsing/mapeamento SyncTeX e fallback;
- baselines de diff no ficheiro contextual;
- conflito no source editado e recompilação por dependência externa;
- routing de links PDF;
- transições observáveis do `AppModel` e da toolbar.

As fixtures manuais devem incluir documento multi-ficheiro, imagem, referências
cruzadas, bibliografia, erro de compilação e alteração externa sucessiva.

## Critérios de conclusão

- Duplo clique no PDF entra no source correto e usa SyncTeX quando disponível.
- Source e PDF funcionam em split view.
- Alterações atualizam o PDF após o debounce sem substituir resultados novos
  por resultados obsoletos.
- Undo/Redo, Save, Esc e Discard Changes têm o mesmo significado que no
  Markdown.
- Disk Diff e Git Diff mostram o ficheiro contextual correto.
- Conflitos externos protegem o rascunho e permitem escolher a versão.
- Erros de compilação preservam o último PDF válido e permitem guardar source.
- Links internos, externos e locais seguem as regras definidas.
- Testes, runners, build, `git diff --check` e validação manual passam.
- Depois de cada ronda que altera a app, `./scripts/restart-app.sh` conclui o
  build e abre a versão mais recente.

## Fora de escopo

- Editor multi-ficheiro completo com vários sources simultaneamente editáveis.
- Formatação semântica automática de LaTeX.
- Auto-save ou colaboração.
- Compilação por cada tecla sem debounce.
- Suporte garantido a SyncTeX quando a instalação LaTeX local não o produzir.

## Riscos

- Compilações longas podem exigir cancelamento real do processo, além da
  proteção por geração já usada pelo coordinator.
- A sobreposição temporária precisa de respeitar paths relativos complexos,
  `\\input`, `\\include`, `\\graphicspath` e bibliografia.
- Algumas engines ou distribuições podem não disponibilizar SyncTeX ou
  produzir mapas incompletos.
- Projetos grandes e dependências externas podem tornar o preview live caro.

## Referências

- [`docs/current-state.md`](docs/current-state.md)
- [`docs/technical/architecture.md`](docs/technical/architecture.md)
- [`docs/technical/ui-architecture.md`](docs/technical/ui-architecture.md)
- [`Sources/BPViewerCore/CONTEXT.md`](Sources/BPViewerCore/CONTEXT.md)
- [`Sources/BPViewerApp/CONTEXT.md`](Sources/BPViewerApp/CONTEXT.md)

# Plano: pesquisa unificada na tab ativa

## Objetivo

Tornar `⌘F` numa pesquisa consistente dentro da tab ativa do `bp-viewer`,
funcionando tanto nos previews como nos editores source, com a mesma barra
visual em todos os formatos suportados.

## Decisões de produto

- A pesquisa fica limitada ao documento da tab ativa.
- Os formatos suportados são Markdown, LaTeX/PDF, JSON e DOCX.
- A pesquisa funciona em previews e editores source.
- Em split view, o alvo é o painel que tem o foco; sem foco explícito, usa o
  preview.
- A correspondência é texto simples, case-insensitive e sem distinção de
  acentos.
- `Enter` avança, `Shift+Enter` recua e `Esc` fecha a barra.
- A barra de pesquisa é única e consistente em todas as superfícies.
- Ficheiros não suportados continuam a abrir pela aplicação do macOS e ficam
  fora da pesquisa interna.
- Pesquisa global no workspace, regex, palavra inteira e outras opções
  avançadas ficam fora deste plano.

## Desenho

O `AppModel` mantém o estado e os intents pequenos da pesquisa; a barra comum
trata a apresentação e os adapters específicos tratam a integração com cada
superfície. A interface comum deve esconder as diferenças entre WebKit,
PDFKit e `NSTextView`, sem criar um módulo que conheça todos os frameworks.

Adapters previstos:

- WebKit para Markdown, JSON e DOCX;
- PDFKit para PDF e os previews LaTeX;
- `NSTextView` para os editores source Markdown e JSON.

Cada adapter deve suportar atualizar a query, selecionar/destacar resultados,
navegar para o resultado seguinte/anterior e limpar a pesquisa. A seleção do
alvo deve seguir o foco real no split view.

## Trabalho

1. Registar as regras puras de correspondência e navegação com testes
   independentes da UI.
2. Expandir o estado e os intents de pesquisa no `AppModel` para todos os tipos
   suportados.
3. Criar uma barra de pesquisa comum, reutilizável por previews e editores.
4. Ligar a barra aos adapters WebKit, PDFKit e `NSTextView`.
5. Fazer `⌘F`, `Enter`, `Shift+Enter` e `Esc` respeitarem o painel com foco.
6. Garantir resultados destacados, navegação, limpeza e o estado sem resultados
   em cada superfície.
7. Atualizar `docs/current-state.md`, `docs/technical/ui-architecture.md` e a
   documentação dos atalhos.
8. Validar todos os formatos, modos de edição, split view e temas claro/escuro.

## Critérios de conclusão

- `⌘F` abre a mesma barra em todos os formatos suportados.
- A pesquisa ocorre apenas na tab ativa.
- Preview e editor source apresentam comportamento equivalente.
- O foco define o alvo no split view.
- A pesquisa é case-insensitive e sem distinção de acentos.
- Enter, Shift+Enter e Esc funcionam de forma consistente.
- Existem testes para correspondência e navegação.
- A documentação canónica descreve o comportamento implementado.
- `swift test`, os runners, a build e `git diff --check` passam.
- `./scripts/restart-app.sh` conclui o build e abre a versão mais recente para
  teste manual.

## Fora de escopo

- Pesquisa global em todos os ficheiros do workspace.
- Pesquisa em ficheiros delegados para aplicações externas.
- Regex, palavra inteira, filtros avançados ou indexação persistente.

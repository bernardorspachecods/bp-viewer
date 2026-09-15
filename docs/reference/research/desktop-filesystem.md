# Brief de pesquisa: desktop e filesystem

## Objetivo

Determinar a arquitetura mínima de uma aplicação desktop para macOS que navegue por pastas locais, observe alterações e coordene os adapters de renderização sem editar os ficheiros-fonte.

## Pergunta principal

Que opções de shell desktop e integração com o filesystem oferecem o fluxo mais simples e fiável para o `bp-viewer` pessoal, mantendo abertas as escolhas dos adapters?

## Deve investigar

- opções de aplicação desktop adequadas ao macOS e os seus custos operacionais;
- acesso a pastas, seleção de diretórios, navegação hierárquica e permissões;
- APIs ou bibliotecas de file watching e comportamento em renomeações, remoções, escritas atómicas e alterações rápidas;
- debounce, filas de renderização, cancelamento e prevenção de condições de corrida;
- descoberta de dependências relacionadas com o ficheiro visualizado;
- execução e supervisão de processos externos;
- comunicação entre shell, adapter e superfície de preview;
- consumo de memória, arranque, empacotamento e manutenção;
- associação de ficheiros, drag-and-drop e abertura de uma pasta, apenas quando relevantes para o MVP;
- limitações específicas do macOS e custos de permissões persistentes.

## Fora do escopo

- escolher o parser Markdown ou a estratégia LaTeX;
- fazer uma análise detalhada de segurança de WebViews e PDFs;
- criar a aplicação ou um protótipo;
- suportar Windows ou Linux no MVP;
- substituir completamente o Finder ou construir um gestor de ficheiros geral.

Pode comparar tecnologias concretas, mas deve começar pelos requisitos e não por uma preferência de framework.

## Cenários mínimos a avaliar

- abrir uma pasta com subpastas e muitos ficheiros;
- o LLM substituir um ficheiro através de escrita atómica;
- várias alterações consecutivas enquanto existe uma compilação em curso;
- alterar um ficheiro incluído sem alterar o ficheiro aberto;
- perder e recuperar permissões de acesso a uma pasta.

## Resultado específico

Entregar uma comparação das opções de shell e integração local, uma recomendação condicional para o MVP, os contratos necessários entre componentes e os testes de filesystem que devem ser feitos antes de congelar a arquitetura.

Usar o [formato comum do plano](CONTEXT.md#formato-de-entrega). Remeter segurança detalhada e distribuição para o brief próprio, evitando duplicação.

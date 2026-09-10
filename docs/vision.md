# Visão e plano atual

## Objetivo

Criar uma aplicação desktop pessoal para macOS que permita navegar por uma pasta local e visualizar, de forma bonita e atualizada, ficheiros Markdown e LaTeX.

## Problema

Durante a escrita de uma tese, um LLM ou outra ferramenta pode alterar diretamente os ficheiros raw. O utilizador precisa de abrir esses ficheiros noutros programas ou serviços para confirmar o resultado final, interrompendo o fluxo de trabalho.

## Experiência pretendida

1. O utilizador abre uma pasta do computador como projeto.
2. Navega por subpastas e ficheiros numa árvore semelhante à navegação habitual no computador.
3. Seleciona um ficheiro Markdown ou LaTeX.
4. A aplicação apresenta o resultado renderizado.
5. Se o ficheiro ou uma dependência mudar externamente, a aplicação atualiza o preview automaticamente.

## Decisões de UX confirmadas

### Navegação

- O utilizador pode abrir qualquer pasta como raiz.
- A árvore apresenta essa pasta e os seus descendentes.
- Um toggle permite alternar entre:
  - mostrar apenas ficheiros compatíveis, ativo por defeito;
  - mostrar todos os ficheiros.
- Com o filtro ativo, devem ficar ocultas as pastas que não contenham nenhum `.md` ou `.tex` nos seus descendentes.
- A árvore deve mostrar primeiro as pastas e depois os ficheiros, ambos por ordem alfabética.
- A pasta-raiz começa expandida; as restantes pastas começam fechadas.
- A árvore deve suportar navegação por teclado, incluindo seleção, abertura e expansão/fecho.
- O estado expandido/fechado das pastas deve ser restaurado ao reabrir o projeto.
- O menu para abrir pastas deve apresentar pastas recentes, mantendo essa informação local.
- Uma pasta sem ficheiros compatíveis deve apresentar uma mensagem explicativa, sem esconder a própria árvore.
- Ficheiros ou pastas sem acesso devem continuar visíveis com um indicador de acesso bloqueado.
- Ficheiros ocultos do macOS ficam escondidos por defeito.
- A árvore deve ter pesquisa própria por nome ou caminho, separada da pesquisa do preview.
- A pesquisa da árvore deve mostrar também pastas que contenham resultados nos descendentes.
- Clicar numa pasta deve apenas expandi-la ou fechá-la, sem alterar o preview ativo.
- Ao ativar uma tab, o ficheiro correspondente deve ficar visível na árvore.
- O filtro altera a navegação, não a resolução interna de dependências pelos adapters.

### Preview e atualização

- O MVP apresenta apenas o preview renderizado; não inclui editor.
- Alterações externas devem atualizar automaticamente o preview.
- A atualização deve usar debounce para evitar renders excessivos ou estados incompletos.
- A interface deve indicar se o preview está a atualizar, atualizado ou com erro.
- Quando uma alteração causa um erro, a área principal mostra os detalhes do erro por defeito.
- O utilizador pode pedir para ver o último preview válido, que deve ser identificado claramente como desatualizado.
- Depois de uma atualização automática, a app deve tentar preservar a posição de leitura.
- Markdown deve suportar matemática delimitada, como `$x^2$` e `$$...$$`.
- A tab ou topbar deve mostrar contexto suficiente do caminho relativo do ficheiro ativo para distinguir ficheiros com o mesmo nome.
- Links para ficheiros `.md` ou `.tex` dentro da pasta aberta devem abrir ou focar esses ficheiros numa tab.
- Links externos devem abrir no browser normal, mediante uma ação explícita do utilizador.
- Imagens locais referenciadas por Markdown devem aparecer no preview.
- Imagens remotas referenciadas por URL também devem aparecer no preview; a aplicação pode fazer pedidos à internet e esses recursos podem não estar disponíveis offline.
- HTML raw em Markdown deve ser aceite apenas depois de sanitizado.
- Links locais para ficheiros não suportados devem abrir o programa predefinido do macOS mediante uma ação explícita.
- O preview LaTeX/PDF deve usar scroll contínuo por defeito, com paginação visual normal.
- O preview deve mostrar quando foi atualizado pela última vez.
- A topbar deve incluir um botão para alternar manualmente entre tema claro e escuro.
- A pesquisa (`⌘F`) deve atuar apenas sobre o conteúdo renderizado da tab atual.
- O preview deve permitir aumentar, diminuir e repor o zoom através da topbar e dos atalhos `⌘+`, `⌘-` e `⌘0`.
- O utilizador deve poder navegar por um índice/outline do documento quando essa estrutura estiver disponível.
- O texto do preview deve poder ser selecionado e copiado com `⌘C`.
- A topbar deve incluir uma ação para forçar a atualização ou recompilação da tab atual.
- `⌘R` deve forçar a atualização ou recompilação da tab atual.

### LaTeX

- Ao abrir um ficheiro `.tex`, a aplicação deve tentar identificar o ficheiro principal do projeto e compilar o documento completo.
- Se não encontrar um ficheiro principal ou encontrar vários candidatos, a aplicação deve pedir ao utilizador para escolher.
- A escolha manual do documento principal deve ser memorizada por projeto.
- O utilizador deve poder alterar posteriormente o documento principal escolhido.
- A abertura de um `.tex` deve iniciar automaticamente a compilação.
- O MVP deve usar uma instalação local de LaTeX; a app não precisa de incluir o compilador.
- O resultado LaTeX deve ser apresentado como PDF compilado dentro da app.
- Se o LaTeX não estiver disponível, a tab deve mostrar um erro específico com instruções de configuração, ação para voltar a tentar e opção para copiar o diagnóstico; isto não deve impedir o uso do Markdown.
- Os erros de compilação devem permitir expandir o log completo e copiá-lo.
- Dependências LaTeX fora da pasta-raiz exigem confirmação explícita.
- Alterações num capítulo ou noutra dependência devem recompilar automaticamente o documento principal.
- Um capítulo LaTeX aberto deve focar a tab do documento principal, em vez de criar uma tab duplicada para o capítulo.

### Tabs

- O MVP suporta várias tabs.
- Cada ficheiro deve ter no máximo uma tab aberta; ao abrir um ficheiro já aberto, a aplicação foca a tab existente.
- Quando tabs tiverem o mesmo nome de ficheiro, devem mostrar também contexto da pasta-pai.
- As tabs devem ser restauradas depois de reiniciar a aplicação.
- A restauração deve preservar, pelo menos, as referências aos ficheiros, a ordem e a tab ativa.
- A aplicação deve restaurar também a posição de leitura de cada tab.
- A escolha entre tema claro e escuro deve ser restaurada ao reiniciar.
- O tamanho da janela e a largura da sidebar devem ser restaurados ao reiniciar.
- A escolha da tab não deve impedir o fecho da app durante uma compilação ativa.
- O menu contextual das tabs deve permitir fechar as outras tabs e as tabs à direita.
- `⌘W` deve fechar a tab atual e `⌘1`–`⌘9` devem permitir mudar rapidamente entre tabs.
- `Control-Tab` deve avançar para a tab seguinte e voltar à primeira depois da última.
- A aplicação guarda referências aos ficheiros, não cópias do seu conteúdo.

### Abertura a partir do Finder

- O utilizador pode abrir diretamente ficheiros `.md` e `.tex` a partir do Finder.
- Ao abrir um ficheiro diretamente, a aplicação deve abrir também a pasta que o contém como raiz.
- O ficheiro aberto deve ser adicionado ou focado numa tab.
- No caso de LaTeX, a descoberta do documento principal continua a aplicar-se.
- `⌘O` deve permitir abrir uma pasta.
- Ao abrir outra pasta com tabs existentes, a aplicação deve pedir confirmação antes de substituir o projeto atual.
- Uma pasta ou ficheiro pode ser arrastado do Finder para a app.
- O menu contextual de um ficheiro deve permitir mostrá-lo no Finder, copiar o seu caminho e abri-lo no editor predefinido do sistema.
- O menu contextual deve permitir copiar também o caminho relativo à pasta-raiz.
- Deve existir uma ação para revelar na árvore o ficheiro correspondente à tab ativa.

### Evolução futura

- Uma versão futura poderá combinar um editor raw à esquerda com o viewer renderizado à direita.
- A separação entre edição e preview deve ser preservada na arquitetura, apesar de o editor estar fora do MVP.
- Abrir o ficheiro no editor predefinido é apenas uma ponte no MVP; não substitui o editor integrado previsto para o futuro.

## Escopo do MVP

- Aplicação local para macOS.
- Abertura e navegação de pastas do computador.
- Árvore de ficheiros e subpastas.
- Preview renderizado de ficheiros `.md`.
- Preview renderizado de ficheiros `.tex`.
- Observação de alterações no sistema de ficheiros.
- Atualização automática do preview.
- Apresentação legível de erros de renderização ou compilação.
- Toggle para filtrar a árvore por ficheiros compatíveis, ativo por defeito.
- Ordenação previsível da árvore e ocultação de pastas sem ficheiros compatíveis.
- Várias tabs com restauração após reinício.
- Restauração da última pasta, posição de leitura, ordem das tabs e tab ativa.
- Controlos de tema, pesquisa, zoom, outline, cópia e atualização manual.
- Abertura direta de `.md` e `.tex` a partir do Finder.
- Abertura de pastas e ficheiros por atalhos, drag & drop e menu contextual.
- Navegação interna entre ficheiros compatíveis através de links.
- Funcionamento sem conta, cloud ou base de dados.
- Aplicação sem edição dos ficheiros-fonte.

## Fora do escopo inicial

- Editor de Markdown ou LaTeX.
- Integração obrigatória com um LLM.
- Sincronização cloud.
- Colaboração entre utilizadores.
- Suporte multiplataforma no MVP.
- Gestão avançada de projetos académicos.

## Modelo de renderização

### Markdown

Hipótese inicial: converter Markdown para HTML através de um adapter e apresentar o resultado numa WebView estilizada. A implementação concreta do suporte já confirmado para matemática, imagens, links e HTML sanitizado será definida na pesquisa técnica.

### LaTeX

Hipótese inicial: usar uma instalação local de LaTeX e apresentar o resultado compilado como PDF dentro da app. A distribuição concreta, deteção da instalação e integração do processo permanecem dependentes da pesquisa e dos testes locais.

Os artefactos temporários de compilação não devem poluir a pasta do projeto do utilizador.

## Decisões confirmadas

- Nome do projeto: `bp-viewer`.
- Uso pessoal.
- Primeira plataforma: macOS.
- Repository GitHub privada.
- A implementação do MVP deve privilegiar uma app nativa de macOS, sem compromisso com Windows ou Linux.
- A distribuição inicial destina-se apenas ao uso pessoal fora da App Store, por build local ou pacote direto.
- O alvo inicial é a versão atual do macOS; versões futuras devem ser acompanhadas, sem compromisso com versões antigas.
- O MVP deve ser otimizado primeiro para a tese atual de Bernardo, não para suportar genericamente todos os projetos LaTeX.
- A tese pode usar `biber`, TikZ/PGFPlots, fontes especiais, `shell escape` e ferramentas externas; a compatibilidade deve ser validada com ficheiros reais.
- Recursos fora da pasta-raiz são permitidos mediante confirmação explícita.
- A utilização normal pressupõe ligação à internet; imagens remotas em Markdown são permitidas e podem falhar quando não houver rede.
- A recompilação deve ser otimizada através de agrupamento de alterações, análise de dependências, cancelamento de trabalhos obsoletos e reutilização de cache, sem assumir que é seguro compilar apenas páginas isoladas de um documento LaTeX.
- As configurações avançadas de LaTeX devem existir no MVP numa área discreta, mantendo o fluxo normal simples.
- Funcionalidades académicas avançadas, como bookmarks, notas e ferramentas adicionais de referências, ficam para o futuro.
- A interface deve seguir um sistema visual documentado e reutilizável, com primitivas e tokens consistentes em vez de estilos locais hardcoded.
- Os ficheiros raw permanecem fora do controlo de edição da aplicação.
- A app deve ser independente do LLM que altera os ficheiros.
- A app não deve impor restrições artificiais ao acesso dos ficheiros pessoais; as permissões efetivas continuam a ser controladas pelo macOS.
- A estrutura documental começa com um `README.md` na raiz e documentos relacionados em `docs/`.

## Hipóteses ainda abertas

- Adapter e parser de Markdown.
- Implementação concreta do suporte já definido para matemática, imagens, links, HTML sanitizado e imagens remotas em Markdown.
- Integração concreta da compilação e apresentação do PDF LaTeX.
- Dependências locais necessárias para LaTeX.
- Semântica exata da deteção de alterações, debounce e coordenação de renders.
- Algoritmo exato para identificar o ficheiro principal LaTeX.
- Metadados adicionais a restaurar nas tabs.

## Implicações ainda não decididas

As seguintes consequências são esperadas pela experiência escolhida, mas não constituem decisões técnicas finais:

- cada tab deverá manter estado de preview e diagnóstico independente;
- a resolução de dependências deverá continuar a funcionar mesmo quando ficheiros auxiliares estão ocultos pelo filtro;
- a fila de renderização poderá limitar compilações simultâneas para proteger o desempenho.

Estas hipóteses não devem ser tratadas como decisões finais sem pesquisa ou validação através de um protótipo.

## Cenário de sucesso do MVP

O utilizador abre a pasta de uma tese, seleciona um capítulo Markdown ou LaTeX, pede a um LLM para alterar o ficheiro raw e vê a versão renderizada atualizar-se sem ter de mudar de aplicação ou abrir o Finder.

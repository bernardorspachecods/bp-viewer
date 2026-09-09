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
- O filtro altera a navegação, não a resolução interna de dependências pelos adapters.

### Preview e atualização

- O MVP apresenta apenas o preview renderizado; não inclui editor.
- Alterações externas devem atualizar automaticamente o preview.
- A atualização deve usar debounce para evitar renders excessivos ou estados incompletos.
- A interface deve indicar se o preview está a atualizar, atualizado ou com erro.
- Quando uma alteração causa um erro, a área principal mostra os detalhes do erro por defeito.
- O utilizador pode pedir para ver o último preview válido, que deve ser identificado claramente como desatualizado.
- Links para ficheiros `.md` ou `.tex` dentro da pasta aberta devem abrir ou focar esses ficheiros numa tab.
- Links externos devem abrir no browser normal, mediante uma ação explícita do utilizador.
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
- Um capítulo LaTeX aberto deve focar a tab do documento principal, em vez de criar uma tab duplicada para o capítulo.

### Tabs

- O MVP suporta várias tabs.
- Cada ficheiro deve ter no máximo uma tab aberta; ao abrir um ficheiro já aberto, a aplicação foca a tab existente.
- As tabs devem ser restauradas depois de reiniciar a aplicação.
- A restauração deve preservar, pelo menos, as referências aos ficheiros, a ordem e a tab ativa.
- A aplicação deve restaurar também a posição de leitura de cada tab.
- `⌘W` deve fechar a tab atual e `⌘1`–`⌘9` devem permitir mudar rapidamente entre tabs.
- A aplicação guarda referências aos ficheiros, não cópias do seu conteúdo.

### Abertura a partir do Finder

- O utilizador pode abrir diretamente ficheiros `.md` e `.tex` a partir do Finder.
- Ao abrir um ficheiro diretamente, a aplicação deve abrir também a pasta que o contém como raiz.
- O ficheiro aberto deve ser adicionado ou focado numa tab.
- No caso de LaTeX, a descoberta do documento principal continua a aplicar-se.
- `⌘O` deve permitir abrir uma pasta.
- Uma pasta ou ficheiro pode ser arrastado do Finder para a app.
- O menu contextual de um ficheiro deve permitir mostrá-lo no Finder, copiar o seu caminho e abri-lo no editor predefinido do sistema.

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

Hipótese inicial: converter Markdown para HTML através de um adapter e apresentar o resultado numa WebView estilizada. O suporte concreto para matemática, imagens, links e variantes de Markdown será definido na pesquisa técnica.

### LaTeX

Hipótese inicial: usar uma instalação local de LaTeX e apresentar o resultado compilado. A escolha entre PDF, HTML ou outra estratégia permanece aberta até à pesquisa dos adapters e das necessidades reais dos documentos.

Os artefactos temporários de compilação não devem poluir a pasta do projeto do utilizador.

## Decisões confirmadas

- Nome do projeto: `bp-viewer`.
- Uso pessoal.
- Primeira plataforma: macOS.
- Repository GitHub privada.
- Os ficheiros raw permanecem fora do controlo de edição da aplicação.
- A app deve ser independente do LLM que altera os ficheiros.
- A estrutura documental começa com um `README.md` na raiz e documentos relacionados em `docs/`.

## Hipóteses ainda abertas

- Adapter e parser de Markdown.
- Suporte de matemática, imagens, links e ficheiros relacionados em Markdown.
- Estratégia de renderização de LaTeX.
- Dependências locais necessárias para LaTeX.
- Deteção de alterações e momento adequado para atualizar ou recompilar.
- Tecnologia da aplicação desktop.
- Algoritmo exato para identificar o ficheiro principal LaTeX e forma de guardar essa escolha.
- Política para dependências localizadas fora da pasta-raiz.
- Metadados adicionais a restaurar nas tabs e comportamento quando um ficheiro já não existe.

## Implicações ainda não decididas

As seguintes consequências são esperadas pela experiência escolhida, mas não constituem decisões técnicas finais:

- cada tab deverá manter estado de preview e diagnóstico independente;
- a resolução de dependências deverá continuar a funcionar mesmo quando ficheiros auxiliares estão ocultos pelo filtro;
- a fila de renderização poderá limitar compilações simultâneas para proteger o desempenho.

Estas hipóteses não devem ser tratadas como decisões finais sem pesquisa ou validação através de um protótipo.

## Cenário de sucesso do MVP

O utilizador abre a pasta de uma tese, seleciona um capítulo Markdown ou LaTeX, pede a um LLM para alterar o ficheiro raw e vê a versão renderizada atualizar-se sem ter de mudar de aplicação ou abrir o Finder.

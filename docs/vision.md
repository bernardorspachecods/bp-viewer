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

## Escopo do MVP

- Aplicação local para macOS.
- Abertura e navegação de pastas do computador.
- Árvore de ficheiros e subpastas.
- Preview renderizado de ficheiros `.md`.
- Preview renderizado de ficheiros `.tex`.
- Observação de alterações no sistema de ficheiros.
- Atualização automática do preview.
- Apresentação legível de erros de renderização ou compilação.
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

Estas hipóteses não devem ser tratadas como decisões finais sem pesquisa ou validação através de um protótipo.

## Cenário de sucesso do MVP

O utilizador abre a pasta de uma tese, seleciona um capítulo Markdown ou LaTeX, pede a um LLM para alterar o ficheiro raw e vê a versão renderizada atualizar-se sem ter de mudar de aplicação ou abrir o Finder.

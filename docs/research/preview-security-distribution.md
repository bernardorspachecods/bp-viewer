# Brief de pesquisa: preview, segurança e distribuição

## Objetivo

Determinar como apresentar HTML e resultados LaTeX localmente e como reduzir riscos e fricção operacional ao executar a aplicação no macOS.

## Pergunta principal

Que combinação de superfícies de preview, isolamento, permissões e empacotamento permite visualizar conteúdo local com segurança suficiente e uma experiência simples para uso pessoal?

## Deve investigar

- WebViews e superfícies equivalentes para HTML local;
- visualização de PDF e as suas capacidades relevantes para leitura;
- isolamento de conteúdo, execução de JavaScript, navegação, links e acesso a ficheiros locais;
- sanitização e defesa em profundidade para Markdown e HTML gerados ou alterados externamente;
- riscos de abrir imagens, links, PDFs, bibliografias e outros artefactos locais;
- execução de compiladores e processos auxiliares com limites, diretórios de trabalho e permissões adequados;
- macOS sandboxing, entitlements, permissões de ficheiros e persistência de acesso;
- assinatura, notarização, distribuição e atualização para uma app pessoal;
- implicações de licenciamento e empacotamento das dependências de preview;
- mensagens de erro e recuperação quando o conteúdo ou uma dependência não é segura ou não pode ser aberta.

## Fora do escopo

- criar um modelo completo de ameaça para distribuição pública;
- decidir o parser Markdown ou o compilador LaTeX;
- implementar autenticação, cloud ou colaboração;
- otimizar para sistemas operativos que não sejam macOS;
- assumir que uso pessoal elimina todos os riscos de executar conteúdo local.

Deve distinguir riscos teóricos, riscos plausíveis no fluxo do MVP e requisitos necessários para distribuição fora do computador do utilizador.

## Cenários mínimos a avaliar

- um Markdown contém HTML ou JavaScript incorporado;
- um documento referencia imagens e ficheiros fora da pasta aberta;
- um PDF ou link aponta para conteúdo inesperado;
- um compilador recebe um projeto com comandos ou pacotes problemáticos;
- a app é aberta pela primeira vez num macOS com permissões restritas.

## Resultado específico

Entregar uma comparação das opções de preview e das medidas de isolamento, uma recomendação condicional para o MVP pessoal, requisitos de distribuição e uma lista de riscos que devem ser aceites, mitigados ou adiados explicitamente.

Usar o [formato comum do plano](README.md#formato-de-entrega). Não classificar uma opção como “segura” sem delimitar o modelo de ameaça e a evidência que sustenta a afirmação.

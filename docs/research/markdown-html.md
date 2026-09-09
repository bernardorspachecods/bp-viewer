# Brief de pesquisa: Markdown → HTML

## Objetivo

Determinar quais as abordagens tecnicamente viáveis para converter ficheiros Markdown locais em HTML renderizado dentro do `bp-viewer`, preservando um fluxo de atualização automática e uma experiência de leitura adequada a uma tese.

## Pergunta principal

Que parser e pipeline Markdown → HTML oferecem o melhor equilíbrio entre fidelidade, extensibilidade, suporte a conteúdo académico, funcionamento offline, segurança e complexidade para o MVP em macOS?

## Deve investigar

- variantes de Markdown relevantes e compatibilidade com documentos reais;
- arquitetura do parser e extensão por plugins ou transformações;
- matemática, blocos de código, tabelas, citações, notas e referências;
- imagens, links relativos, âncoras e referências entre ficheiros;
- CSS, temas e controlo do HTML gerado;
- sanitização e tratamento de conteúdo local potencialmente perigoso;
- atualização depois de alterações externas e custo de re-renderização;
- dependências, execução offline, licenciamento e manutenção;
- diferenças entre renderização no cliente e pré-renderização no processo local;
- casos em que Markdown não consegue reproduzir requisitos académicos sem ferramentas adicionais.

## Fora do escopo

- escolher a framework desktop;
- desenhar a interface completa;
- implementar o adapter;
- decidir features de edição;
- fazer uma comparação genérica de todos os parsers existentes.

Pode registar dependências da WebView ou do desktop quando forem materialmente relevantes, mas remeter a análise detalhada para os briefs correspondentes.

## Cenários mínimos a avaliar

- um capítulo Markdown com matemática e imagens relativas;
- um documento com subpastas e links para outros ficheiros;
- uma alteração frequente feita por um processo externo;
- HTML ou Markdown com conteúdo que não deve poder executar scripts arbitrários.

## Resultado específico

Entregar uma comparação de abordagens descobertas, uma recomendação condicional para o MVP, os requisitos que a podem alterar e uma lista curta de testes locais necessários para validar a escolha.

Usar o [formato comum do plano](README.md#formato-de-entrega) e não apresentar uma preferência como facto.

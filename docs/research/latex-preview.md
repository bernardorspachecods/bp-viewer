# Brief de pesquisa: LaTeX → preview

## Objetivo

Determinar como o `bp-viewer` deve processar documentos LaTeX locais e apresentar um preview útil, considerando documentos de tese reais e alterações feitas por ferramentas externas.

## Pergunta principal

Que estratégias de processamento e apresentação de LaTeX são viáveis no macOS para o MVP — incluindo os seus custos, dependências, limitações e qualidade de resultado?

## Deve investigar

- estratégias de saída visualmente relevantes, incluindo PDF, HTML ou abordagens híbridas;
- engines, compiladores, wrappers e ferramentas de build local materialmente viáveis;
- dependência de MacTeX, TeX Live, MiKTeX ou alternativas, sem assumir nenhuma como obrigatória;
- documentos multi-ficheiro, `\input`, `\include`, imagens, bibliografia e referências cruzadas;
- deteção de dependências e recompilação após alterações externas;
- compilação incremental, tempos de espera e concorrência entre compilações;
- localização de artefactos temporários sem poluir o projeto do utilizador;
- extração e apresentação de erros e avisos de compilação;
- pacotes LaTeX incompatíveis, casos que exigem interação e limites de execução;
- permissões, processos externos, licenciamento e distribuição no macOS;
- fidelidade do resultado para uma tese e implicações de acessibilidade ou pesquisa no preview.

## Fora do escopo

- escolher a framework desktop ou o visualizador final;
- implementar um compilador ou um sistema de build;
- assumir que HTML é necessariamente melhor que PDF, ou vice-versa;
- investigar editores LaTeX completos;
- decidir funcionalidades de escrita ou colaboração.

Deve indicar claramente que partes dependem do viewer e da arquitetura envolvente, remetendo a análise detalhada para os briefs correspondentes.

## Cenários mínimos a avaliar

- um `main.tex` que inclui vários capítulos;
- bibliografia e referências cruzadas que exigem mais de uma passagem;
- uma imagem ou pacote ausente;
- alterações sucessivas no ficheiro principal e num ficheiro incluído;
- uma compilação que falha ou fica bloqueada.

## Resultado específico

Entregar uma comparação das estratégias descobertas, uma recomendação condicional para o MVP, pré-requisitos locais, principais riscos e um plano de testes com documentos LaTeX representativos.

Usar o [formato comum do plano](README.md#formato-de-entrega) e separar capacidade documentada de adequação inferida ao `bp-viewer`.

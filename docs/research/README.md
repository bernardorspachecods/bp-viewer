# Plano de pesquisa técnica

## Objetivo

Produzir evidência suficiente para escolher uma implementação viável dos adapters de Markdown e LaTeX e da arquitetura local que os integra no `bp-viewer`, sem antecipar decisões de produto nem implementação.

## Resultado pretendido

Quatro agentes investigam áreas independentes e entregam relatórios comparáveis. Depois, Bernardo e Codex fazem a síntese, identificam incompatibilidades e decidem as features e decisões técnicas do MVP.

Os agentes de pesquisa não devem implementar código, criar um protótipo ou fechar decisões de produto em nome do projeto.

## Áreas de pesquisa

1. [Markdown → HTML](markdown-html.md)
2. [LaTeX → preview](latex-preview.md)
3. [Desktop e filesystem](desktop-filesystem.md)
4. [Preview, segurança e distribuição](preview-security-distribution.md)

## Relatórios recebidos

Os relatórios completos dos agentes ficam separados dos briefs para preservar a distinção entre instruções de pesquisa e resultados. Ainda não representam decisões técnicas aprovadas.

- [Relatório: Markdown → HTML](reports/markdown-html.md)
- [Relatório: LaTeX → preview](reports/latex-preview.md)
- [Relatório: desktop e filesystem](reports/desktop-filesystem.md)
- [Relatório: preview, segurança e distribuição](reports/preview-security-distribution.md)

Todos os agentes devem ler [a visão e o plano atual](../vision.md) antes de pesquisar e devem tratar as suas decisões técnicas como recomendações condicionais, não como requisitos já aprovados.

## Método comum

Esta é uma pesquisa técnica comparativa de nível standard.

### Regras de independência

- Não assumir uma framework, linguagem, compilador, parser ou formato de saída antes de investigar alternativas.
- Não usar popularidade, rankings, memória ou snippets de pesquisa como evidência.
- Distinguir claramente capacidade documentada, adequação ao `bp-viewer` e preferência do investigador.
- Não contar páginas que repetem a mesma origem como corroboração independente.
- Procurar limitações, incompatibilidades, issues, custos operacionais e alternativas plausíveis.
- Não transformar uma recomendação do fornecedor em prova de superioridade.
- Se a evidência for insuficiente, marcar a conclusão como incerta ou parcialmente suportada.

### Evidência mínima

Para cada capacidade ou limitação material, usar documentação oficial, especificações, repositórios oficiais, changelogs, issues relevantes ou outra fonte primária próxima do facto. Para comparações de qualidade, desempenho, segurança, facilidade ou fiabilidade, procurar evidência comparativa independente; se não existir, apresentar a comparação como inferência limitada.

Verificar versão, data de publicação ou atualização e data de acesso para software volátil. Não generalizar resultados de benchmarks ou exemplos para além das condições em que foram obtidos.

### Registo obrigatório

Cada relatório deve conter:

- uma matriz de claims `C1`, `C2`, etc.;
- evidência `E1`, `E2`, etc., ligada aos claims que suporta;
- registo compacto das pesquisas e caminhos de descoberta `Q1`, `Q2`, etc.;
- ledger das fontes usadas e rejeitadas;
- alternativas e tentativas de refutação;
- conflitos, limitações e lacunas;
- recomendação final como inferência, com confiança calibrada;
- razão para parar a pesquisa.

Um claim material sem evidência associada não deve ser apresentado como facto.

## Critérios comuns de avaliação

Aplicar apenas os critérios relevantes para cada área, sem inventar pesos numéricos:

- adequação ao fluxo do MVP;
- funcionamento offline e local;
- integração com ficheiros e dependências externas;
- atualização após alterações feitas por processos externos;
- qualidade e fidelidade do preview;
- desempenho e previsibilidade;
- tratamento de erros;
- segurança e permissões;
- complexidade operacional e de manutenção;
- licenciamento e distribuição;
- maturidade, manutenção e compatibilidade com macOS.

Se dois critérios entrarem em conflito, explicar o trade-off em vez de escondê-lo numa pontuação.

## Formato de entrega

Cada agente deve usar este formato no seu relatório:

1. **Resumo executivo** — conclusão principal em poucas linhas.
2. **Pergunta e decisão suportada** — o que foi investigado e o que a pesquisa permite decidir.
3. **Escopo e pressupostos** — incluindo o que ficou deliberadamente fora.
4. **Critérios de avaliação** — e a razão para serem relevantes.
5. **Matriz de claims** — `C#`, importância, estado, evidência e limitações.
6. **Alternativas investigadas** — incluindo abordagens rejeitadas ou não adequadas.
7. **Comparação fundamentada** — capacidades, trade-offs e condições de validade.
8. **Evidência** — entradas `E#` com fonte, passagem ou dado, o que estabelece e o que não estabelece.
9. **Conflitos e refutações** — resultados que enfraquecem as conclusões.
10. **Recomendação condicional** — opção preferida, contexto em que muda e confiança.
11. **Implicações para o MVP** — impactos, dependências e perguntas para a síntese; não novas features decididas.
12. **Lacunas e próximos testes** — o que só um protótipo ou teste local pode resolver.
13. **Ledger de fontes e registo de pesquisa** — datas, versões, origem, independência e motivo de inclusão ou rejeição.

Os relatórios devem usar links diretos para as fontes. A pesquisa web deve ser feita durante a execução do brief, não preenchida com conhecimento prévio.

## Handoff para a síntese

Depois dos quatro relatórios, a síntese deve:

- separar factos confirmados de inferências e preferências;
- comparar dependências e pressupostos incompatíveis;
- identificar decisões de produto que ainda pertencem ao utilizador;
- propor apenas o menor conjunto de decisões necessário para um protótipo;
- atualizar a [visão e plano atual](../vision.md) somente depois de as decisões serem confirmadas.

Não criar uma recomendação única antes de ler os quatro relatórios.

O estado atual é de quatro relatórios recebidos e ainda não sintetizados. As decisões de produto continuam a ser mantidas em [docs/vision.md](../vision.md).

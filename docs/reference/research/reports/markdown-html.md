# Relatório de investigação: Markdown → HTML

Data da investigação: 2026-09-09  
Repositório consultado: [arquivo da pesquisa](../CONTEXT.md), [brief Markdown](../markdown-html.md) e [estado atual](../../../current-state.md).

## 1. Resumo executivo

A melhor opção depende do runtime desktop ainda não escolhido:

- Se for aceitável empacotar JavaScript, a opção mais completa é uma pipeline local baseada em `remark`/`unified`: CommonMark + GFM + matemática → AST → transformação de links/âncoras → HTML → sanitização.
- Se o MVP exigir uma integração nativa sem runtime JavaScript, `cmark-gfm` é uma base pequena, rápida e sem dependências externas, mas exige trabalho próprio para reescrita de links, âncoras, matemática e controlo fino do HTML.
- `markdown-it` é uma alternativa equilibrada para HTML direto e sintaxes personalizadas, mas matemática e footnotes dependem de componentes separados.
- `swift-markdown` é interessante num projeto Swift, mas não elimina a necessidade de criar um renderer HTML e validar cuidadosamente footnotes, URLs e HTML seguro.

A recomendação condicional é:

> Preferir uma pipeline local AST-aware baseada em `remark`/`unified` se o runtime JavaScript for aceitável. Preferir `cmark-gfm`/`swift-markdown` se a prioridade for integração nativa e dependências mínimas, desde que os testes locais confirmem que os documentos reais não exigem semântica académica além do Markdown/GFM.

Markdown cobre bem estrutura, tabelas, blocos de código, imagens, links, âncoras e footnotes. Não fornece, por si só, um sistema completo de citações bibliográficas, includes entre ficheiros, numeração global de equações ou referências semânticas como `\\label`/`\\ref`.

## 2. Pergunta e decisão suportada

Foi investigado que parser e pipeline oferecem o melhor equilíbrio entre:

- fidelidade a Markdown real;
- GFM, tabelas, citações e footnotes;
- matemática;
- extensibilidade;
- funcionamento offline;
- segurança;
- controlo sobre HTML/CSS;
- atualização após alterações externas;
- complexidade de integração e manutenção.

A pesquisa permite comparar abordagens e recomendar uma direção condicional. Não permite fechar:

- framework desktop;
- linguagem;
- política final para links externos;
- dialecto Markdown definitivo;
- necessidade de compatibilidade completa com LaTeX;
- escolha final de KaTeX ou MathJax.

## 3. Escopo e pressupostos

Incluído:

- ficheiros Markdown locais;
- capítulos com matemática e imagens relativas;
- links para outros ficheiros;
- alterações frequentes por processos externos;
- conteúdo potencialmente perigoso;
- renderização HTML numa superfície de leitura;
- dependências locais e distribuição offline.

Fora do escopo:

- framework desktop;
- desenho da interface;
- implementação do adapter;
- edição de fontes;
- comparação exaustiva de todos os parsers;
- gestão bibliográfica completa;
- compilação de LaTeX.

“Offline” significa que o runtime não depende de servidores, CDNs ou APIs durante a utilização. As dependências podem ser obtidas durante o desenvolvimento e empacotadas na aplicação.

## 4. Critérios de avaliação

Os critérios relevantes são:

- conformidade com CommonMark/GFM;
- representação de documentos académicos;
- AST e capacidade de transformação;
- HTML previsível e estilização;
- matemática e tratamento de erros;
- resolução de recursos locais;
- segurança perante HTML, URLs e scripts;
- desempenho e previsibilidade;
- integração nativa ou JavaScript;
- licenciamento;
- manutenção e atualizações;
- comportamento após alterações externas.

Não foram usados rankings, popularidade ou benchmarks de terceiros como prova de qualidade. Os números de desempenho publicados pelos próprios projetos são tratados apenas como indicações.

## 5. Matriz de claims

| Claim | Importância | Estado | Evidência | Limitação |
|---|---:|---|---|---|
| C1. CommonMark continua a ser a base mais clara para compatibilidade entre parsers. | Alta | Facto | E1 | A especificação não cobre todas as extensões usadas em documentos reais. |
| C2. GFM acrescenta tabelas, strikethrough, task lists, autolinks e footnotes. | Alta | Facto | E2, E5 | A especificação GFM publicada é antiga; o comportamento atual do GitHub inclui pós-processamento adicional. |
| C3. `cmark-gfm` fornece AST, renderer HTML, C99 e zero dependências externas de runtime. | Alta | Facto | E3 | A API é de baixo nível e exige trabalho adicional para políticas do produto. |
| C4. `markdown-it` tem regras configuráveis, renderer de tokens e distribuição browser. | Alta | Facto | E4 | Matemática e algumas extensões académicas ficam fora do núcleo. |
| C5. `micromark` suporta CommonMark, GFM, matemática e frontmatter através de extensões. | Alta | Facto | E5 | As extensões são ESM e a integração AST exige componentes adicionais. |
| C6. `remark`/`unified` suporta transformação por AST e conversão para HTML via `remark-rehype`. | Alta | Facto | E6 | A pipeline tem mais pacotes e maior superfície de manutenção. |
| C7. O ecossistema `remark` suporta GFM e matemática com plugins mantidos. | Alta | Facto | E6, E7 | A composição correta e a ordem dos plugins são responsabilidade da aplicação. |
| C8. Footnotes são viáveis em GFM, mas não constituem um sistema bibliográfico. | Alta | Facto + inferência | E2, E7, E9 | Não há semântica de referências bibliográficas, bibliografia ou citações autor-data. |
| C9. KaTeX permite renderização para HTML sem JavaScript no cliente. | Alta | Facto | E8 | A cobertura TeX não é completa; `\\label`, `\\ref` e `\\eqref` não são suportados. |
| C10. MathJax oferece cobertura mais ampla e suporta processamento em Node. | Alta | Facto | E8, E9 | A pipeline é mais assíncrona e operacionalmente mais pesada. |
| C11. Parsers seguros por defeito não tornam automaticamente a WebView segura. | Crítica | Facto | E3, E5, E7, E10 | Ainda é necessário controlar navegação, URLs, recursos e scripts. |
| C12. Links e imagens relativos devem ser resolvidos a partir do ficheiro Markdown, não do diretório de execução. | Alta | Facto + recomendação | E10 | A política para atravessar a pasta do projeto ainda é uma decisão do produto. |
| C13. Markdown não define includes nem uma relação semântica entre ficheiros. | Alta | Facto | E1, E2, E11 | A aplicação pode acrescentar reescrita, validação ou composição própria. |
| C14. A atualização automática deve invalidar o preview quando o Markdown ou dependências relevantes mudam. | Alta | Inferência operacional | E12 | O debounce, cancelamento e deteção da escrita atómica exigem teste local. |
| C15. A renderização local antes da WebView reduz a responsabilidade da WebView pelo parsing. | Alta | Inferência arquitectural | E6, E10 | Não elimina a necessidade de sanitizar HTML e controlar recursos. |
| C16. `swift-markdown` é uma integração nativa plausível, mas requer renderer HTML próprio. | Alta | Facto + inferência | E13 | Não foi encontrada uma API oficial equivalente a `remark-rehype` pronta para este uso. |
| C17. `markdown-rs` é uma alternativa Rust moderna com HTML, AST, GFM e matemática. | Média | Facto | E14 | A maturidade de integração e a ausência de um sistema de plugins externo comparável ao unified devem ser validadas. |

## 6. Alternativas investigadas

### 6.1 `cmark-gfm` ou `swift-markdown`

`cmark-gfm` é a implementação C de referência associada ao GFM. O projeto fornece:

- parser CommonMark;
- extensões GFM;
- AST manipulável;
- renderer HTML;
- renderer LaTeX, XML, CommonMark e outros;
- C99;
- ausência de dependências externas;
- sanitização por defeito de HTML bruto e URLs perigosos.

A versão mais recente listada é `0.29.0.gfm.13`. O projeto permanece alinhado com uma linha GFM baseada na especificação `0.29`, enquanto a especificação CommonMark principal já está em `0.31.2`.

O ponto forte é a previsibilidade e a integração nativa. O ponto fraco é que o renderer HTML não resolve sozinho:

- links `.md` para a rota interna do viewer;
- IDs de headings segundo uma política própria;
- imagens relativas e permissões;
- matemática `$...$`;
- tratamento de HTML customizado;
- referências entre documentos.

`swift-markdown` usa `cmark-gfm` e expõe uma árvore persistente de valores Swift, além de `MarkupVisitor` para criar renderers próprios. É uma boa opção se a aplicação acabar por ser Swift-native, mas implica escrever e manter o renderer HTML.

### 6.2 `markdown-it`

`markdown-it` oferece:

- suporte CommonMark;
- regras configuráveis;
- plugins;
- renderer baseado em tokens;
- builds ESM, CommonJS e browser;
- licença MIT;
- versão observada `15.0.1`.

Tem bom equilíbrio para HTML direto e para pequenas extensões específicas. Tabelas e strikethrough estão próximos do seu uso esperado, mas footnotes aparecem como plugin separado (`markdown-it-footnote`). Para matemática seria necessário selecionar e validar outro plugin, o que fragmenta a cadeia.

É uma alternativa plausível se o requisito principal for HTML controlável com poucas transformações. É menos convincente se a aplicação precisar de uma árvore semântica rica para reescrever links, examinar referências, extrair headings, validar ficheiros e adicionar diferentes transformações.

### 6.3 `micromark` + extensões

`micromark` é um parser state-machine com tokens concretos e compilação direta para HTML. A versão observada é `4.0.2`. As extensões oficiais incluem:

- GFM;
- tabelas;
- footnotes;
- task lists;
- tag filtering;
- matemática;
- frontmatter;
- directives.

A extensão GFM observada é `3.0.0`; a extensão de matemática é `3.1.0`.

É particularmente forte quando se quer HTML direto, segurança por defeito e uma implementação pequena. A própria documentação recomenda `micromark` para transformar Markdown em HTML com algumas extensões.

Para o `bp-viewer`, contudo, a necessidade de transformar links relativos, resolver ficheiros e criar rotas internas pode justificar uma camada AST adicional. Nesse caso, `micromark` deixa de ser a pipeline completa e passa a ser o núcleo de parsing.

### 6.4 `remark`/`unified` + `rehype`

Esta é a alternativa mais extensível. A pipeline conceptual é:

```text
Markdown
  → remark-parse
  → remark-gfm
  → remark-math
  → transformações AST
  → remark-rehype
  → renderer de matemática
  → rehype-sanitize
  → HTML
```

O ecossistema observado inclui:

- `remark` `15.0.1`;
- `remark-gfm` `4.0.1`;
- `remark-math` `6.0.0`;
- `rehype-katex` `7.0.1`;
- `rehype-mathjax` `7.1.0`;
- `rehype-sanitize` `6.0.0`.

Vantagens:

- AST Markdown (`mdast`);
- AST HTML (`hast`);
- transformações fáceis de testar;
- GFM com footnotes;
- matemática integrada;
- extração e geração de IDs;
- validação de links locais;
- possibilidade de alterar HTML sem concatenar strings manualmente.

Desvantagens:

- maior número de dependências;
- ESM-only em vários pacotes;
- necessidade de fixar versões compatíveis;
- ordem dos plugins importante;
- sanitização precisa de um schema adequado para matemática e syntax highlighting.

É a alternativa com melhor cobertura para o cenário completo do brief.

### 6.5 `markdown-rs`

`markdown-rs` é uma alternativa Rust com:

- CommonMark;
- GFM;
- footnotes;
- tabelas;
- task lists;
- matemática;
- frontmatter;
- AST `mdast`;
- HTML seguro por defeito.

A versão observada no `Cargo.toml` é `1.0.0`, com `rust-version = 1.56`. O projeto apresenta uma arquitetura monolítica com extensões ativadas por opções.

É relevante para um desktop nativo em Rust, mas não resolve automaticamente a integração com WebView, reescrita de links ou políticas de recursos. O modelo de extensibilidade é menos modular que o de `unified`.

## 7. Comparação fundamentada

### Variantes e documentos reais

CommonMark é a base mais interoperável. GFM acrescenta exatamente várias construções úteis para uma tese:

- tabelas;
- footnotes;
- strikethrough;
- task lists;
- autolinks.

No entanto, GFM não é um padrão académico completo. Frontmatter, directives, includes, citações bibliográficas e convenções de sites estáticos são extensões adicionais.

O GFM publicado pelo GitHub é `0.29-gfm`, datado de 2019. A própria especificação avisa que o GitHub faz pós-processamento e sanitização depois da conversão. Portanto, “compatível com GFM” não significa necessariamente “idêntico ao GitHub atual”.

### AST e extensibilidade

Para transformações simples, `markdown-it` pode ser suficiente através de regras e tokens.

Para o `bp-viewer`, a existência de um AST explícito é mais importante porque permite:

- resolver URLs tendo em conta o caminho do ficheiro;
- distinguir links externos, imagens, headings e referências internas;
- gerar IDs;
- validar links para outros documentos;
- substituir links `.md` por rotas internas;
- aplicar sanitização depois das transformações;
- produzir diagnósticos com posição no ficheiro.

Aqui, `remark`/`unified` e `markdown-rs` têm uma vantagem estrutural sobre renderers HTML diretos.

### Matemática

Matemática não faz parte de CommonMark nem de GFM. A extensão `remark-math` documenta explicitamente que esta sintaxe reduz a portabilidade do Markdown.

KaTeX:

- gera HTML no processo local;
- permite `renderToString`;
- não precisa de JavaScript de matemática na WebView;
- suporta limites de tamanho e expansão;
- tem opção `trust` para comandos potencialmente perigosos.

Mas a tabela oficial mostra comandos não suportados, incluindo `\\label`, `\\ref` e `\\eqref`. Isto limita a reprodução de documentos académicos que dependam de referências de equações.

MathJax:

- oferece cobertura TeX mais ampla;
- suporta CHTML, SVG e MathML;
- pode ser usado em Node;
- tem processamento assíncrono;
- documenta `\\label`, `\\ref` e `\\eqref`.

A escolha condicional é:

- KaTeX para matemática comum, previsibilidade e HTML estático;
- MathJax quando a cobertura de comandos e referências matemáticas justificar maior complexidade.

Mesmo MathJax não transforma automaticamente vários ficheiros Markdown num documento LaTeX completo com numeração global e referências entre capítulos. Isso exigiria uma camada documental própria.

### Tabelas, footnotes e referências

Tabelas são suportadas por GFM e pelas alternativas principais.

Footnotes são suportadas por:

- `remark-gfm`;
- `micromark-extension-gfm`;
- `cmark-gfm`, através da opção correspondente;
- `markdown-rs`.

Há, contudo, duas limitações:

1. Footnotes GFM não são equivalentes a bibliografia académica.
2. A implementação de footnotes não está completamente estabilizada no próprio ecossistema GFM; a documentação de `micromark` regista diferenças e bugs existentes no GitHub.

`remark-validate-links` demonstra que verificar links para headings e ficheiros locais é uma preocupação separada do parser, não uma capacidade universal de Markdown.

### Imagens, links relativos e âncoras

Markdown representa o destino de um link ou imagem como uma URL. Não define que:

- `chapter-2.md` deve abrir no viewer;
- `chapter-2.md#method` deve navegar para um heading renderizado;
- um include deve ser expandido;
- links fora da pasta do projeto devem ser permitidos;
- imagens remotas devem ser carregadas.

A aplicação terá de definir essa política.

No caso de `WKWebView`, a API `loadHTMLString(_:baseURL:)` permite fornecer uma base URL para resolução de URLs relativas. Isto torna possível preservar referências como `../images/figure.png`, mas a solução deve:

- usar como base a pasta do Markdown original;
- controlar a raiz de leitura;
- interceptar links para outros `.md`;
- tratar ficheiros inexistentes;
- distinguir caminhos relativos de URLs remotas;
- impedir navegação arbitrária.

A recomendação é resolver e normalizar estes destinos antes de entregar o HTML à WebView, em vez de depender apenas da resolução automática do browser.

### CSS, temas e HTML gerado

Todas as alternativas produzem HTML estilável por CSS.

`remark`/`rehype` oferece mais controlo semântico, porque permite alterar a árvore HTML antes da serialização. Isso facilita:

- classes de tema;
- IDs;
- wrappers para figuras;
- classes de código;
- marcação de referências;
- schemas de sanitização.

`cmark-gfm` e `markdown-it` oferecem HTML mais direto, mas modificações complexas tendem a exigir renderer próprio ou regras específicas.

O syntax highlighting deve ser tratado como transformação opcional. Blocos de código básicos não exigem executar código nem carregar scripts.

### Segurança

Há várias camadas diferentes:

1. parser;
2. renderer de matemática;
3. HTML final;
4. WebView;
5. carregamento de recursos;
6. navegação.

`cmark-gfm` remove por defeito HTML bruto e protocolos perigosos como `javascript:`, `vbscript:`, `data:` e `file:`.

`micromark` também é seguro por defeito, mas avisa que ativar `allowDangerousHtml` ou `allowDangerousProtocol` muda essa propriedade.

`rehype-sanitize` remove tudo o que não esteja explicitamente permitido pelo schema. A documentação recomenda colocá-lo depois da última transformação potencialmente insegura. O schema terá de permitir cuidadosamente o HTML produzido por KaTeX/MathJax, incluindo partes de SVG ou MathML.

A segurança do parser não é suficiente para garantir segurança na WebView. O conteúdo final não deve poder:

- executar `<script>`;
- definir handlers `onerror`, `onclick`, etc.;
- abrir `iframe`;
- usar protocolos perigosos;
- carregar recursos fora da política definida;
- navegar a aplicação para páginas arbitrárias.

MDX foi deliberadamente excluído desta recomendação: a documentação do ecossistema trata MDX como código e não como Markdown seguro.

### Atualização e custo de re-renderização

O parser não precisa de conhecer o sistema de ficheiros. A arquitetura de atualização pode:

1. receber um evento de alteração;
2. esperar que a escrita termine;
3. reler o ficheiro;
4. cancelar um render anterior ainda pendente;
5. re-renderizar;
6. publicar apenas o resultado mais recente.

A Apple documenta `DispatchSource` para eventos de filesystem e `NSFilePresenter` para alterações coordenadas. A documentação de `NSFilePresenter` avisa que alterações feitas por escritas de baixo nível não geram notificações através de file coordination; por isso, o watcher deve ser validado com ferramentas externas reais.

O custo de re-renderizar um capítulo inteiro deverá ser medido localmente. Não há, nesta investigação, benchmark comparativo independente suficiente para afirmar que uma alternativa será materialmente mais rápida para os documentos do projeto.

### Cliente versus processo local

#### Renderização dentro da WebView

Vantagens:

- menor IPC;
- atualização directa do DOM;
- parser e renderer podem partilhar JavaScript com a camada visual.

Riscos:

- mais código privilegiado dentro da WebView;
- acesso a ficheiros e recursos mais difícil de controlar;
- maior probabilidade de misturar conteúdo do utilizador com código da aplicação;
- matemática assíncrona pode complicar as atualizações.

#### Pré-renderização no processo local

Vantagens:

- leitura e resolução de ficheiros ficam fora da WebView;
- sanitização acontece antes de inserir HTML;
- erros de parsing podem ser normalizados;
- pipeline mais fácil de testar independentemente da interface;
- a WebView pode receber apenas HTML final e CSS conhecido.

Custos:

- IPC ou fronteira entre processo e UI;
- necessidade de controlar cancelamento e versões de render;
- eventual runtime adicional se for usado Node.

Para este projeto, a pré-renderização local parece a arquitetura mais previsível, mas esta é uma recomendação arquitectural, não uma decisão fechada.

## 8. Evidência

### E1 — CommonMark

A especificação CommonMark mais recente publicada é `0.31.2`, de 2024-01-28. Define headings, listas, blocos de código, tabelas não standard, links, imagens, HTML bruto e âncoras ao nível HTML, mas não GFM nem matemática.

Fonte: [CommonMark Specification](https://spec.commonmark.org/)

### E2 — GFM

A especificação GFM publicada é `0.29-gfm`, de 2019-04-06. Define GFM como superconjunto estrito de CommonMark e inclui tabelas, task lists, strikethrough e autolinks. Também declara que o GitHub faz sanitização e pós-processamento adicionais.

Fonte: [GitHub Flavored Markdown Spec](https://github.github.com/gfm/)

### E3 — cmark-gfm

O repositório oficial documenta AST, renderers múltiplos, C99, ausência de dependências externas, testes CommonMark, fuzzing e sanitização por defeito. A release mais recente listada é `0.29.0.gfm.13`.

Fontes: [README do cmark-gfm](https://github.com/github/cmark-gfm), [releases do cmark-gfm](https://github.com/github/cmark-gfm/releases), [API C](https://raw.githubusercontent.com/github/cmark-gfm/master/src/cmark-gfm.h)

### E4 — markdown-it

A documentação oficial descreve CommonMark, regras configuráveis, plugins, renderer e “safe by default”. O `package.json` observado indica `15.0.1`, MIT, com exports browser, ESM e CommonJS.

Fontes: [README/documentação markdown-it](https://markdown-it.github.io/markdown-it/), [package.json](https://raw.githubusercontent.com/markdown-it/markdown-it/master/package.json), [changelog](https://github.com/markdown-it/markdown-it/blob/master/CHANGELOG.md)

### E5 — micromark

A documentação oficial descreve CommonMark, GFM, matemática, frontmatter, tokens concretos, extensões de sintaxe e HTML, segurança por defeito e limites contra inputs excessivos. As versões observadas são `micromark 4.0.2`, `micromark-extension-gfm 3.0.0` e `micromark-extension-math 3.1.0`.

Fontes: [micromark](https://github.com/micromark/micromark), [GFM extension](https://github.com/micromark/micromark-extension-gfm), [math extension](https://github.com/micromark/micromark-extension-math)

### E6 — remark/unified

A documentação oficial descreve `mdast`, plugins AST, `remark-rehype` para conversão a `hast` e transformação para HTML. `remark` recomenda `micromark` quando o objetivo é apenas HTML, mas a pipeline AST é adequada quando o produto precisa de transformações.

Fontes: [remark](https://github.com/remarkjs/remark), [remark-rehype](https://github.com/remarkjs/remark-rehype), [remark-gfm](https://github.com/remarkjs/remark-gfm)

### E7 — matemática no unified

`remark-math` documenta a separação entre parsing de matemática e renderização com KaTeX ou MathJax, incluindo renderização em tempo de compilação sem JavaScript no cliente.

Fonte: [remark-math](https://github.com/remarkjs/remark-math)

### E8 — KaTeX

A documentação observada é da versão `0.18.7`. KaTeX oferece `renderToString`, opções `maxSize`, `maxExpand` e `trust`, e documenta comandos não suportados como `\\label`, `\\ref` e `\\eqref`.

Fontes: [KaTeX API](https://katex.org/docs/api), [segurança KaTeX](https://katex.org/docs/security), [opções KaTeX](https://katex.org/docs/options), [tabela de suporte](https://katex.org/docs/support_table), [package.json](https://raw.githubusercontent.com/KaTeX/KaTeX/main/package.json)

### E9 — MathJax

A documentação estável observada é da linha MathJax 4. Documenta uso em Node, processamento assíncrono, saída SVG/CHTML/MathML e referências como `\\label`, `\\ref` e `\\eqref`.

Fontes: [MathJax documentation](https://docs.mathjax.org/en/latest/), [PDF da documentação](https://docs.mathjax.org/_/downloads/en/stable/pdf/), [rehype-mathjax package](https://raw.githubusercontent.com/remarkjs/remark-math/main/packages/rehype-mathjax/package.json)

### E10 — WebKit e URLs locais

A Apple documenta `WKWebView.loadHTMLString(_:baseURL:)` para resolução de URLs relativas e `loadFileURL(_:allowingReadAccessTo:)` para conteúdo local.

Fontes: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/), [loadHTMLString(_:baseURL:)](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring%28_%3Abaseurl%3A%29)

### E11 — links para outros ficheiros

`remark-validate-links` verifica links para ficheiros e headings locais, incluindo links para headings em outros Markdown. Isto demonstra que a validação de referências entre documentos é uma camada adicional, não uma capacidade intrínseca de CommonMark.

Fonte: [remark-validate-links](https://github.com/remarkjs/remark-validate-links)

### E12 — alterações externas

A Apple documenta `DispatchSource` para eventos de filesystem e `NSFilePresenter`/`NSFileCoordinator` para alterações coordenadas.

Fontes: [DispatchSource filesystem events](https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent/all), [NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter), [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)

### E13 — Swift Markdown

`swift-markdown 0.8.0` usa `cmark-gfm`, oferece árvore persistente e `MarkupVisitor`. O `Package.swift` observado requer Swift tools `6.2` no tag `0.8.0` e licencia o projeto sob Apache-2.0 com Runtime Library Exception.

Fontes: [Swift Markdown](https://github.com/swiftlang/swift-markdown), [release 0.8.0](https://github.com/swiftlang/swift-markdown/releases), [Package.swift 0.8.0](https://raw.githubusercontent.com/swiftlang/swift-markdown/0.8.0/Package.swift), [MarkupVisitor](https://github.com/swiftlang/swift-markdown/blob/main/Sources/Markdown/Visitor/MarkupVisitor.swift)

### E14 — markdown-rs

O projeto Rust documenta CommonMark, GFM, footnotes, matemática, frontmatter, AST, HTML seguro por defeito e `1.0.0` no `Cargo.toml`.

Fontes: [markdown-rs](https://github.com/wooorm/markdown-rs), [Cargo.toml](https://raw.githubusercontent.com/wooorm/markdown-rs/main/Cargo.toml), [releases](https://github.com/wooorm/markdown-rs/releases)

## 9. Conflitos e tentativas de refutação

### “cmark-gfm é automaticamente a melhor opção”

Refutação: é excelente como núcleo nativo, mas não resolve matemática Markdown, rotas internas, composição entre ficheiros ou políticas de HTML. A vantagem só se mantém se os documentos reais forem próximos de CommonMark/GFM e se o projeto aceitar renderer e transformações próprias.

### “GFM é um standard académico completo”

Refutação: GFM fornece footnotes e tabelas, mas não bibliografia, citações semânticas, includes, numeração de equações ou referências entre capítulos.

### “KaTeX reproduz LaTeX suficiente para qualquer tese”

Refutação: a tabela oficial mostra comandos não suportados, incluindo `\\label`, `\\ref` e `\\eqref`. Para matemática mais próxima de LaTeX, MathJax é uma alternativa, mas aumenta a complexidade.

### “Sanitizar o Markdown chega”

Refutação: sanitizar a árvore Markdown não basta quando existe HTML bruto, renderer de matemática, SVG, CSS, URLs locais ou navegação. `rehype-sanitize` deve ser aplicado depois das transformações potencialmente inseguras.

### “Renderizar na WebView é mais simples”

Refutação: pode reduzir IPC, mas mistura conteúdo controlado pelo utilizador com a superfície que carrega recursos e navega. A renderização local separa melhor parsing, permissões e apresentação.

### “A versão mais recente da ferramenta garante compatibilidade”

Refutação: há desalinhamentos de versões. Por exemplo, `rehype-katex 7.0.1` declara dependência em KaTeX `^0.16.0`, enquanto a versão KaTeX observada é `0.18.7`; `rehype-mathjax 7.1.0` declara `mathjax-full ^3.0.0`, enquanto a documentação MathJax atual é da linha 4. Isto exige testes de compatibilidade e pinning explícito.

## 10. Recomendação condicional

### Opção preferida se JavaScript for aceitável

Usar uma pipeline local:

```text
remark-parse
  + remark-gfm
  + remark-math
  → transformações AST próprias
  → remark-rehype
  → KaTeX ou MathJax
  → rehype-sanitize
  → HTML final
```

Condições:

- todos os pacotes devem ser empacotados localmente;
- versões devem ser fixadas;
- HTML bruto deve permanecer desativado ou passar por sanitização explícita;
- links e imagens devem ser reescritos a partir do caminho do Markdown;
- links `.md` devem ser interceptados pelo viewer;
- o renderer matemático deve ser escolhido com base nos documentos reais.

Confiança: média-alta para o equilíbrio entre extensibilidade, conteúdo académico e segurança.

### Opção preferida se integração nativa for prioritária

Usar `cmark-gfm` diretamente ou através de `swift-markdown`, com:

- GFM;
- footnotes ativadas;
- renderer HTML controlado;
- transformação própria para links e imagens;
- renderer matemático separado;
- sanitização adicional se HTML bruto ou matemática rica forem permitidos.

Confiança: média. É tecnicamente viável, mas depende de quanto renderer próprio o MVP aceita manter.

### Quando mudar de recomendação

A recomendação deve mudar para MathJax ou para uma pipeline mais próxima de LaTeX se os documentos reais dependerem de:

- `\\label`, `\\ref` ou `\\eqref`;
- ambientes matemáticos não suportados por KaTeX;
- numeração global de equações;
- referências bibliográficas automáticas;
- includes ou composição de vários capítulos;
- semântica próxima de um documento LaTeX completo.

## 11. Implicações para o MVP

Sem fechar decisões de produto, a síntese deve considerar:

- declarar explicitamente o dialecto suportado;
- manter o parser e os renderers fora da WebView quando possível;
- modelar o contexto do documento com caminho absoluto, pasta base e raiz autorizada;
- tratar links, imagens e headings como dados a transformar;
- ter uma ordem explícita de plugins;
- sanitizar depois da última transformação insegura;
- incluir erros de parsing/matemática como resultado renderizável;
- cancelar renders antigos quando chega uma alteração mais recente;
- manter artefactos e dependências dentro do bundle da aplicação;
- evitar dependência de CDN ou rede durante a utilização.

## 12. Lacunas e testes locais sugeridos

1. **Fixture de capítulo académico**
   - headings, citações em blockquote, tabelas, footnotes, blocos de código, imagens e matemática inline/display;
   - comparar `cmark-gfm`, `markdown-it`, `micromark` e `remark`.

2. **Links relativos**
   - Markdown em subpastas;
   - imagens com `../`;
   - nomes com espaços, Unicode e parênteses;
   - links `.md#heading`;
   - ficheiros inexistentes;
   - tentativa de sair da raiz do projeto.

3. **Matemática**
   - fórmulas KaTeX comuns;
   - ambientes suportados e não suportados;
   - `\\label`, `\\ref`, `\\eqref`;
   - macros grandes ou recursivas;
   - erro de TeX sem interromper o preview inteiro.

4. **Segurança**
   - `<script>`;
   - `onclick`, `onerror`;
   - `javascript:`, `file:`, `data:` e `vbscript:`;
   - `<iframe>`;
   - SVG com handlers;
   - HTML bruto combinado com KaTeX/MathJax;
   - confirmação de que nenhum script do documento é executado.

5. **Atualização externa**
   - escrita incremental;
   - escrita atómica via ficheiro temporário e rename;
   - várias alterações rápidas;
   - alteração de imagem sem alteração do Markdown;
   - remoção ou rename de ficheiro relacionado;
   - render antigo a terminar depois de um render novo.

6. **Desempenho**
   - capítulos de 10 KB, 100 KB e 500 KB;
   - tempo até primeiro HTML;
   - tempo até matemática final;
   - memória;
   - comportamento durante alterações sucessivas.

7. **Compatibilidade de versões**
   - `rehype-katex` com KaTeX empacotado;
   - `rehype-mathjax` com a versão realmente resolvida;
   - builds offline e sem acesso a CDN;
   - build nativo em Apple Silicon.

## 13. Ledger de fontes

### Usadas

| Fonte | Tipo | Versão/data observada | Razão |
|---|---|---|---|
| CommonMark | Especificação | 0.31.2, 2024-01-28 | Base sintáctica e limitações do standard. |
| GFM | Especificação | 0.29-gfm, 2019-04-06 | Tabelas, footnotes e extensões GitHub. |
| cmark-gfm | Repositório/API/releases | 0.29.0.gfm.13 | Parser nativo, AST, segurança e licença. |
| markdown-it | Repositório/package/changelog | 15.0.1; changelog 15.0.0 em 2026-07-30 | HTML directo e extensibilidade. |
| micromark | Repositórios/package | 4.0.2; GFM 3.0.0; math 3.1.0 | Parser directo, extensões e segurança. |
| remark/unified | Repositórios oficiais | remark 15.0.1; GFM 4.0.1 | AST e pipeline de transformações. |
| remark-math | Repositório/package | 6.0.0; KaTeX 7.0.1; MathJax 7.1.0 | Matemática e renderização local. |
| rehype-sanitize | Repositório/package | 6.0.0 | Sanitização e ordem das transformações. |
| KaTeX | Documentação/package | 0.18.7 | Cobertura TeX, segurança e HTML estático. |
| MathJax | Documentação oficial | linha 4 | Cobertura e processamento em Node. |
| Apple WebKit/Foundation | Documentação oficial | consultada em 2026-09-09 | URLs relativas e alterações externas. |
| Swift Markdown | Repositório/package | 0.8.0; Swift tools 6.2 | Integração nativa e AST Swift. |
| markdown-rs | Repositório/Cargo/release | 1.0.0 | Alternativa Rust. |

### Rejeitadas ou usadas apenas como descoberta

| Fonte/caminho | Razão |
|---|---|
| Snippets de pesquisa e rankings | Não são evidência primária suficiente. |
| GitHub stars/watchers | Não medem adequação, segurança ou manutenção. |
| `marked` | A própria comparação do ecossistema `micromark` declara que não corresponde a CommonMark/GFM e é inseguro por defeito; não foi mantido como candidato principal. |
| `swift-markdownkit` | Projeto terceiro; usado apenas como descoberta, sem evidência suficiente para competir com as opções oficiais. |
| Plugins `markdown-it` de matemática não oficiais | Não foram comparados em profundidade nem tratados como equivalentes a `remark-math`. |
| Benchmarks publicados pelos próprios parsers | Mantidos como alegações do fornecedor, não como comparação independente. |

## 14. Registo de pesquisa

- Q1 — Ler instruções da repo, visão e brief Markdown → HTML. Resultado: critérios e formato definidos.
- Q2 — Consultar CommonMark e GFM. Resultado: separar standard base, extensões e falta de matemática.
- Q3 — Consultar `cmark-gfm`, `markdown-it`, `micromark`, `remark` e `markdown-rs`. Resultado: comparar AST, HTML directo, extensões e dependências.
- Q4 — Consultar `remark-math`, KaTeX e MathJax. Resultado: comparar matemática, cobertura, erros e segurança.
- Q5 — Consultar `rehype-sanitize` e documentação dos parsers. Resultado: estabelecer que sanitização é uma etapa própria.
- Q6 — Consultar Apple WebKit/Foundation. Resultado: identificar implicações de base URLs, ficheiros locais e watchers.
- Q7 — Procurar refutações e limitações. Resultado: confirmar desalinhamento de versões, limitações de KaTeX, estado antigo da especificação GFM e ausência de semântica bibliográfica.

### Razão para parar

A pesquisa atingiu o nível standard pedido: foram consultadas as especificações e repositórios oficiais das alternativas principais, documentadas as limitações materiais, verificadas versões atuais observáveis e definidos testes que só podem ser resolvidos com documentos reais e um protótipo local.

Não foram implementados testes nem alterada a repo.

# Relatório de investigação: preview, segurança e distribuição

Data de acesso web: 09-09-2026  
Repositório verificado: [arquivo da pesquisa](../CONTEXT.md), [brief de preview](../preview-security-distribution.md) e [estado atual](../../../current-state.md)
Estado da repo no momento da investigação: sem alterações.

## 1. Resumo executivo

A combinação com melhor relação entre controlo, integração nativa e risco delimitável é:

- Markdown: `WKWebView` para HTML estático, com JavaScript de conteúdo desativado, sanitização allow-list, política CSP, carregamento de recursos limitado à pasta autorizada e navegação interceptada.
- LaTeX: PDFKit para apresentar o PDF produzido, com ações e links tratados explicitamente; Quick Look é uma alternativa simples, mas oferece menos controlo.
- Ficheiros: App Sandbox, acesso read-only à pasta escolhida pelo utilizador e bookmarks com security scope para reabrir o projeto.
- Compilação: diretório temporário fora da pasta do projeto, limites de tempo/saída/recursos, shell escape desativado ou restrito e nenhum pacote instalado automaticamente.

A maior incompatibilidade permanece entre:

1. usar uma instalação LaTeX externa, como MacTeX;
2. manter a aplicação sandboxed, especialmente com distribuição pela Mac App Store.

A documentação da Apple indica que permissões para ficheiros escolhidos pelo utilizador não autorizam executar programas localizados fora da app, container ou app group. Para uma distribuição sandboxed, a alternativa tecnicamente mais controlável é empacotar executáveis auxiliares assinados, possivelmente atrás de XPC. Isso aumenta bastante o tamanho, manutenção e complexidade de licenciamento.

Nenhuma opção deve ser classificada como “segura” em absoluto. As recomendações abaixo reduzem o impacto de conteúdo local comprometido, mas não eliminam vulnerabilidades em WebKit, PDFKit, parsers, compiladores ou bibliotecas.

## 2. Pergunta e decisão suportada

Foi investigado como:

- apresentar HTML local e PDFs;
- limitar JavaScript, navegação e acesso a ficheiros;
- processar Markdown, imagens, PDFs e projectos LaTeX potencialmente hostis;
- usar App Sandbox, permissões e security-scoped bookmarks;
- executar compiladores auxiliares;
- distribuir e atualizar a aplicação fora ou dentro da Mac App Store.

A pesquisa suporta uma arquitetura de preview estático com defesa em profundidade. Não suporta ainda uma decisão final sobre a estratégia de execução/empacotamento do LaTeX.

## 3. Escopo e pressupostos

### Incluído

- conteúdo local modificado por processos externos, incluindo LLMs;
- conteúdo deliberadamente malicioso dentro da pasta aberta;
- tentativas de aceder a ficheiros fora da pasta autorizada;
- HTML/JavaScript, imagens, SVG, PDF, links e artefactos LaTeX;
- comprometimento do processo de preview ou compilador;
- uso pessoal no macOS e possível distribuição futura.

### Excluído

- modelo completo de ameaça para distribuição pública;
- decisão do parser Markdown ou compilador LaTeX;
- implementação;
- comparação com outros sistemas operativos;
- autenticação, cloud ou colaboração;
- garantia contra um macOS ou utilizador já comprometido.

### Modelo de ameaça usado

Assume-se que:

- o utilizador pode abrir uma pasta que contém ficheiros hostis;
- o conteúdo pode tentar executar código, ler ficheiros, fazer pedidos de rede ou consumir recursos;
- a app corre com a identidade do utilizador;
- não há intenção de dar à app acesso global ao computador;
- o utilizador ainda controla acções explícitas como escolher uma pasta ou abrir um link externo.

Não se assume que App Sandbox, notarização ou sanitização tornam um ficheiro confiável.

## 4. Critérios de avaliação

- contenção de conteúdo hostil;
- controlo de acesso a ficheiros;
- controlo de rede e navegação;
- qualidade do preview;
- isolamento e recuperação após falhas;
- funcionamento offline;
- dependências e actualizações;
- compatibilidade com App Sandbox;
- complexidade operacional;
- licenciamento e distribuição;
- previsibilidade em alterações externas.

## 5. Matriz de claims

| Claim | Importância | Estado | Evidência | Limitações |
|---|---:|---|---|---|
| C1. `WKWebView` suporta HTML, CSS, JavaScript, HTML em memória e ficheiros locais. | Alta | Facto | E1 | Não estabelece que conteúdo local seja seguro. |
| C2. `loadFileURL` pode limitar a leitura a um ficheiro ou directório indicado. | Alta | Facto | E2 | A área indicada continua a ser uma capacidade de leitura; não é uma política completa de paths. |
| C3. JavaScript de conteúdo está activo por defeito, mas pode ser desactivado por navegação. | Alta | Facto | E3 | JavaScript desligado não impede todos os pedidos passivos nem vulnerabilidades do renderer. |
| C4. WebKit renderiza conteúdo em processos separados da app. | Alta | Facto | E4 | Isolamento de processo reduz impacto, mas não substitui sandbox nem elimina bugs do WebKit. |
| C5. `WKNavigationDelegate` permite aceitar ou rejeitar navegações. | Alta | Facto | E5 | A política tem de abranger redirecções, novas janelas, downloads e esquemas não HTTP. |
| C6. `WKWebsiteDataStore.nonPersistent` evita persistir dados do website em disco. | Média | Facto | E6 | Não controla por si só pedidos de rede ou acesso a ficheiros. |
| C7. DOMPurify usa uma política allow-list, mas não sanitiza CSS nem impede leaks HTTP por si só. | Alta | Facto | E7 | A versão, configuração e sink exactos têm de ser fixados e testados. |
| C8. A documentação actual do DOMPurify regista vulnerabilidades recentes e riscos de configuração. | Alta | Facto | E8 | A existência de uma biblioteca não prova segurança da integração. |
| C9. PDFKit apresenta PDFs, permite selecção, navegação e cópia de texto. | Média | Facto | E9 | PDFKit continua a ser um parser complexo de ficheiros não confiáveis. |
| C10. PDFs podem conter annotations/actions, incluindo destinos URL, URI, Launch e remote go-to. | Alta | Facto | E10 | A documentação não prova exactamente quais acções o `PDFView` executa automaticamente em cada versão do macOS. |
| C11. Quick Look suporta PDFs e ficheiros de texto, mas a lista de formatos pode mudar entre versões. | Média | Facto | E11 | Oferece menos controlo de política que uma superfície dedicada. |
| C12. App Sandbox limita recursos por entitlements e pode conceder acesso recursivo à pasta escolhida. | Alta | Facto | E12 | POSIX ACLs, TCC e estados externos podem continuar a bloquear acesso. |
| C13. Security-scoped bookmarks permitem persistir acesso a recursos entre lançamentos, exigindo gestão explícita do scope. | Alta | Facto | E12 | O bookmark pode ficar stale ou perder validade. |
| C14. Um processo auxiliar sandboxed não recebe automaticamente permissões PowerBox obtidas depois do arranque; bookmarks/dados têm de ser passados. | Alta | Facto | E13 | O comportamento exacto depende do tipo de helper e do modelo de distribuição. |
| C15. XPC é a tecnologia Apple preferida para privilege separation relativamente a um simples child process. | Alta | Facto | E13, E14 | XPC não torna o compilador confiável; apenas cria uma fronteira adicional. |
| C16. TeX Live trata shell escape como risco; `-shell-escape` permite comandos arbitrários, enquanto o modo restrito limita comandos permitidos. | Muito alta | Facto | E15 | O modo restrito ainda permite leitura/escrita de ficheiros e comandos aprovados. |
| C17. TeX Live recomenda cuidado adicional com programas contribuídos e uso de subdirectório/chroot para input não confiável. | Muito alta | Facto | E15 | Não é garantia de isolamento no macOS. |
| C18. MacTeX 2026 requer macOS 11+, é universal para Intel/Arm e o pacote completo tem cerca de 6,4 GB; BasicTeX tem cerca de 134 MB. | Alta | Facto | E16 | Tamanho não inclui necessariamente todas as dependências requeridas por uma tese. |
| C19. Acesso a ficheiros seleccionados não autoriza, por si só, executar programas fora da app, container ou app group. | Muito alta | Facto | E12 | A compatibilidade exacta com cada modelo de distribuição requer teste local e validação da App Store. |
| C20. Notarização fora da App Store requer Developer ID, Hardened Runtime, timestamp seguro e assinatura dos executáveis distribuídos. | Alta | Facto | E17 | Notarização não é App Review nem auditoria do conteúdo aberto pela app. |
| C21. TeX Live contém componentes com licenças próprias, apesar de a distribuição seguir princípios de software livre. | Média | Facto | E18 | Um inventário legal completo ainda é necessário se componentes forem empacotados. |
| C22. A recomendação de preview estático com JS desligado, sanitização, CSP, política de paths e sandbox é uma inferência de defesa em profundidade. | Muito alta | Inferência | C1–C21 | Não foi validada por protótipo no macOS alvo. |

## 6. Alternativas investigadas

### 6.1 Markdown/HTML

| Opção | Vantagens | Riscos/limitações |
|---|---|---|
| `WKWebView` com HTML estático | Boa fidelidade visual; API nativa; suporta CSS, matemática pré-renderizada e imagens | Superfície WebKit; JavaScript e navegação requerem política explícita |
| `WKWebView` com JavaScript activo | Permite bibliotecas client-side e interacção | Aumenta XSS, exfiltração, consumo de CPU e complexidade de bridge |
| `WKWebView` com `loadFileURL` | Recurso local simples; Apple permite limitar `readAccessURL` | Paths, symlinks, `..`, URLs absolutas e esquemas continuam a exigir validação |
| `WKWebView` com esquema app-owned | Permite validar cada pedido de recurso e MIME type | Introduz código nativo de carregamento; um erro pode criar uma nova fronteira insegura |
| AppKit/texto nativo | Menor superfície web e menos dependências | Menor fidelidade para HTML, CSS, tabelas e matemática |
| Quick Look | Integração rápida para ficheiros suportados | Lista de formatos variável e menor controlo sobre navegação e conteúdo |
| HTML com sanitização apenas | Reduz XSS conhecido | Insuficiente contra CSS, pedidos externos, sinks posteriores e reprocessamento |

### 6.2 PDF

| Opção | Vantagens | Riscos/limitações |
|---|---|---|
| PDFKit | Nativo, controlo de visualização e acesso a annotations/actions | Parser complexo; políticas de links/acções precisam de validação |
| Quick Look | Simples e integrado no sistema | Menor controlo sobre comportamento e compatibilidade exacta |
| Abrir no Preview externo | Isola a app no processo do Preview | Transfere risco para outra app e quebra o fluxo pretendido |

### 6.3 LaTeX

| Opção | Vantagens | Riscos/limitações |
|---|---|---|
| MacTeX/TeX Live já instalado | Menor pacote da app e maior compatibilidade com ambientes existentes | Dependência externa; conflito com sandbox; versões e paths variáveis |
| BasicTeX externo | Muito menor que MacTeX completo | Pacotes ausentes; instalação/configuração adicional |
| Executáveis empacotados | Versões controladas; mais previsível para distribuição | Tamanho, assinatura, actualizações, licenças e possíveis dependências |
| Helper/XPC empacotado | Melhor separação de processo e permissões | Complexidade de IPC, passagem de bookmarks e assinatura de todos os executáveis |
| Child process simples | Mais fácil de integrar | A Apple documenta menor separação de privilégios que XPC |
| Compilação sem isolamento | Integração directa | Não adequada para conteúdo potencialmente hostil; pode escrever no projecto ou executar comandos |

## 7. Comparação fundamentada

### 7.1 Markdown com HTML ou JavaScript incorporado

O `WKWebView` tem JavaScript de conteúdo activo por defeito. A Apple documenta que `allowsContentJavaScript = false` impede scripts inline, ficheiros JavaScript referenciados e URLs `javascript:`. Isto reduz substancialmente a superfície do cenário C1, mas não deve ser tratado como sanitização.

A recomendação condicional é:

1. converter Markdown para HTML;
2. sanitizar o HTML antes de o entregar ao WebView;
3. usar uma allow-list pequena;
4. remover scripts, handlers `on*`, `iframe`, `object`, `embed`, forms, `base`, `link`, `style` e SVG, salvo necessidade validada;
5. desactivar JavaScript de conteúdo;
6. aplicar CSP, por exemplo com `script-src 'none'`, `object-src 'none'`, `connect-src 'none'`;
7. não expor bridge nativa desnecessária ao JavaScript;
8. interceptar toda a navegação.

O DOMPurify actual explicita que não sanitiza CSS nem impede pedidos HTTP passivos. Também documenta bypasses e correcções recentes. Por isso, a versão deve ser fixada durante cada build, monitorizada e sujeita a testes de regressão.

### 7.2 Imagens e ficheiros fora da pasta

Um `src="../..."` ou URL absoluta não deve ser interpretado como autorização para escapar da pasta aberta.

Duas abordagens são plausíveis:

- `loadFileURL` com `readAccessURL` exactamente igual à pasta seleccionada;
- um carregador de recursos app-owned que resolve cada path, verifica que permanece dentro da raiz canónica e só então devolve o conteúdo.

A segunda oferece maior controlo sobre paths, MIME types, symlinks e extensões, mas cria mais lógica própria. A primeira é mais simples e está directamente documentada pela Apple.

A app não deve seguir automaticamente:

- symlinks que escapem da raiz;
- paths absolutos;
- componentes `..` que saiam da raiz;
- URLs `file:`, `javascript:`, `data:`, `blob:` ou esquemas personalizados não autorizados.

A necessidade de referências deliberadamente fora do projecto deve permanecer uma decisão de produto aberta, não uma consequência acidental do renderer.

### 7.3 Links e navegação

`WKNavigationDelegate` permite aceitar ou cancelar navegações antes de carregar o conteúdo. Uma política mínima plausível seria:

- links internos: apenas para ficheiros permitidos dentro da raiz;
- links externos: não carregados dentro do preview; abrir apenas após acção explícita do utilizador;
- esquemas permitidos externamente: inicialmente apenas `https` e, se necessário, `http`;
- bloquear `file`, `javascript`, `data`, `blob`, `ftp` e esquemas personalizados;
- bloquear novas janelas, downloads automáticos e redireccionamentos não esperados.

Abrir um link explicitamente no browser não é “seguro”: apenas desloca a responsabilidade para outra aplicação, que pode ter acesso a cookies, rede e credenciais do utilizador.

### 7.4 PDF

PDFKit oferece capacidades adequadas para leitura: páginas, zoom, selecção, pesquisa/cópia e navegação. Contudo, o modelo PDF inclui annotations e actions. A Apple documenta tipos URL/URI, Launch, remote go-to e outras acções.

Assim, a app não deve assumir que “PDF é apenas desenho”. É necessário testar, na versão mínima de macOS escolhida:

- cliques em links HTTP/HTTPS;
- links `file:`;
- Launch actions;
- remote go-to;
- attachments;
- forms e JavaScript específico de PDF;
- PDFs grandes, corrompidos ou com imagens comprimidas anómalas.

A preferência condicional é PDFKit como superfície principal, com acções externas bloqueadas ou submetidas a confirmação explícita. Quick Look pode ser fallback, mas não deve ser considerado equivalente em controlo.

### 7.5 Compilação LaTeX

Este é o risco mais importante do brief.

O TeX Live documenta que:

- `-shell-escape` permite executar comandos arbitrários;
- o modo restrito limita a uma lista de comandos;
- o processamento de input não confiável deve ser feito com cautela;
- programas contribuídos podem não ter a mesma robustez dos programas core;
- subdirectórios isolados ou chroot podem melhorar a segurança.

Implicações recomendadas:

- nunca compilar directamente dentro da pasta do projecto;
- criar um workspace temporário;
- copiar apenas os inputs necessários;
- produzir PDF, logs e auxiliares apenas no workspace temporário/container;
- não conceder permissões de escrita à pasta original;
- desactivar shell escape por defeito;
- permitir apenas shell escape restrito se uma capacidade requerida o justificar;
- não instalar pacotes automaticamente;
- fixar `PATH`, ambiente, directório de trabalho e localização de outputs;
- definir timeout, limite de logs, limite de tamanho de artefactos e terminação do processo;
- considerar fontes, `.sty`, `.bst`, `.bib`, scripts, SVG, EPS e conversores como inputs potencialmente activos;
- limpar ou substituir o workspace após compilação.

A documentação da Apple introduz uma dificuldade adicional: uma app sandboxed não pode usar apenas a permissão de ficheiro escolhido pelo utilizador para executar programas localizados fora da app, container ou app group. Isto coloca a instalação externa do MacTeX fora de uma solução simples e universal para distribuição sandboxed.

## 8. Evidência

### E1–E6: WebKit

- **E1 — WKWebView.** A Apple documenta suporte para HTML, CSS, JavaScript, conteúdo HTML em memória e ficheiros locais: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview).
- **E2 — limite de leitura local.** `loadFileURL(_:allowingReadAccessTo:)` permite indicar um ficheiro ou directório de leitura; usar o próprio ficheiro limita a leitura a esse ficheiro: [loadFileURL](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29).
- **E3 — JavaScript.** A Apple documenta que `allowsContentJavaScript` é true por defeito e que false impede scripts inline, referências JavaScript e URLs `javascript:`: [allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript).
- **E4 — processo de conteúdo.** WebKit renderiza conteúdo em processos separados da app, embora possa partilhar processos conforme limites internos: [WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool).
- **E5 — navegação.** `WKNavigationDelegate` expõe políticas para aceitar ou cancelar navegações: [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).
- **E6 — persistência.** `WKWebsiteDataStore` tem uma variante não persistente que mantém dados em memória: [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore).

Estas fontes estabelecem capacidades da API; não estabelecem que uma configuração concreta seja resistente a todo o conteúdo malicioso.

### E7–E8: sanitização e CSP

- **E7 — DOMPurify.** A documentação de segurança descreve o modelo allow-list, sanitização DOM, suporte a Trusted Types e limites relativos a CSS e pedidos HTTP: [DOMPurify Security Goals & Threat Model](https://github.com/cure53/DOMPurify/wiki/Security-Goals-%26-Threat-Model).
- **E8 — manutenção e vulnerabilidades.** A mesma documentação estava actualizada em 09-09-2026 e indicava a linha actual 3.4.x, versão 3.4.15, além de advisories recentes: [DOMPurify Security Advisories](https://github.com/cure53/DOMPurify/security/advisories).
- **E9 — CSP.** CSP define restrições para scripts, objectos, frames, conexões e recursos; a especificação recomenda evitar `unsafe-inline` e `data:` quando não forem necessários: [Content Security Policy Level 3](https://www.w3.org/TR/CSP/).

CSP é defesa em profundidade, não substituto da sanitização nem da política nativa de navegação.

### E9–E11: PDF

- **E9 — capacidades PDFKit.** `PDFView` apresenta PDF, permite selecção, navegação, zoom e cópia de texto: [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview).
- **E10 — annotations/actions.** A Apple documenta que PDFs contêm annotations e acções; `PDFAction` pode representar URI/Launch através de `PDFActionURL`: [PDFAnnotation](https://developer.apple.com/documentation/pdfkit/pdfannotation), [PDFAction type](https://developer.apple.com/documentation/pdfkit/pdfaction/type).
- **E11 — Quick Look.** Quick Look suporta PDFs e texto, mas a lista de tipos suportados pode mudar entre versões do sistema: [Quick Look](https://developer.apple.com/documentation/quicklook/).

A documentação confirma a existência das superfícies e das acções; não fornece uma classificação de segurança para ficheiros PDF arbitrários.

### E12–E14: App Sandbox, bookmarks e helpers

- **E12 — sandbox e permissões.** A Apple documenta App Sandbox, Open Panels, acesso read-only/read-write a ficheiros escolhidos e acesso recursivo quando é seleccionada uma pasta: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- **E13 — bookmarks e child processes.** Security-scoped bookmarks podem persistir acesso; permissões obtidas dinamicamente não são automaticamente transmitidas a helpers com sandbox inheritance: [Enabling App Sandbox Inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).
- **E14 — XPC.** A Apple descreve XPC como mecanismo para separar processos e indica que XPC é preferível para privilege separation: [Creating XPC services](https://developer.apple.com/documentation/xpc/creating-xpc-services), [Embedding a helper tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).

### E15–E16: TeX Live/MacTeX

- **E15 — shell escape e input não confiável.** O TeX Live 2026 descreve shell escapes, modo restrito, riscos dos programas contribuídos e a recomendação de usar subdirectório ou chroot para conteúdo não confiável: [TeX Live Guide 2026](https://tug.org/texlive/doc/texlive-en/texlive-en.html).
- **E16 — versões e tamanhos.** TeX Live 2026 foi lançado em 01-03-2026. MacTeX 2026 requer macOS 11 ou superior, suporta Intel/Arm e o pacote completo ronda 6,4 GB; BasicTeX ronda 134 MB: [TeX Live](https://tug.org/texlive/), [MacTeX downloads](https://tug.org/mactex/mactex-download.html).

### E17–E18: distribuição e licenciamento

- **E17 — distribuição fora da App Store.** Para software fora da App Store, a Apple requer Developer ID, assinatura dos executáveis, Hardened Runtime, timestamp seguro e notarização: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).
- **E18 — dependências TeX.** TeX Live indica que os componentes têm licenças próprias e que a redistribuição deve respeitar as condições de cada componente: [TeX Live copying and redistribution](https://www.tug.org/texlive/copying.html), [About MacTeX](https://tug.org/mactex/aboutmactex.html).

## 9. Conflitos e tentativas de refutação

### “WKWebView em processo separado torna HTML seguro”

Refutação: processo separado reduz o impacto de um exploit, mas o processo ainda pode ser comprometido por WebKit. Se tiver acesso a recursos locais, rede ou bridge nativa, a exploração pode continuar relevante.

### “Desactivar JavaScript resolve HTML hostil”

Refutação: HTML pode fazer pedidos passivos através de imagens, CSS e outros recursos. DOMPurify declara explicitamente que não é um CSS sanitizer nem bloqueia todos os HTTP leaks.

### “Sanitizar com DOMPurify basta”

Refutação: a biblioteca não protege se não for chamada correctamente, não protege sinks posteriores, não cobre CSS por defeito e tem riscos associados a versões/configurações. Sanitização deve ser combinada com CSP, JavaScript desligado e isolamento de paths.

### “PDF é apenas output visual”

Refutação: PDF pode conter annotations e actions de URL, Launch, remote go-to, attachments e formulários. O comportamento exacto do PDFKit deve ser testado na versão de macOS alvo.

### “App Sandbox resolve a execução de LaTeX externo”

Refutação: a documentação da Apple indica que permissões de ficheiro escolhido pelo utilizador não autorizam executar programas fora da app, container ou app group. A instalação externa de MacTeX não deve ser assumida compatível com uma app sandboxed distribuível.

### “Notarização valida a segurança da app”

Refutação: notarização verifica a app distribuída, assinatura e problemas detectáveis pelo serviço. Não valida o conteúdo local que o utilizador abrirá nem substitui controlos de runtime.

### “TeX Live restricted shell escape torna compilação segura”

Refutação: reduz a capacidade de executar comandos, mas não torna macros, pacotes, ficheiros auxiliares ou conversores confiáveis. Também não resolve automaticamente leitura/escrita de ficheiros nem exaustão de recursos.

## 10. Recomendação condicional

### Recomendação com confiança alta

Para Markdown:

- `WKWebView`;
- conteúdo tratado como não confiável;
- HTML sanitizado com allow-list;
- JavaScript de conteúdo desligado;
- CSP de defesa em profundidade;
- nenhum bridge nativo desnecessário;
- recursos limitados à raiz autorizada;
- navegação externa apenas por acção explícita;
- data store não persistente;
- sem entitlement de rede se o MVP não precisar de rede.

Para LaTeX:

- PDFKit como superfície de leitura;
- acções PDF tratadas explicitamente;
- nenhum abrir automático de paths ou aplicações externas;
- compilação fora da pasta raw;
- limites de processo e outputs;
- shell escape desligado/restrito.

### Condicional decisiva

Se a prioridade futura for App Sandbox e Mac App Store, a estratégia LaTeX deve partir de executáveis auxiliares empacotados, assinados e compatíveis com sandbox/XPC. O custo de empacotar TeX Live completo, ou de seleccionar uma distribuição mínima, deve ser avaliado antes de fechar essa arquitectura.

Se a prioridade for apenas um protótipo pessoal no próprio Mac, pode ser aceitável depender de uma instalação TeX externa, mas isso deve ser registado como risco operacional e de segurança aceite — não como uma solução sandboxed ou universalmente segura.

Confiança:

- APIs de WebKit/PDFKit: alta.
- Modelo de permissões App Sandbox: alta.
- Riscos do TeX shell escape: alta.
- Compatibilidade exacta entre MacTeX externo, sandbox e cada modalidade de distribuição: média/baixa sem teste local.
- Segurança adversarial da cadeia completa: média/baixa sem protótipo e testes de corpus.

## 11. Implicações para o MVP

### Riscos aceites

Condicionalmente aceitáveis para uso pessoal:

- residual de vulnerabilidades em WebKit, PDFKit ou parsers;
- conteúdo que consuma recursos, desde que exista timeout e recuperação;
- necessidade de o utilizador conceder acesso à pasta;
- dependência de uma instalação TeX externa, se o MVP não for sandboxed/distribuído;
- abertura de links externos apenas após confirmação explícita.

### Riscos mitigados

Devem ser tratados pela implementação escolhida:

- JavaScript e HTML activo;
- pedidos de rede não intencionais;
- referências fora da pasta;
- escrita do compilador na pasta original;
- shell escape arbitrário;
- execução de ferramentas auxiliares;
- perda de permissões após relançamento;
- PDFs com acções externas;
- dependências temporárias misturadas com o projecto;
- logs sem limite ou processos pendurados.

### Riscos adiados

Podem ficar fora da primeira validação, mas devem ser explícitos:

- suporte a JavaScript client-side;
- HTML arbitrário com forms, iframes, SVG ou CSS fornecido pelo documento;
- referências autorizadas fora da pasta escolhida;
- compilação de projectos com shell escape completo;
- instalação automática de pacotes TeX;
- distribuição sandboxed pela Mac App Store com TeX externo;
- auto-update;
- garantia contra todos os PDFs malformados;
- empacotamento completo de MacTeX/TeX Live.

## 12. Mensagens de erro e recuperação

A UI deveria distinguir, sem esconder a causa:

- “A pasta não foi autorizada pelo macOS.”
- “O ficheiro existe, mas está fora da raiz autorizada.”
- “O recurso foi bloqueado por política de preview.”
- “O PDF contém uma acção externa que não foi aberta.”
- “O compilador não foi encontrado ou não é compatível.”
- “A compilação excedeu o tempo limite.”
- “A compilação tentou usar shell escape não permitido.”
- “O PDF/HTML não pôde ser processado.”
- “O processo de preview terminou; pode ser reiniciado sem alterar os ficheiros raw.”

A recuperação deve permitir cancelar a compilação, reiniciar o renderer e apagar artefactos temporários sem tocar nos fontes.

## 13. Lacunas e próximos testes

Estes pontos requerem protótipo ou teste local:

1. comportamento de `WKWebView` com `loadFileURL`, HTML em memória e esquema app-owned;
2. acesso a imagens relativas, `..`, symlinks e paths absolutos;
3. eficácia real de CSP/meta CSP no modo de carregamento escolhido;
4. pedidos de rede do WebView sem entitlement de cliente;
5. execução de links e actions PDF em cada versão de macOS suportada;
6. PDFs com attachments, Launch actions, forms e documentos corrompidos;
7. herança de sandbox em helper e passagem de bookmarks;
8. possibilidade de executar MacTeX externo numa app sandboxed;
9. comportamento de `pdflatex`, `xelatex`, `lualatex`, BibTeX e ferramentas auxiliares sob shell escape desactivado/restrito;
10. timeout, terminação de árvore de processos e limites de memória/saída;
11. notarização de todos os executáveis empacotados;
12. matriz de licenças para qualquer subconjunto TeX redistribuído.

## 14. Ledger de fontes

| Fonte | Data/versão verificada | Estado | Razão |
|---|---|---|---|
| Apple WebKit documentation | Acesso 09-09-2026 | Usada | API primária para WebView, navegação, JavaScript e processos |
| Apple PDFKit documentation | Acesso 09-09-2026 | Usada | API primária para leitura e actions PDF |
| Apple Quick Look documentation | Acesso 09-09-2026 | Usada | Alternativa nativa de preview |
| Apple App Sandbox documentation | Acesso 09-09-2026 | Usada | Entitlements, folders, bookmarks e helpers |
| Apple Hardened Runtime/notarização | Acesso 09-09-2026 | Usada | Requisitos actuais de distribuição |
| TeX Live Guide 2026 | Publicado 21-02-2026; release 01-03-2026 | Usada | Shell escape, segurança e plataformas |
| MacTeX 2026 | Actualização indicada em 24-03-2026 | Usada | Compatibilidade, tamanhos e assinatura/notarização |
| DOMPurify Security Goals | Versão actual indicada: 3.4.15 em 09-09-2026 | Usada | Limites e advisories do sanitizer |
| W3C CSP Level 3 | Acesso 09-09-2026 | Usada | Base normativa para CSP |
| Adobe PDF documentation | Acesso 09-09-2026 | Parcialmente usada | Taxonomia de actions PDF; não usada para afirmar comportamento específico do PDFKit |
| Apple Developer Forums | Consultada durante descoberta | Rejeitada como evidência principal | Discussões úteis, mas não documentação normativa |
| MDN same-origin/file URLs | Consultada durante descoberta | Rejeitada para claims macOS | Fonte secundária; não substitui documentação WebKit/App Sandbox |
| Blogs, snippets, Stack Overflow e rankings | Não usados | Rejeitados | Não cumprem o requisito de fontes primárias atuais |
| Benchmarks comparativos | Não encontrados/necessários | Não usados | Não havia evidência comparativa aplicável ao fluxo específico do MVP |

## 15. Registo de pesquisa

| Query | Caminho de descoberta | Resultado |
|---|---|---|
| Q1 | Documentação local → contextos, brief, vision | Escopo, formato e modelo de ameaça |
| Q2 | Apple Developer → WebKit/WKWebView | Capacidades de HTML local, JS, navegação e processos |
| Q3 | Apple Developer → PDFKit/Quick Look | Superfícies e limitações de leitura |
| Q4 | Apple Developer → App Sandbox | Ficheiros escolhidos, bookmarks e entitlements |
| Q5 | Apple Developer → XPC/helper tools | Isolamento e limitações de child processes |
| Q6 | TUG → TeX Live/MacTeX | Shell escape, versões, tamanhos e licenciamento |
| Q7 | Apple Developer → Hardened Runtime/notarização | Requisitos de distribuição |
| Q8 | DOMPurify/W3C | Sanitização, CSP, CSS e leaks |
| Q9 | Adobe PDF documentation | Actions PDF e riscos de links/Launch |

## Razão para parar a pesquisa

A pesquisa encontrou evidência primária suficiente para:

- comparar as principais superfícies de preview;
- definir uma postura de defesa em profundidade;
- identificar o conflito material entre sandbox e compilador LaTeX externo;
- separar riscos aceites, mitigados e adiados;
- especificar os testes que faltam.

Continuar a pesquisa documental sem escolher a versão mínima de macOS, o modo de distribuição e a estratégia de compilação produziria principalmente mais detalhes sem resolver as incertezas centrais. Essas incertezas exigem testes locais e decisões posteriores do projecto, que este brief explicitamente não deve fechar.

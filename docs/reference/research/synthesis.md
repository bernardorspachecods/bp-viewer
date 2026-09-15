# Síntese técnica para decisão humana

Esta síntese reúne os quatro relatórios de investigação recebidos para o `bp-viewer`. Não revalida independentemente as fontes primárias citadas nos reports nem substitui testes no Mac e com os documentos reais de Bernardo. Quando uma conclusão depende de detalhe, a secção do report original é indicada.

**Estado de uso:** este é um registo de evidência e comparação, não a fonte de
verdade do produto. O MVP atual já adotou SwiftUI/AppKit nativo para uso pessoal
no macOS; as alternativas abaixo permanecem úteis para contexto e para decisões
técnicas ainda abertas, mas não são fonte do estado atual da app.

## 1. Resumo executivo

Os quatro reports permitem definir uma base segura para um protótipo, mas não permitem escolher automaticamente uma stack final. A decisão mais sólida neste momento é sobre os contratos e invariantes da aplicação, não sobre SwiftUI, Tauri, Electron, PDF, HTML, MacTeX, Tectonic, `remark` ou outro candidato.

### O que já pode orientar o MVP

- A pasta aberta pelo utilizador, as permissões e o estado da raiz devem ser modelados explicitamente. Uma string de caminho não basta para representar acesso persistente no macOS.
- O watcher deve ser tratado como sinal de invalidação. A verdade vem de novo snapshot/re-scan do filesystem; eventos podem ser agrupados, duplicados, perdidos ou indicar uma alteração de raiz.
- O adapter deve declarar dependências. Um Markdown pode depender de imagens e outros documentos; um LaTeX pode depender de `.tex`, `.bib`, `.sty`, `.cls`, imagens, fontes e ferramentas auxiliares.
- Renderizações devem ser versionadas por geração. Uma renderização antiga, mesmo que termine depois, nunca pode substituir o preview da alteração mais recente.
- Compilação e artefactos temporários devem ficar fora da pasta raw do utilizador. Processos precisam de timeout, cancelamento, captura de logs e diagnóstico estruturado.
- Markdown/HTML deve ser tratado como conteúdo não confiável: sanitização allow-list, JavaScript de conteúdo desligado, CSP, recursos confinados à raiz autorizada e navegação interceptada.
- LaTeX deve ser tratado como execução de ferramentas potencialmente perigosas: shell escape desligado por defeito, workspace temporário, limites de recursos e nenhuma instalação automática de pacotes no primeiro caminho.

### As escolhas que continuam humanas

- Se o preview de LaTeX deve privilegiar fidelidade visual do PDF compilado ou navegação/semântica de HTML.
- Se o primeiro alvo é um protótipo pessoal dependente de ferramentas instaladas no Mac ou uma aplicação distribuível e sandboxed.
- A comparação de shells continua como contexto; para o MVP atual, a escolha de produto já é nativo SwiftUI/AppKit. Uma reconsideração só faria sentido se o modo de distribuição ou os testes locais mudassem.
- Que dialecto Markdown, matemática, links fora da raiz, links externos e engines LaTeX fazem parte do uso real.

**Estado global:** há recomendações condicionais com confiança variável; não há decisão técnica final aprovada.

## 2. Estado atual: o que os quatro reports permitem afirmar e o que não permitem

### Factos reportados pelos agentes

Os reports apresentam como capacidades documentadas, ligadas às suas matrizes de claims e evidências:

- CommonMark é a base sintática mais clara; GFM acrescenta, entre outras coisas, tabelas, footnotes, task lists, strikethrough e autolinks. Nenhum destes standards fornece por si só bibliografia académica, includes ou referências semânticas entre capítulos ([Markdown → HTML](reports/markdown-html.md), secções 5–8).
- `cmark-gfm`, `markdown-it`, `micromark`, `remark`/`unified`, `swift-markdown` e `markdown-rs` cobrem partes diferentes do problema. `remark`/`unified` oferece uma cadeia AST extensível; `cmark-gfm` oferece um núcleo nativo pequeno; as outras alternativas têm combinações próprias de extensões, renderer e integração ([Markdown → HTML](reports/markdown-html.md), secção 6).
- Uma distribuição TeX tradicional com `latexmk` acompanha múltiplas passagens, ficheiros incluídos, gráficos e bibliografia; Tectonic oferece executável/bundle, cache e opções offline, mas tem diferenças de engine, bundle e Biber. TeX4ht, lwarp e LaTeXML convertem para HTML por caminhos diferentes do PDF original ([LaTeX → preview](reports/latex-preview.md), secções 5–9).
- No macOS, seleção de pastas, security-scoped bookmarks, FSEvents e `Process` têm APIs próprias. FSEvents pode coalescer ou perder eventos; `NSFilePresenter` não cobre todas as escritas low-level ([desktop e filesystem](reports/desktop-filesystem.md), secções 5 e 8).
- `WKWebView` e PDFKit oferecem superfícies adequadas para leitura, mas HTML e PDF podem conter riscos de navegação, recursos ou actions. App Sandbox e notarização reduzem determinados riscos e impõem restrições, mas não tornam conteúdo ou compiladores confiáveis ([preview, segurança e distribuição](reports/preview-security-distribution.md), secções 5–10).

### Inferências técnicas que os reports suportam

- Uma arquitetura por contratos — sessão, filesystem, watcher, índice de dependências, coordenador de renderização, runner de processos e sink de preview — reduz o acoplamento entre shell, adapters e formato do artefacto. É a recomendação central de [desktop e filesystem](reports/desktop-filesystem.md), secções 9–10.
- Pré-renderizar fora da WebView torna mais clara a separação entre leitura/resolução, parsing, sanitização e apresentação. Não elimina a necessidade de controlar HTML, URLs, recursos e CSP ([Markdown → HTML](reports/markdown-html.md), secção 7; [preview, segurança e distribuição](reports/preview-security-distribution.md), secção 7).
- PDF é a referência mais direta se “preview” significa confirmar a composição produzida pelo LaTeX. HTML é potencialmente melhor para estrutura, pesquisa e acessibilidade, mas abre uma fronteira de compatibilidade que precisa de ser aceite e medida ([LaTeX → preview](reports/latex-preview.md), secções 7, 15 e 16).

### O que os reports não demonstram

- Não demonstram um vencedor em memória, arranque, velocidade ou manutenção entre SwiftUI/AppKit, Tauri, Electron e Flutter. O report desktop rejeita benchmarks comparativos não controlados (claim C19).
- Não demonstram que uma cadeia Markdown reproduz os documentos reais de Bernardo, nem que KaTeX ou MathJax cobre a matemática usada.
- Não demonstram que MacTeX, BasicTeX ou qualquer instalação TeX externa possa ser usada numa aplicação sandboxed distribuída pela Mac App Store. O report de segurança identifica isto como incompatibilidade material a testar.
- Não demonstram que Tectonic seja compatível com a tese real, incluindo engine, fontes, paths, pacotes, bibliografia e Biber.
- Não demonstram equivalência visual geral entre PDF, TeX4ht, lwarp e LaTeXML.
- Não demonstram os valores corretos de debounce, estabilidade de escrita, timeout, limite de output ou memória.
- Não demonstram o comportamento efetivo de `WKWebView` e PDFKit perante todos os paths, symlinks, redirects, annotations e actions no macOS mínimo escolhido.

### Como ler as conclusões

Os quatro documentos são resultados de agentes de pesquisa. As suas fontes primárias, versões observadas, limitações e razões para parar estão preservadas nos reports originais. Nesta síntese:

- **Facto reportado** significa uma capacidade ou limitação que o agente ligou a documentação/evidência no report; não significa revalidação nesta tarefa.
- **Inferência técnica** significa uma conclusão de adequação derivada dos factos, com as limitações descritas.
- **Recomendação condicional** significa uma direção que só é válida sob determinadas prioridades ou resultados de testes.
- **Decisão de Bernardo** significa uma escolha de produto, uso, risco ou distribuição que não deve ser tomada pelo agente.

## 3. Decisões acionáveis sem preferência pessoal: contratos, invariantes, testes e guardrails que podem orientar o MVP

Estas não escolhem uma tecnologia. São um registo histórico das regras que os
reports sugeriram para o fluxo então descrito.

### 3.1 Contratos mínimos entre componentes

**Facto reportado:** [desktop e filesystem](reports/desktop-filesystem.md), secção 9, propõe contratos independentes. A forma abaixo é uma consolidação operacional desses contratos.

| Contrato | Deve representar | Não deve assumir |
|---|---|---|
| `ProjectSession` | raiz aberta, bookmark/referência, estado `available`, `permissionLost`, `rootMoved` ou `closed`, e associação de IDs a caminhos relativos | que um caminho textual continue autorizado depois de reiniciar |
| `FileSystemGateway` | listar, enumerar, ler, obter metadata, resolver caminho relativo e distinguir ausência, remoção, corrida e permissão | que a UI possa ler qualquer path arbitrário |
| `FileWatcher` | batches com sessão, sequência, paths observados, tipos de mudança e `rescanScope` | que um evento contenha o conteúdo final ou seja completo |
| `DependencyIndex` | manifesto por documento, dependências, referências não resolvidas e geração | que todos os auxiliares estejam visíveis na árvore ou dentro da raiz |
| `RenderCoordinator` | render por documento e revisão, cancelamento, geração e fila | que duas renderizações do mesmo documento possam publicar livremente |
| `ProcessRunner` | executável identificado, argumentos separados, ambiente, diretório temporário, stdout/stderr, timeout, cancelamento e estado final | que “processo terminou” implique “artefacto válido existe” |
| `PreviewSink` | artefacto, documento, geração e diagnósticos; rejeição de gerações antigas | que o artefacto seja sempre HTML ou sempre PDF |

**Invariante:** a UI recebe resultados aprovados pelo shell/coordenador; não inicia compiladores, não decide que um evento é conteúdo final e não lê paths arbitrários.

### 3.2 Invariantes de filesystem e atualização

**Recomendação condicional comum aos reports:**

1. Iniciar o watcher antes do primeiro scan.
2. Manter um snapshot atual da hierarquia observada.
3. Agrupar eventos próximos, mas fazer re-scan sempre que o evento indicar coalescing, perda, root change ou escopo incerto.
4. Reabrir e validar o conteúdo após eventos; não confiar apenas no path recebido.
5. Representar remoção, rename, raiz movida e perda de permissão como estados explícitos.
6. Calcular documentos afetados a partir do `DependencyIndex`, não apenas do ficheiro selecionado.
7. Incrementar uma geração quando uma alteração relevante for reconhecida.
8. Publicar apenas o resultado cuja geração ainda é atual.

**Testes mínimos:** escrita incremental; rename atómico; várias alterações rápidas; alteração de imagem, `.bib`, `.sty`, `.cls` ou include; remoção/rename de dependência; eventos coalescidos ou dropped; raiz movida/removida; bookmark stale; reinício; symlinks, Unicode, espaços e case-only rename.

### 3.3 Invariantes de compilação e artefactos

- Compilar num workspace temporário por projeto/root, fora da pasta raw.
- Passar argumentos separados ao processo, nunca uma shell command string derivada do conteúdo.
- Capturar stdout, stderr, log e, quando disponível, recorder/dependency file.
- Impor timeout, limite de output e cancelamento; verificar se descendentes relevantes terminam.
- Serializar compilação por root e impedir duas escritas concorrentes no mesmo output.
- Diferenciar sucesso, sucesso com warnings, PDF parcial, erro fatal, timeout, cancelamento, dependência ausente, ferramenta ausente e pedido de input.
- Manter o último preview válido apenas se a política de UX o confirmar, marcando-o como desatualizado e sem o apresentar como resultado atual.
- Não instalar pacotes automaticamente no fluxo base sem decisão explícita; instalação em runtime reduz esforço inicial, mas prejudica previsibilidade offline.

### 3.4 Guardrails de preview e conteúdo

**Recomendação condicional com confiança alta no report de segurança:**

- tratar Markdown/HTML, imagens, SVG e PDF como conteúdo potencialmente hostil;
- desativar JavaScript de conteúdo na `WKWebView` por defeito;
- sanitizar HTML depois das transformações que possam introduzir conteúdo inseguro, com allow-list pequena e versionada;
- aplicar CSP de defesa em profundidade e não expor bridge nativa desnecessária;
- bloquear `script`, handlers `on*`, `iframe`, `object`, `embed`, forms, `base` e HTML/SVG/CSS não validados;
- resolver recursos dentro da raiz canónica autorizada, com política explícita para `..`, paths absolutos e symlinks;
- interceptar navegação, redirects, novas janelas e downloads;
- não carregar links externos dentro do preview; se essa opção existir, exigir ação explícita;
- tratar actions PDF como comportamento a bloquear ou confirmar, nunca como simples desenho;
- manter o data store web não persistente se o preview não precisar de estado web;
- não conceder entitlement de rede se o MVP não precisar de rede.

**Limite importante:** estes guardrails são inferências de defesa em profundidade dos reports. Não constituem garantia de segurança contra bugs de WebKit, PDFKit, compiladores, parsers ou bibliotecas.

### 3.5 Critérios de aceitação transversais

O MVP só deve considerar um fluxo validado quando conseguir demonstrar, para um fixture representativo:

- abrir uma raiz autorizada e recuperá-la segundo a política escolhida;
- refletir alterações externas sem publicar estado incompleto ou obsoleto;
- localizar dependências mesmo que estejam ocultas no filtro da árvore;
- não escrever artefactos de compilação na pasta raw;
- mostrar erro estruturado sem perder automaticamente o último preview válido, caso essa UX seja escolhida;
- bloquear scripts, esquemas perigosos, escapes de raiz e actions externas não confirmadas;
- cancelar ou invalidar uma renderização lenta sem deixar uma geração antiga vencer;
- funcionar sem rede durante a utilização, dentro das dependências previamente disponibilizadas.

## 4. Matriz de decisões técnicas

“Estado” descreve o que os reports permitem fazer agora; não significa decisão aprovada.
Na linha do shell, “aberta” descreve apenas a comparação dos reports; o plano
atual já regista SwiftUI/AppKit como escolha do MVP pessoal.

| Decisão | Alternativas reais | Evidência dos reports | Trade-offs | Impacto | Estado |
|---|---|---|---|---|---|
| Shell desktop | SwiftUI/AppKit; Tauri 2; Electron 44; Flutter | [desktop](reports/desktop-filesystem.md), secções 6–7 e 12 | Nativo favorece permissões e integração; Tauri separa core Rust/UI web; Electron favorece Node/web aceitando bundle e releases; Flutter não mostrou vantagem específica | Afeta UI, IPC, permissões, empacotamento e adapters | **Aberta; opinião e testes locais** |
| Persistência da pasta | bookmarks security-scoped; equivalente mediado pelo shell; seleção a cada arranque | [desktop](reports/desktop-filesystem.md), E1–E2; [segurança](reports/preview-security-distribution.md), E12–E14 | Bookmarks preservam intenção, mas podem ficar stale e exigem `start/stop`; plugins Tauri não demonstram persistência macOS suficiente | Afeta restauração de tabs, acesso e distribuição sandboxed | **Contrato necessário; mecanismo aberto** |
| Semântica do watcher | FSEvents direto; watcher de framework; `notify`; Chokidar; Watchman | [desktop](reports/desktop-filesystem.md), E3–E5 e E8–E16 | APIs/abstrações variam em ergonomia; Watchman é mais robusto mas adiciona daemon; nenhum elimina snapshot e re-scan | Afeta atualização, CPU, instalação e recuperação | **Invariante fechada; implementação aberta** |
| Fonte de verdade da mudança | eventos; snapshot/re-scan | FSEvents pode coalescer, perder ou pedir `MustScanSubDirs` ([desktop](reports/desktop-filesystem.md), E3–E4) | Snapshot pode ser caro; eventos sozinhos são incompletos | Afeta correção da árvore e invalidação | **Snapshot/re-scan condicionalmente obrigatório** |
| Modelo de dependências | apenas ficheiro aberto; manifesto do adapter; re-scan amplo | [desktop](reports/desktop-filesystem.md), secções 9–10; [Markdown](reports/markdown-html.md), C12–C14; [LaTeX](reports/latex-preview.md), C7–C11 | Manifesto exige trabalho, mas observar só o ficheiro aberto perde imagens/includes/bibliografia | Afeta renders corretos e custo de scan | **Manifesto recomendado; detalhes abertos** |
| Coordenação de render | fila serial; concorrência limitada; cancelamento; descarte por geração | [desktop](reports/desktop-filesystem.md), secções 9–10; [LaTeX](reports/latex-preview.md), secção 12 | Serializar protege outputs; concorrência pode reduzir espera mas aumenta contenção e risco | Afeta UX, CPU e integridade do preview | **Geração e rejeição de antigos fechadas; limites abertos** |
| Markdown base | `remark`/`unified`; `cmark-gfm`/`swift-markdown`; `markdown-it`; `micromark`; `markdown-rs` | [Markdown](reports/markdown-html.md), secções 5–7 e 10 | AST/extensibilidade contra runtime/dependências; renderer próprio contra menor integração | Afeta dialecto, links, matemática, sanitização e manutenção | **Aberta; depende do runtime e corpus** |
| Matemática Markdown | KaTeX; MathJax; sem matemática inicial; renderer próprio | [Markdown](reports/markdown-html.md), C9–C10 e secção 7 | KaTeX é HTML estático/previsível mas não suporta `\\label`, `\\ref`, `\\eqref`; MathJax cobre mais mas é mais pesado/assíncrono | Afeta fidelidade e pipeline de segurança | **Aberta; fixture real obrigatório** |
| Saída LaTeX | PDF; HTML; híbrida PDF+HTML | [LaTeX](reports/latex-preview.md), secções 7, 15–16 | PDF maximiza fidelidade; HTML favorece estrutura/pesquisa/acessibilidade; híbrido duplica cadeias e falhas | Afeta definição de “preview”, viewer e custo | **Decisão de uso de Bernardo** |
| Engine/distribuição LaTeX | TeX Live/MacTeX + `latexmk`; MiKTeX; Tectonic; BasicTeX | [LaTeX](reports/latex-preview.md), secções 6, 8, 16; [segurança](reports/preview-security-distribution.md), secções 6–10 | TeX tradicional é mais abrangente; Tectonic simplifica instalação mas diverge em engine/cache/Biber; MiKTeX pode instalar pela rede | Afeta compatibilidade, offline, tamanho e suporte | **Aberta; corpus real e distribuição necessária** |
| Root LaTeX | escolha manual; descoberta heurística; configuração persistida | [LaTeX](reports/latex-preview.md), secção 9; visão, “LaTeX” | Capítulo isolado normalmente não compila; heurística pode encontrar zero/múltiplos candidatos | Afeta UX de abertura e dependências | **Comportamento de pedir escolha já previsto; algoritmo aberto** |
| Wrapper LaTeX | `latexmk`; watch do Tectonic; watcher/coordenador da app | [LaTeX](reports/latex-preview.md), C6–C8 e secções 12–13 | Watch externo não resolve root, debounce, geração, cancelamento nem concorrência | Afeta simplicidade e diagnóstico | **A app continua responsável; ferramenta aberta** |
| Superfície HTML | `WKWebView` estática; esquema app-owned; texto nativo; Quick Look | [segurança](reports/preview-security-distribution.md), secções 6–7; [Markdown](reports/markdown-html.md), secção 7 | `loadFileURL` é simples; esquema app-owned controla mais mas cria lógica; Quick Look controla menos | Afeta segurança, recursos e CSS | **WKWebView condicionalmente favorecida; configuração aberta** |
| Superfície PDF | PDFKit; Quick Look; Preview externo | [LaTeX](reports/latex-preview.md), C16; [segurança](reports/preview-security-distribution.md), C9–C11 | PDFKit dá controlo e pesquisa; Quick Look é simples; externo quebra fluxo | Afeta leitura, actions e isolamento | **PDFKit recomendação condicional; não aprovada** |
| Links e recursos locais | permitir dentro da raiz; negar fora; pedir autorização adicional | [Markdown](reports/markdown-html.md), C12 e secção 7; [segurança](reports/preview-security-distribution.md), secções 7.2–7.3 | Permitir aumenta compatibilidade; negar reduz superfície; autorização adicional complica UX/permissões | Afeta imagens, links e segurança | **Política de produto aberta; raiz canónica é guardrail** |
| Links externos | bloquear; abrir com ação explícita; carregar no preview | [segurança](reports/preview-security-distribution.md), secção 7.3 | Bloquear maximiza contenção; browser externo preserva utilidade mas desloca risco; carregar na WebView aumenta exposição | Afeta leitura e rede | **Recomendação condicional: não carregar automaticamente** |
| Segurança LaTeX | shell escape off; restricted allow-list; escape completo | [LaTeX](reports/latex-preview.md), C18; [segurança](reports/preview-security-distribution.md), C16–C17 | Off quebra documentos dependentes; restricted reduz risco mas não torna input confiável; completo é incompatível com postura defensiva inicial | Afeta compatibilidade e ameaça | **Off por defeito; exceções exigem decisão/teste** |
| Workspace de compilação | diretório raw; temp isolado; helper/XPC | [LaTeX](reports/latex-preview.md), secções 11 e 14; [segurança](reports/preview-security-distribution.md), secções 7.5 e 10 | Raw é simples mas expõe fontes; temp reduz danos; XPC melhora separação mas aumenta complexidade | Afeta segurança, limpeza e sandbox | **Temp fora da raiz é guardrail; grau de isolamento aberto** |
| Distribuição | protótipo local com TeX externo; app fora da App Store; App Store sandboxed com helpers empacotados | [segurança](reports/preview-security-distribution.md), C18–C21 e secção 10 | TeX externo reduz bundle mas conflita com sandbox; empacotar controla versões mas aumenta tamanho, assinatura, licenças e manutenção | Pode redefinir toda a arquitetura LaTeX | **Decisão de distribuição de Bernardo** |
| Offline | dependências empacotadas/cache completo; instalação em runtime; rede opcional | [Markdown](reports/markdown-html.md), escopo e C6–C7; [LaTeX](reports/latex-preview.md), C3–C5; [segurança](reports/preview-security-distribution.md), C18 | Cache completo é previsível; runtime conveniente mas depende de rede; Tectonic `--only-cached` falha com cache incompleto | Afeta primeiro arranque e falhas | **Uso sem rede é princípio; composição aberta** |
| Licenciamento | usar ferramentas externas; redistribuir subconjunto TeX; redistribuir stack JS/Rust | Ledgers dos quatro reports, sobretudo [LaTeX](reports/latex-preview.md), secções 14 e 21, e [segurança](reports/preview-security-distribution.md), E18 | Externo reduz inventário da app; empacotado exige inventário e assinatura por componente | Afeta distribuição e manutenção | **Validação legal/empacotamento pendente** |

## 5. Decisões que dependem da opinião/uso pessoal de Bernardo

As perguntas abaixo são deliberadamente simples. Cada opção tem uma consequência concreta; a recomendação é condicional e não uma decisão tomada nesta síntese.

### 5.1 O que significa “preview” de LaTeX para o uso principal?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Confirmar a composição visual da tese** — PDF | Se a pergunta diária for “a tese compilou e está visualmente correta”, começar por PDF com o engine compatível com a tese | Mais fidelidade; menos HTML semântico; é preciso PDFKit e política para actions PDF |
| **Navegar/pesquisar a estrutura** — HTML | Se headings, links, pesquisa e acessibilidade forem mais importantes que equivalência visual, testar TeX4ht/make4ht, lwarp e/ou LaTeXML | Mais transformação e incompatibilidade; não há equivalência visual garantida |
| **Querer os dois** — PDF + HTML | Só se ambos forem necessidades reais desde o início e houver capacidade para duas cadeias | Duplica compilação, diagnósticos, caches, validação e superfícies de segurança |

**Decisão de Bernardo:** qual destas tarefas justifica a primeira versão?

### 5.2 O primeiro objetivo é protótipo pessoal local ou aplicação distribuível?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Protótipo pessoal no Mac atual** | Permite validar cedo com ferramentas já instaladas, registando o risco aceite | Pode depender de MacTeX/BasicTeX externo; não prova compatibilidade sandboxed nem distribuição universal |
| **Aplicação fora da App Store, assinada/notarizada** | Avaliar depois de um protótipo, mantendo executáveis e licenças sob controlo | Mais liberdade operacional, mas todos os executáveis e helpers precisam de assinatura/notarização e inventário |
| **Mac App Store/App Sandbox** | Tratar a distribuição como requisito desde o primeiro teste de compilação | TeX externo não é uma solução simples; pode exigir helpers/XPC empacotados, bookmarks e custo elevado de distribuição |

**Decisão de Bernardo:** o custo de distribuição deve limitar o MVP ou pode ficar para depois?

### 5.3 Que prioridade deve escolher o shell desktop?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **SwiftUI/AppKit** | Se integração macOS, bookmarks e comportamento de app Mac forem prioridade | Menos bridging para permissões/processos; UI e infraestrutura ficam em Swift |
| **Tauri 2** | Se UI web e core Rust forem importantes e houver disponibilidade para bridge macOS própria | WebView natural e bundle potencialmente menor; scopes persistentes no macOS precisam de validação/implementação |
| **Electron** | Se TypeScript/Node e ferramentas web reduzirem muito o risco de desenvolvimento | IPC e tooling fortes; bundle maior e ciclo Chromium/Node mais frequente |
| **Flutter** | Se a futura multiplataforma pesar mais que a hipótese de preview WebKit nativo | UI compilada; nenhum ganho específico foi demonstrado para este MVP macOS-first |

**Decisão de Bernardo:** qual custo é mais aceitável: Swift/native, Rust/bridge, bundle Electron ou Flutter?

### 5.4 Qual dialecto e nível académico de Markdown são realmente necessários?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **CommonMark + GFM + matemática comum** | Se os capítulos usam estrutura, tabelas, footnotes e fórmulas sem semântica LaTeX avançada | Permite começar com pipeline mais limitada; não oferece bibliografia, includes ou `\\label`/`\\ref` de forma geral |
| **Markdown com AST e extensões académicas próprias** | Se links entre capítulos, referências, composição e diagnósticos forem parte do fluxo real | Favorece `remark`/`unified` ou AST equivalente; aumenta manutenção e contratos próprios |
| **Markdown como aproximação de LaTeX** | Se os documentos dependem de referências matemáticas/bibliográficas e composição LaTeX-like | Pode tornar LaTeX/PDF o caminho principal; KaTeX provavelmente não basta para todos os casos |

**Decisão de Bernardo:** quais são os três ficheiros Markdown reais que devem ser suportados primeiro?

### 5.5 Dependências fora da pasta raiz devem funcionar?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Negar fora da raiz** | Se contenção e previsibilidade forem prioridade | Política simples e segura; alguns projetos existentes deixam de compilar/renderizar |
| **Pedir autorização adicional** | Se há dependências legítimas fora da raiz e Bernardo aceita uma decisão explícita | Mantém controlo; exige múltiplos scopes/bookmarks, watcher adicional e UX de permissões |
| **Permitir automaticamente** | Só se a conveniência superar claramente a ameaça | Maior compatibilidade, mas contraria a postura de raiz autorizada e aumenta exfiltração/escrita acidental |

**Decisão de Bernardo:** os projetos são autocontidos ou é normal partilharem recursos fora da pasta aberta?

### 5.6 Como devem funcionar links externos?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Bloquear** | Se o preview deve permanecer offline e estritamente local | Maior contenção; links web deixam de ser úteis |
| **Abrir externamente após ação explícita** | Se links bibliográficos/web são úteis, mas não devem carregar na WebView | Preserva utilidade com decisão visível; desloca o risco de rede para o browser |
| **Carregar no preview** | Apenas se interatividade/rede for requisito real | Exige política CSP/rede muito mais ampla e aumenta a superfície de ataque |

**Decisão de Bernardo:** links externos fazem parte da tarefa de leitura ou são apenas conveniência?

### 5.7 Quão compatível deve ser a compilação LaTeX?

| Opção | Recomendação condicional | Consequência |
|---|---|---|
| **Compatibilidade com o ambiente atual da tese** | Se a tese já compila num engine/distribuição conhecidos | Melhor probabilidade de fidelidade; dependência externa e configuração local tornam-se centrais |
| **Ambiente controlado/portável** | Se reprodutibilidade, offline e distribuição pesarem mais | Considerar Tectonic ou TeX empacotado, mas validar engine, Biber, fontes, paths e licenças |
| **Compatibilidade ampla com projetos TeX arbitrários** | Só com aceitação de custo elevado | Aproxima TeX Live/MacTeX completo; aumenta bundle, superfície de execução e suporte |

**Decisão de Bernardo:** a app precisa de abrir a tese dele ou de ser uma ferramenta geral para projetos LaTeX?

## 6. Conflitos e incompatibilidades entre reports

### 6.1 HTML flexível versus segurança e simplicidade

O report Markdown favorece `remark`/`unified` quando JavaScript é aceitável, devido ao AST, transformações de links, matemática e sanitização. O report de segurança favorece `WKWebView` com HTML estático e JavaScript desligado. Não há contradição necessária: o JavaScript pode existir no processo local de pré-renderização e ser excluído do conteúdo entregue à WebView. Há, porém, uma decisão de empacotamento/runtime e uma pipeline de compatibilidade a validar.

### 6.2 `cmark-gfm`/nativo versus `remark`/AST rico

`cmark-gfm` ou `swift-markdown` reduzem dependências e favorecem integração nativa, mas exigem renderer próprio para links, âncoras, matemática e políticas de recursos. `remark`/`unified` reduz esse trabalho de transformação, mas aumenta a superfície de pacotes, a importância da ordem dos plugins e a necessidade de pinning. O report não mede o custo real no corpus de Bernardo; a escolha depende do shell, do runtime aceitável e das extensões necessárias.

### 6.3 PDF fiel versus HTML navegável

O report LaTeX não trata PDF e HTML como equivalentes. PDF preserva melhor o resultado do motor original; HTML oferece vantagens de estrutura, pesquisa e acessibilidade. Escolher HTML por ser mais fácil de inserir numa WebView pode falhar na tarefa principal de conferir uma tese. Escolher PDF pode sacrificar semântica e flexibilidade de navegação. Esta é uma decisão de uso, não uma conclusão apenas técnica.

### 6.4 TeX externo versus App Sandbox/Mac App Store

O report LaTeX recomenda validar primeiro uma cadeia tradicional e admite Tectonic como alternativa operacional. O report de segurança alerta que uma permissão de ficheiro escolhido pelo utilizador não autoriza simplesmente executar programas externos fora da app, container ou app group numa aplicação sandboxed. Assim, “usar MacTeX instalado” pode ser aceitável para um protótipo pessoal, mas não deve ser promovido automaticamente a arquitetura de distribuição sandboxed.

### 6.5 Watch mode da ferramenta versus watcher da aplicação

`latexmk` e Tectonic têm modos de watch; Tauri, Chokidar e `notify` têm abstrações de watch. Nenhum report permite concluir que isso substitui o coordenador do `bp-viewer`: continuam necessários root discovery, dependências, debounce, snapshot/re-scan, geração, cancelamento e proteção contra resultados obsoletos.

### 6.6 Tectonic simples versus TeX Live abrangente

Tectonic reduz instalação e pode operar com cache, mas usa essencialmente XeTeX, pode precisar de Biber externo/compatível e divergir de paths/configurações tradicionais. TeX Live/MacTeX é mais abrangente, mas grande e difícil de empacotar/limitar. A release 0.17.0 corrigiu um problema específico de macOS ARM64 reportado contra 0.16.x; isso exige testar versões concretas, não concluir que Tectonic é geralmente inadequado ou seguro.

### 6.7 Sanitização, CSP e JavaScript desligado não são substitutos

O report de segurança regista limites distintos: DOMPurify não é sanitizer completo de CSS nem bloqueador de leaks HTTP; CSP é defesa em profundidade; JavaScript desligado não impede todos os pedidos passivos; processo separado do WebKit reduz impacto mas não elimina bugs. A política precisa de combinar as camadas.

### 6.8 Versões observadas e integração

O report Markdown encontrou desalinhamentos entre `rehype-katex`/KaTeX e `rehype-mathjax`/MathJax; isso não prova incompatibilidade final, mas impede assumir que “latest” funciona. Os reports desktop e LaTeX também contêm snapshots de versões e instalações locais diferentes. Todos devem ser tratados como observações datadas, com pinning e teste local antes de qualquer decisão.

## 7. Proposta de ordem de validação/prototipagem, priorizada por risco

Esta ordem prioriza riscos que podem invalidar a arquitetura inteira, não a conveniência de implementação. É uma proposta de trabalho, não uma decisão de produto.

### 0. Fixar o cenário de validação

Antes do código, Bernardo deve escolher temporariamente: tese/corpus real ou fixtures representativos; macOS mínimo; protótipo pessoal ou distribuição sandboxed; e se o objetivo LaTeX é PDF ou HTML. Sem isto, os resultados não têm critério comum.

### 1. Validar a cadeia LaTeX real — risco máximo

Com uma cópia dos documentos e outputs num diretório temporário:

- identificar root, `\\input`/`\\include`, imagens, `.bib`, `.sty`, `.cls`, fontes e ferramentas;
- testar o engine atual da tese com TeX Live/MacTeX/instalação existente e `latexmk` quando disponível;
- testar bibliografia clássica e BibLaTeX/Biber se usados;
- testar paths com espaços/Unicode, erros, pacote ausente, imagem ausente e pedido interativo;
- testar recompilação após alterações e confirmar que nada é escrito na pasta raw;
- testar shell escape desligado e registar exatamente o que deixa de funcionar.

**Critério de saída:** há uma cadeia que compila o corpus prioritário com diagnósticos controláveis, ou está documentado que a tese exige uma capacidade ainda não suportada.

### 2. Validar o conflito distribuição–compilador

Testar separadamente execução local de desenvolvimento, app assinada/notarizada se relevante e sandbox. Verificar acesso ao root, passagem de bookmarks ao helper, execução de compiladores externos, herança de sandbox, XPC/helper, assinatura e dependências.

**Critério de saída:** está claro se o MVP aceita TeX externo como risco pessoal ou se precisa de executáveis empacotados. Se Mac App Store for requisito, este passo não pode ser adiado.

### 3. Validar filesystem, dependências e concorrência

Construir fixtures para o contrato, independentemente da UI final:

- snapshot inicial com watcher já ativo;
- escrita incremental e rename atómico;
- bursts de alterações e eventos coalescidos/dropped;
- alteração/remoção de imagens, includes e bibliografia;
- raiz movida, permissões perdidas e bookmark stale;
- render lento que termina depois de uma geração nova;
- cancelamento e árvore de processos.

**Critério de saída:** snapshot/re-scan, manifesto de dependências e rejeição por geração produzem sempre o estado correto nos cenários testados.

### 4. Validar contenção de HTML e PDF

Antes de aceitar um parser específico, testar `WKWebView`/PDFKit no macOS mínimo com scripts, handlers, `iframe`, SVG, URLs perigosas, imagens externas, `..`, symlinks, paths absolutos, redirects, downloads, attachments e PDF actions.

**Critério de saída:** cada tentativa é bloqueada, explicitamente permitida ou diagnosticada conforme a política escolhida; não se assume que a API fará a política sozinha.

### 5. Comparar pipelines Markdown no corpus real

Usar a fixture sugerida pelo report Markdown: headings, tabelas, footnotes, código, imagens, links, âncoras, matemática comum, `\\label`/`\\ref`/`\\eqref`, macros e erros. Comparar `remark`/`unified`, `cmark-gfm`/`swift-markdown`, `markdown-it`, `micromark` e/ou `markdown-rs` apenas onde forem candidatos ao shell escolhido.

**Critério de saída:** dialecto suportado, limitações e renderer matemático estão escritos com exemplos de entrada/saída e diagnósticos.

### 6. Validar shell, permissões e restauração de UX

Só depois dos riscos anteriores, comparar os shells com a mesma sessão: abrir pasta, lazy tree, tabs, reinício, bookmark, seleção, WebView/PDF, mensagens de erro e atualização.

**Critério de saída:** a decisão de shell é baseada no fluxo e nos testes locais, não em tamanho de bundle ou preferência abstrata.

### 7. Validar alternativas LaTeX de HTML apenas se HTML for escolhido

Comparar TeX4ht/make4ht, lwarp e LaTeXML com a tese/fixtures, incluindo bibliografia, cross-references, imagens, MathML, CSS, splitting e diagnósticos. Não usar listas de pacotes suportados como prova de fidelidade geral.

### 8. Validar empacotamento e manutenção

Fixar versões; repetir builds offline; verificar compatibilidade `rehype-katex`/KaTeX e `rehype-mathjax`/MathJax; inventariar licenças; testar Apple Silicon, assinatura, notarização e tamanho real. Só então transformar uma recomendação condicional em decisão técnica aprovada.

## 8. Perguntas abertas para continuar a discussão do produto

1. O caso principal é uma tese única de Bernardo ou vários projetos heterogéneos?
2. A primeira versão precisa de suportar LaTeX que já depende de `biber`, TikZ/PGFPlots, fontes do sistema, shell escape ou ferramentas externas?
3. Qual é o macOS mínimo aceitável?
4. A pasta raiz deve ser autocontida por contrato?
5. O utilizador deve poder conceder acesso a dependências fora da raiz, e esse acesso deve persistir?
6. Um capítulo LaTeX selecionado deve sempre compilar o root, ou deve existir uma opção para compilar o ficheiro selecionado isoladamente quando possível?
7. Como deve a app escolher entre zero, um ou vários roots candidatos, e onde deve persistir a escolha?
8. O último preview válido deve continuar disponível após erro? Como deve ser marcado e por quanto tempo?
9. O que significa “atualizado” quando uma imagem ou include muda durante a compilação?
10. Qual a política para symlinks: ignorar, mostrar sem seguir ou seguir dentro de uma allow-list?
11. Links `.md#heading` devem abrir/focar tabs, e como devem ser tratados links para ficheiros inexistentes?
12. MathJax é necessário pelas referências matemáticas reais, ou KaTeX cobre o corpus prioritário?
13. Footnotes são suficientes, ou Bernardo precisa de bibliografia/citações semânticas em Markdown?
14. CSS fornecido pelo documento deve ser permitido, limitado ou removido?
15. Links externos devem ser bloqueados ou abertos no browser mediante confirmação?
16. O MVP precisa de notarização/distribuição ou apenas de correr no Mac de desenvolvimento?
17. A app deve funcionar sem qualquer rede depois de instalada, incluindo pacotes/fontes TeX?
18. Qual o tempo de atualização aceitável para um capítulo pequeno, médio e grande?
19. Qual o comportamento desejado para uma compilação que exceda timeout ou consuma recursos excessivos?
20. O editor futuro muda algum contrato do viewer agora, além da separação arquitetural então prevista?

## 9. Claims que ainda exigem validação local

Os seguintes pontos aparecem nos reports como lacunas ou próximos testes. Não são factos já confirmados para o `bp-viewer`.

### Corpus e renderização

- Qual parser Markdown reproduz corretamente os ficheiros reais, incluindo HTML bruto, tabelas, footnotes, imagens, anchors, Unicode e blocos de código.
- Se os documentos reais precisam de includes, bibliografia, referências semânticas ou convenções fora de CommonMark/GFM.
- Se KaTeX cobre a matemática usada; em particular, `\\label`, `\\ref`, `\\eqref`, ambientes, macros e erros.
- Se MathJax funciona com a versão realmente resolvida e com o tempo/complexidade aceitáveis.
- Compatibilidade concreta entre `remark`/`rehype`, KaTeX/MathJax, sanitização e o HTML produzido.
- Fidelidade de TeX4ht/make4ht, lwarp e LaTeXML para a tese real, se HTML LaTeX for considerado.

### LaTeX e processos

- Qual root deve ser descoberto para cada projeto, incluindo zero ou múltiplos candidatos.
- Se TeX Live/MacTeX, BasicTeX, MiKTeX ou Tectonic compilam o corpus com o engine esperado.
- Compatibilidade de BibTeX, BibLaTeX, Biber, MakeIndex/Xindy, TikZ/PGFPlots, fontes e conversores.
- Efeito de shell escape desligado/restrito e necessidade de ferramentas auxiliares.
- Funcionamento offline com cache Tectonic completo/incompleto e sem instalação automática.
- Fecho da árvore de processos no cancelamento e ausência de locks/artefactos residuais.
- Tempo, memória, tamanho de logs e tamanho de artefactos sob documentos pequenos, médios e grandes.

### Filesystem e permissões

- Custo de snapshot/re-scan e lazy loading em árvores semelhantes às do projeto.
- Semântica concreta do backend escolhido perante rename atómico, escrita em blocos, bursts, coalescing e dropped events.
- Deteção de alterações em imagens, includes, `.bib`, `.sty`, `.cls` e dependências fora da raiz.
- Persistência, stale e recuperação de security-scoped bookmarks em build assinada/sandboxed.
- Acesso e reabertura após rename da raiz, perda de permissão, ACL/TCC e subpasta ilegível.
- Política de symlinks, ciclos, paths absolutos, `..`, volumes de rede/SMB e case-insensitive filesystem.
- Memória, arranque e responsividade reais dos shells; os reports não têm benchmark comparativo suficiente.

### Preview e segurança

- Comportamento de `loadFileURL`, `loadHTMLString(baseURL:)` e eventual esquema app-owned.
- Eficácia concreta de CSP/meta CSP no modo de carregamento escolhido.
- Pedidos de rede passivos sem entitlement e comportamento de imagens/CSS/URLs.
- Execução efetiva de scripts, handlers, redirects, downloads, novas janelas e esquemas perigosos.
- PDFKit perante URLs, `file:`, Launch, remote go-to, attachments, forms, JavaScript PDF, PDFs corrompidos ou muito grandes.
- Herança de sandbox, passagem de bookmarks e permissões ao helper/XPC.
- Assinatura/notarização de executáveis empacotados e matriz de licenças.

## 10. Mapa das fontes

Os quatro reports originais são as fontes de síntese e contêm os links para as fontes primárias, ledgers, versões observadas, registos de pesquisa, refutações e razões para parar. As fontes primárias não foram reconsultadas nesta tarefa.

- [Relatório: Markdown → HTML](reports/markdown-html.md) — parser, AST, GFM, matemática, links, sanitização e testes locais sugeridos.
- [Relatório: LaTeX → preview](reports/latex-preview.md) — PDF/HTML, engines, `latexmk`, Tectonic, multi-ficheiro, bibliografia, artefactos, segurança e testes locais.
- [Relatório: desktop e filesystem](reports/desktop-filesystem.md) — shells, permissões, FSEvents/watchers, contratos, filas, processos e testes de filesystem.
- [Relatório: preview, segurança e distribuição](reports/preview-security-distribution.md) — WebKit, PDFKit, sandbox, bookmarks, helpers/XPC, shell escape, distribuição e modelo de ameaça.

**Nota de procedência:** as referências a claims nesta síntese apontam para secções dos reports originais. A data, versão e força da evidência devem ser consultadas nesses documentos; não devem ser inferidas apenas a partir desta síntese.

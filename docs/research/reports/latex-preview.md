# Relatório de investigação: LaTeX → preview

Data de acesso: 2026-09-09.  
Repositório consultado: [mapa da pesquisa](../CONTEXT.md), [brief LaTeX](../latex-preview.md) e [visão](../../vision.md).

Não foram alterados ficheiros. A working tree está limpa.

## 1. Resumo executivo

Para teses LaTeX reais, PDF produzido pelo próprio motor LaTeX é a estratégia com maior probabilidade de preservar fidelidade visual, classes, pacotes, imagens, bibliografia e referências cruzadas.

A combinação tecnicamente mais abrangente é uma distribuição TeX local — TeX Live/MacTeX ou MiKTeX — com `latexmk`, usando diretórios de saída temporários e compilação serializada. `latexmk` deteta dependências através dos ficheiros gerados e suporta recompilação contínua de fontes, ficheiros incluídos e gráficos. ([CTAN latexmk](https://ctan.org/pkg/latexmk/), [manual latexmk 4.88](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf))

Tectonic reduz significativamente a instalação e encapsula o motor num executável, mas introduz dependência de bundles/cache, usa essencialmente XeTeX, requer atenção especial a `biber` e pode divergir de instalações TeX tradicionais. A versão 0.17.0 corrigiu problemas recentes no macOS, mas o histórico imediato recomenda validação contra a tese concreta. ([Tectonic manual](https://tectonic-typesetting.github.io/book/latest/), [release 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0))

HTML é viável, mas não deve ser tratado como equivalente visual automático ao PDF. TeX4ht, lwarp e LaTeXML usam modelos de conversão diferentes e podem exigir bindings, configurações específicas ou substituição de funcionalidades. A pesquisa não encontrou evidência independente suficiente para afirmar que algum deles reproduz geralmente a aparência de uma tese arbitrária.

## 2. Pergunta e decisão suportada

Foi investigado como processar e apresentar LaTeX local no macOS, sem assumir PDF, HTML, MacTeX ou qualquer motor específico.

A pesquisa permite concluir condicionalmente que:

- PDF é a opção de maior fidelidade quando o objetivo é ver o resultado da compilação original.
- HTML oferece melhor potencial para navegação estrutural, pesquisa, acessibilidade e integração com uma WebView, mas com maior risco de incompatibilidades.
- Uma instalação TeX tradicional é mais abrangente; Tectonic é operacionalmente mais simples, porém menos neutro face ao ecossistema TeX.
- A escolha final depende do corpus LaTeX real, do motor usado pela tese e da importância relativa de fidelidade visual, instalação simples, HTML semântico e acessibilidade.

Isto não fecha uma decisão de produto.

## 3. Escopo e pressupostos

Incluído:

- PDF, HTML e abordagens híbridas;
- TeX Live/MacTeX, BasicTeX, MiKTeX e Tectonic;
- `latexmk`, `make4ht`, lwarp e LaTeXML;
- documentos multi-ficheiro;
- `\\input`, `\\include`, imagens, bibliografia e referências;
- recompilação após alterações externas;
- logs, erros, avisos e processos bloqueados;
- diretórios temporários, shell escape, licenciamento e macOS;
- acessibilidade, seleção e pesquisa no preview.

Fora do escopo:

- framework desktop;
- viewer específico;
- implementação de código;
- editor LaTeX;
- decisão sobre funcionalidades de escrita;
- benchmark exaustivo ou validação com uma tese privada concreta.

## 4. Critérios de avaliação

Os critérios relevantes são:

- fidelidade visual ao resultado esperado da tese;
- suporte a classes e pacotes existentes;
- funcionamento offline;
- instalação e dependências externas;
- bibliografia e referências cruzadas;
- deteção de dependências;
- previsibilidade e tempo de recompilação;
- isolamento dos artefactos;
- diagnóstico de erros;
- segurança;
- acessibilidade e pesquisa;
- manutenção e distribuição no macOS.

Não foram atribuídos pesos numéricos, porque a documentação do projeto não os define.

## 5. Matriz de claims

| Claim | Importância | Estado | Evidência | Limitação |
|---|---:|---|---|---|
| C1. PDF produzido pelo motor original é a referência visual mais direta. | Alta | Inferência forte | E1, E2, E3 | Não prova que todos os viewers apresentem o PDF da mesma forma. |
| C2. TeX Live 2026 está disponível; MacTeX é a distribuição macOS baseada em TeX Live. | Alta | Facto | E4 | MacTeX é grande; BasicTeX é incompleto. |
| C3. MiKTeX oferece instalação de pacotes em tempo de execução. | Média | Facto | E5 | Pode tornar a primeira compilação dependente da rede e menos previsível. |
| C4. Tectonic é distribuído como executável único e pode obter ficheiros de suporte através de bundles. | Alta | Facto | E6 | Cache/bundle tem implicações para offline e reprodutibilidade. |
| C5. Tectonic suporta `--only-cached`, `--untrusted`, `--outdir`, logs e ficheiros de dependências. | Alta | Facto | E7 | Nem todas as funcionalidades correspondem às opções do TeX Live tradicional. |
| C6. Tectonic possui modo `watch` para reconstruir quando os inputs mudam. | Média | Facto | E8 | Watch não significa composição incremental por página. |
| C7. `latexmk` acompanha o ficheiro principal, ficheiros incluídos e gráficos. | Alta | Facto | E9 | Continua a depender dos comportamentos do motor e dos auxiliares. |
| C8. `latexmk` automatiza múltiplas passagens e ferramentas como BibTeX/Biber. | Alta | Facto | E9, E10 | Configurações não convencionais podem exigir `latexmkrc`. |
| C9. `\\input` e `\\include` permitem documentos multi-ficheiro; o compilador precisa de um root. | Alta | Facto/inferência | E11, E12 | Um capítulo isolado pode não ser compilável. |
| C10. Bibliografia e referências cruzadas exigem processamento adicional e mais de uma passagem. | Alta | Facto | E9, E10, E13 | O número concreto de passagens depende da cadeia usada. |
| C11. Biber e BibLaTeX devem ser mantidos em versões compatíveis. | Alta | Facto | E13 | A combinação exata deve ser verificada na instalação usada. |
| C12. TeX4ht converte através de LaTeX modificado e DVI auxiliar. | Alta | Facto | E14 | O caminho não é equivalente ao PDF final. |
| C13. make4ht suporta diretórios de saída, build files, BibTeX/Biber e pós-processamento. | Média | Facto | E15 | O próprio build file pode introduzir dependências e comandos externos. |
| C14. lwarp suporta muitos pacotes e pode gerar HTML com SVG ou MathJax. | Média | Facto | E16 | Requer Perl e utilitários Poppler; declara-se incompatível com Tagged PDF. |
| C15. LaTeXML produz HTML5, MathML, imagens e referências estruturadas através de bindings. | Média | Facto | E17 | A cobertura depende dos bindings; a versão publicada é mais antiga. |
| C16. PDFKit no macOS suporta apresentação, seleção, cópia, navegação e pesquisa. | Média | Facto | E18 | A integração concreta pertence ao brief do viewer. |
| C17. PDF acessível depende de tagging e do suporte dos pacotes usados. | Média | Facto/inferência | E19 | O projeto de tagging continua em desenvolvimento. |
| C18. Shell escape é uma superfície de risco e deve ser desativado por defeito. | Alta | Facto/recomendação | E20, E7 | Alguns documentos dependem dele, por exemplo para ferramentas externas. |
| C19. Tectonic teve problemas recentes específicos em macOS ARM64. | Alta | Facto limitado | E21, E22 | O problema foi corrigido em 0.17.0; não prova falha geral atual. |
| C20. A recomendação final depende do corpus real da tese. | Alta | Inferência | E1–E22 | Só testes locais podem confirmar compatibilidade. |

## 6. Alternativas investigadas

### A. TeX Live/MacTeX + `latexmk` + PDF

Fluxo:

1. escolher o ficheiro root;
2. executar `pdflatex`, `xelatex` ou `lualatex`;
3. executar BibTeX/Biber/MakeIndex quando necessário;
4. repetir até referências e bibliografia estabilizarem;
5. apresentar o PDF.

É a alternativa mais completa para uma tese já existente. TeX Live inclui os motores e ferramentas; MacTeX adiciona integração específica para macOS. O MacTeX 2026 requer macOS 11 ou superior, suporta Intel e Apple Silicon e o instalador completo tem aproximadamente 6,4 GB. ([MacTeX 2026](https://tug.org/mactex/mactex-download.html), [TeX Live 2026](https://tug.org/texlive/))

Limitações:

- instalação grande;
- versões e pacotes dependem da distribuição;
- `latexmk` pode não estar presente em instalações mínimas;
- determinados pacotes exigem Perl, Python, Ghostscript, `dvisvgm` ou shell escape;
- é necessário resolver a descoberta do root.

### B. BasicTeX

O BasicTeX inclui os motores principais, mas omite grande parte dos pacotes e ferramentas do MacTeX completo. ([BasicTeX/MacTeX](https://tug.org/mactex/morepackages.html))

É adequado para testar uma instalação pequena, mas menos previsível para teses reais: um pacote ausente pode exigir instalação posterior e alterar o ambiente durante a utilização.

### C. MiKTeX + PDF

MiKTeX funciona no macOS e pode instalar pacotes ausentes automaticamente. ([Instalação MiKTeX no macOS](https://miktex.org/howto/install-miktex-mac))

Vantagem:

- menor instalação inicial;
- comportamento conveniente quando faltam pacotes.

Riscos:

- primeira compilação pode depender da rede;
- o resultado depende da política de instalação automática;
- o ambiente pode mudar durante a compilação;
- distribuição e configuração são diferentes das do TeX Live.

### D. Tectonic + PDF

Tectonic é um motor baseado em XeTeX/TeX Live, distribuído como executável único. Obtém ficheiros de suporte através de bundles e pode manter artefactos fora da pasta de origem. ([Instalação Tectonic](https://tectonic-typesetting.github.io/book/latest/installation/), [compilação](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Vantagens:

- dependência principal simples;
- suporte nativo a Unicode e fontes modernas através da base XeTeX;
- opção `--only-cached` para impedir rede;
- opção `--untrusted` para desativar funcionalidades inseguras;
- `--outdir`, `--keep-logs`, `--synctex` e regras de dependência.

Riscos:

- é baseado em XeTeX, não em pdfTeX ou LuaTeX;
- compatibilidade com documentos dependentes de detalhes específicos de outros motores não é garantida;
- bibliografias BibLaTeX podem exigir `biber` externo ou `tectonic-biber`, com compatibilidade de versões;
- bundles/cache precisam de gestão;
- paths externos e configurações TeX tradicionais podem comportar-se de forma diferente.

A documentação atual indica que Tectonic V2 pode preferir um executável `tectonic-biber` para evitar incompatibilidades entre Biber e o BibLaTeX do bundle. ([Tectonic V2 CLI](https://tectonic-typesetting.github.io/book/latest/ref/v2cli.html))

A versão 0.17.0, publicada em 2026-07-27, corrigiu um `SIGBUS` em chamadas a `\\setmainfont` no macOS e melhorou o tratamento do watch mode. ([Tectonic 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0))

### E. TeX4ht + make4ht + HTML

TeX4ht não faz um parser independente completo: modifica macros LaTeX, produz um DVI auxiliar e transforma esse resultado em HTML/XML, MathML ou outros formatos. ([TeX4ht no CTAN](https://ctan.org/pkg/tex4ht?lang=en), [comandos TeX4ht](https://tug.ctan.org/support/TeX4ht/doc/mn-commands.html))

`make4ht` acrescenta:

- diretório de output;
- diretório de build;
- build files Lua;
- execução de BibTeX/Biber;
- conversão de imagens;
- pós-processamento;
- deteção de erros através do log.

A versão consultada é 0.4e, de 2026-02-24. ([make4ht no CTAN](https://ctan.org/pkg/make4ht?lang=en), [repositório make4ht](https://github.com/michal-h21/make4ht))

Vantagens:

- reutiliza a própria cadeia LaTeX;
- suporta HTML5, MathML e múltiplos ficheiros;
- permite customização detalhada.

Limitações:

- requer configuração quando a tese usa pacotes pouco suportados;
- o resultado visual depende de CSS e do tratamento de imagens;
- o caminho DVI/HTML pode divergir da composição PDF;
- não há modo oficial equivalente ao `latexmk -pvc` para todo o fluxo; o watcher teria de pertencer à aplicação ou à arquitetura envolvente.

### F. lwarp + HTML

lwarp também usa LaTeX para gerar HTML e declara suporte a mais de 500 pacotes/classes, MathJax ou SVG para matemática, compilação com LuaLaTeX/XeLaTeX/PDFLaTeX e integração com `latexmk`. Requer Perl e utilitários Poppler. A versão consultada é 0.922, de 2026-06-16. ([lwarp no CTAN](https://www.ctan.org/pkg/lwarp), [documentação lwarp](https://mirrors.ibiblio.org/pub/mirrors/CTAN/macros/latex/contrib/lwarp/lwarp.pdf))

Vantagem:

- alternativa HTML relativamente próxima do fluxo LaTeX;
- pode gerar versões de impressão e HTML;
- cobre um conjunto amplo de pacotes.

Limitações:

- a própria ficha do pacote marca “Tagged PDF – incompatible”;
- requer mais ferramentas externas;
- suporte declarado não equivale a fidelidade em todos os documentos;
- MathJax ou SVG podem aumentar a complexidade do preview.

### G. LaTeXML + HTML5/MathML

LaTeXML converte LaTeX para uma representação XML e depois faz pós-processamento para HTML5, XHTML, MathML, imagens, bibliografias e referências. Usa bindings específicos para classes e pacotes. ([manual LaTeXML](https://math.nist.gov/~BMiller/LaTeXML/manual/), [conversão](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/), [pós-processamento](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

Vantagens:

- melhor orientação para estrutura semântica;
- MathML e HTML5;
- divisão por capítulos/secções;
- tratamento explícito de labels, índice, bibliografia e cross-references.

Limitações:

- não é o mesmo motor que compõe o PDF;
- bindings ausentes podem exigir desenvolvimento específico;
- algumas conversões matemáticas são classificadas como experimentais;
- a versão estável consultada é 0.8.8, publicada em 2024-02-29. ([release LaTeXML 0.8.8](https://github.com/brucemiller/LaTeXML/releases/tag/v0.8.8))

## 7. Comparação fundamentada

| Estratégia | Fidelidade visual | Instalação | Offline | Multi-ficheiro | Bibliografia | Dependências | Diagnóstico |
|---|---|---|---|---|---|---|---|
| TeX Live/MacTeX + latexmk + PDF | Mais alta, se usar o motor esperado | Grande | Sim, após instalação | Forte | Forte | Muitas possíveis | Forte |
| MiKTeX + PDF | Alta | Inicialmente menor | Condicional | Forte | Forte | Pode instalar em runtime | Forte |
| Tectonic + PDF | Alta para documentos compatíveis com XeTeX | Pequena | Sim após cache pré-carregado | Forte, com diferenças de paths | Requer validar Biber | Bundle e possíveis ferramentas externas | Bom |
| TeX4ht + make4ht | Variável | Média | Sim | Boa | Boa, configurável | TeX + conversores | Bom via logs |
| lwarp | Variável | Média | Sim | Boa | Via LaTeX/latexmk | TeX + Perl + Poppler | Bom |
| LaTeXML | Estruturalmente rico, visualmente variável | Mais complexa | Sim após instalação | Boa | Tratada no pós-processamento | Perl/XML/XSLT/bindings | Bom |
| PDF convertido para imagens | Visualmente fiel | Depende de Poppler | Sim | Não resolve compilação | Igual ao PDF antes da conversão | Conversor de PDF | Fraco para texto/pesquisa |

A principal inferência é:

- se “preview” significa confirmar se a tese compilou como esperado, PDF é o candidato mais robusto;
- se “preview” significa explorar estrutura, pesquisar e navegar semanticamente dentro de uma WebView, HTML pode ser melhor, mas exige aceitar uma fronteira de compatibilidade;
- manter PDF e HTML em paralelo duplicaria a cadeia de compilação e os pontos de falha.

Não foi encontrada comparação independente suficientemente controlada para estabelecer diferenças gerais de qualidade, velocidade ou compatibilidade entre TeX4ht, lwarp e LaTeXML. Essas comparações devem ser tratadas como hipóteses a testar.

## 8. Dependências e compilação

### Cadeia tradicional

Dependências possíveis:

- `pdflatex`, `xelatex` ou `lualatex`;
- `latexmk`;
- BibTeX ou Biber;
- MakeIndex, Xindy ou ferramentas de glossário;
- conversores de imagem;
- fontes TeX ou fontes instaladas no macOS;
- Perl para `latexmk`;
- Python, Pygments ou outras ferramentas quando usados por pacotes;
- shell escape apenas quando indispensável.

Web2c documenta opções como `-interaction`, `-halt-on-error`, `-output-directory` e `-recorder`. O recorder escreve um `.fls` com os ficheiros abertos pelo processo. ([Web2c 2026](https://www.tug.org/texinfohtml/web2c.html))

Para um processo controlado pela aplicação, os princípios técnicos são:

- `nonstopmode` ou `batchmode` para impedir prompts interativos;
- `halt-on-error` para terminar cedo em erros fatais;
- `file-line-error` para melhorar a associação entre erro e linha;
- `recorder` para obter dependências;
- captura separada de stdout, stderr e `.log`;
- timeout externo;
- cancelamento do processo anterior antes de iniciar outro para o mesmo root.

`nonstopmode` não significa sucesso; warnings e erros recuperáveis têm de ser diferenciados do resultado final.

### Tectonic

O comando standalone suporta:

- `--outdir`;
- `--keep-logs`;
- `--keep-intermediates`;
- `--only-cached`;
- `--untrusted`;
- `--synctex`;
- `--makefile-rules`;
- número explícito de reruns.

No modo V2, os artefactos são colocados por defeito numa pasta `build`; os intermediários e logs podem ficar apenas em memória se não forem pedidos. ([Tectonic build](https://tectonic-typesetting.github.io/book/latest/v2cli/build.html), [Tectonic compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

A opção `--only-cached` é importante para o requisito sem cloud: impede ligações de rede, mas só funciona se todos os ficheiros necessários já estiverem disponíveis localmente.

### HTML

TeX4ht/make4ht e lwarp ainda executam LaTeX e, portanto, herdam:

- múltiplas passagens;
- bibliografia;
- geração de imagens;
- ferramentas externas;
- riscos de shell escape;
- necessidade de um root.

LaTeXML acrescenta uma segunda fase de pós-processamento. O manual descreve scanning, índice, bibliografia, cross-references, matemática, gráficos e XSLT como operações distintas. ([LaTeXML postprocessing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

## 9. Documentos multi-ficheiro

Um documento de tese típico pode ser:

```text
main.tex
chapters/
  introduction.tex
  methods.tex
  results.tex
figures/
  diagram.pdf
references.bib
```

A aplicação não pode assumir que o `.tex` selecionado é o root. Um capítulo incluído por `\\input` ou `\\include` normalmente não contém preâmbulo e não compila sozinho.

Implicações:

- descoberta automática do root é uma questão de produto/arquitetura ainda aberta;
- `\\include` pode gerar ficheiros auxiliares em subdiretórios;
- paths relativos devem ser preservados relativamente ao root;
- imagens e bibliografias partilhadas devem entrar no grafo de dependências;
- symlinks, paths absolutos e ficheiros fora da pasta aberta exigem política explícita.

LaTeXML documenta que `\\input` procura ficheiros `.tex` e `.sty`, enquanto `\\include` procura `.tex`; LaTeX tradicional e ferramentas de build têm regras próprias. ([LaTeXML conversion](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/))

## 10. Bibliografia e referências

`latexmk` é particularmente adequado para o cenário porque automatiza as passagens necessárias e deteta quando BibTeX/Biber precisa de voltar a correr. ([README latexmk](https://ctan.org/tex-archive/support/latexmk?lang=en))

BibLaTeX 3.22 e Biber 2.22 foram publicados em 2026-08-13. BibLaTeX declara Biber como backend próprio e Biber declara suporte a Unicode e processamento configurável. ([BibLaTeX 3.22](https://ctan.org/pkg/biblatex?lang=en), [Biber 2.22](https://ctan.org/pkg/biber/?lang=en))

Para o MVP, o teste deve cobrir pelo menos:

- BibTeX clássico;
- BibLaTeX + Biber;
- bibliografia global;
- bibliografias por capítulo;
- citações não resolvidas;
- atualização do `.bib`;
- incompatibilidade deliberada entre versões.

No caso Tectonic, a dependência Biber deve ser verificada separadamente, porque o bundle do Tectonic e o Biber instalado no sistema podem não corresponder.

## 11. Artefactos temporários

A compilação deve usar uma área fora da pasta da tese.

TeX tradicional suporta `-output-directory`; `latexmk` suporta `-outdir` e `-auxdir`, cria diretórios ausentes e documenta problemas possíveis com BibTeX/MakeIndex quando os diretórios são externos ou absolutos. ([manual latexmk, diretórios](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf))

Tectonic também suporta `--outdir`; no V2 usa uma pasta `build` por defeito. ([Tectonic compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Recomendação técnica condicional:

- colocar PDF, `.aux`, `.log`, `.fls`, `.synctex`, imagens derivadas e ficheiros de bibliografia numa pasta de cache temporária por projeto/root;
- nunca escrever artefactos automaticamente na pasta raw;
- associar o resultado ao caminho absoluto do root e à versão da cadeia de compilação;
- limpar caches apenas através de uma operação controlada.

## 12. Atualização e concorrência

`latexmk` possui modo de preview contínuo e acompanha fontes, includes e gráficos. ([latexmk no CTAN](https://ctan.org/pkg/latexmk/))

Tectonic possui `tectonic -X watch`, que observa inputs e reconstrói o documento. ([Tectonic watch](https://tectonic-typesetting.github.io/book/latest/v2cli/watch.html))

Para o `bp-viewer`, isto não elimina a necessidade da arquitetura de filesystem:

- a app ainda precisa de saber qual root reconstruir;
- vários eventos próximos devem ser agrupados;
- uma compilação antiga não deve substituir o resultado de uma alteração mais recente;
- duas compilações do mesmo root não devem escrever simultaneamente nos mesmos artefactos;
- uma compilação bloqueada precisa de timeout e cancelamento;
- alterações em imagens, `.bib`, `.sty`, `.cls` e ficheiros incluídos devem invalidar o preview.

A existência de `watch` não demonstra composição incremental por capítulo ou por página. A documentação descreve reconstrução do documento atual, não uma compilação parcial.

## 13. Erros, avisos e bloqueios

O resultado deve distinguir:

- compilação concluída com sucesso;
- PDF parcial gerado, mas com warnings;
- erro fatal sem PDF válido;
- erro fatal com PDF antigo disponível;
- processo terminado por timeout;
- processo cancelado por alteração posterior;
- dependência ausente;
- ferramenta externa ausente;
- shell escape bloqueado;
- processo aguardando input.

A informação útil inclui:

- mensagem;
- severidade;
- ficheiro;
- número da linha;
- engine;
- comando executado;
- duração;
- versão da distribuição;
- existência de artefacto anterior.

A documentação de make4ht confirma que o código de saída do TeX não distingue todos os erros e que o log precisa de ser analisado. ([make4ht, tratamento de logs](https://github.com/michal-h21/make4ht))

## 14. Segurança, permissões e distribuição

TeX Live recomenda cautela ao processar documentos desconhecidos, porque TeX e ferramentas auxiliares podem escrever ficheiros e executar comandos. ([TeX Live Guide 2026](https://tug.org/texlive/doc/texlive-en/texlive-en.html))

Shell escape deve ficar desativado por defeito. Tectonic também documenta shell escape como inseguro e oferece `--untrusted`. ([Tectonic security](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html))

Princípios condicionais:

- executar num diretório temporário dedicado;
- limitar paths de leitura/escrita;
- não ativar `--shell-escape` globalmente;
- definir allowlist por pacote/ferramenta quando for inevitável;
- impor timeout e limite de processos;
- não executar diretamente comandos derivados do conteúdo do documento;
- preservar as permissões da pasta escolhida pelo utilizador;
- tratar ficheiros fora da pasta aberta como caso explícito.

Licenciamento:

- TeX Live/MacTeX agregam componentes com licenças individuais; distribuição dentro de uma app exige inventário;
- `latexmk` é GPL;
- TeX4ht, make4ht e lwarp usam LPPL;
- Tectonic usa MIT, mas declara componentes derivados com várias licenças;
- Biber usa Perl Artistic License 2.

Fontes: [MacTeX licensing](https://tug.org/mactex/aboutmactex.html), [latexmk](https://ctan.org/pkg/latexmk/), [TeX4ht](https://ctan.org/pkg/tex4ht?lang=en), [make4ht](https://ctan.org/pkg/make4ht?lang=en), [lwarp](https://www.ctan.org/pkg/lwarp), [Tectonic LICENSE](https://github.com/tectonic-typesetting/tectonic/blob/master/LICENSE), [Biber](https://ctan.org/pkg/biber/?lang=en).

## 15. Fidelidade, acessibilidade e pesquisa

PDFKit no macOS fornece apresentação, seleção, cópia, navegação e pesquisa de documentos PDF. ([PDFKit](https://developer.apple.com/documentation/pdfkit), [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview))

Isto favorece PDF para:

- preservar layout da tese;
- copiar texto;
- pesquisar;
- navegar por páginas;
- lidar com tabelas, figuras e notas da forma produzida pelo motor original.

Acessibilidade não é automática. O LaTeX Tagging Project documenta que o núcleo atual consegue gerar PDF acessível/PDF-UA-2 em cenários suportados, mas o suporte dos pacotes contribuídos ainda está em evolução. LuaLaTeX tem suporte particularmente relevante para MathML associado. ([LaTeX Tagging Project](https://latex3.github.io/tagging-project/documentation/), [uso de PDF acessível](https://latex3.github.io/tagging-project/documentation/usage-instructions))

HTML pode oferecer:

- estrutura de headings;
- links internos;
- MathML;
- pesquisa textual mais direta;
- navegação por secções.

Mas depende de CSS, JavaScript, MathML/MathJax e da política do viewer. LaTeXML documenta explicitamente que pode ser necessário MathJax para plataformas sem suporte adequado a MathML. ([LaTeXML postprocessing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/))

## 16. Recomendação condicional

Recomendação técnica, não decisão de produto:

1. Validar primeiro uma cadeia PDF com o mesmo motor usado pela tese, preferencialmente através de TeX Live/MacTeX ou MiKTeX + `latexmk`.
2. Avaliar Tectonic como alternativa de menor custo operacional apenas se o corpus compilar corretamente com XeTeX/Tectonic, incluindo bibliografia, fontes, paths e pacotes externos.
3. Avaliar HTML como adapter separado, não como substituto implicitamente equivalente ao PDF.
4. Para HTML, começar por comparar TeX4ht/make4ht e lwarp com a tese real; considerar LaTeXML quando estrutura semântica/MathML for requisito importante.
5. Não ativar shell escape por defeito e não assumir que a instalação do utilizador contém todas as ferramentas.

Confiança:

- PDF tradicional: alta para fidelidade, média-alta para operação;
- Tectonic: média;
- TeX4ht/make4ht: média-baixa sem teste específico;
- lwarp: média-baixa;
- LaTeXML: média para estrutura, baixa-média para equivalência visual.

## 17. Implicações para o MVP

Sem fechar decisões:

- é necessário representar a relação entre ficheiro selecionado e root LaTeX;
- o adapter precisa de uma fase de descoberta ou configuração do root;
- a compilação deve ser isolada numa área temporária;
- dependências devem incluir `.tex`, `.bib`, `.sty`, `.cls`, imagens, fontes e outputs intermediários relevantes;
- os processos devem ser serializados por documento;
- o preview deve manter o resultado anterior quando uma recompilação falha, se essa for a decisão de UX;
- logs e erros devem ser tratados como dados estruturados;
- o ambiente local deve expor versões das ferramentas;
- “funciona offline” precisa de distinguir distribuição já instalada, cache de pacotes e ferramentas externas.

Estas são implicações técnicas; não constituem novas funcionalidades aprovadas.

## 18. Lacunas e próximos testes locais

Os testes devem usar uma área temporária fora do projeto, por exemplo:

```text
/tmp/bp-viewer-latex-fixtures/
```

### Matriz mínima

1. Documento mínimo com `main.tex`.
2. `main.tex` com três capítulos via `\\input`.
3. Capítulos via `\\include`, incluindo subdiretórios.
4. Referências cruzadas entre capítulos.
5. Bibliografia BibTeX.
6. Bibliografia BibLaTeX + Biber.
7. Imagens PNG, JPEG, PDF e SVG/EPS quando aplicável.
8. TikZ/PGFPlots.
9. Fonte do sistema via `fontspec`.
10. Pacote deliberadamente ausente.
11. Imagem deliberadamente ausente.
12. Erro de sintaxe.
13. Documento que solicita input interativo.
14. Processo externo que excede o timeout.
15. Alteração sucessiva de `main.tex`, capítulo, imagem e `.bib`.
16. Dois eventos de alteração enquanto a compilação está em curso.
17. Paths com espaços, Unicode, symlinks e ficheiros externos.
18. Modo offline com Tectonic e cache incompleto.
19. Pesquisa e cópia de texto no PDF.
20. Verificação de headings, links e MathML no HTML.

### Estratégias a comparar

Para cada fixture, registar:

- engine e versão;
- distribuição e versão;
- comando;
- primeira compilação;
- recompilação após alteração;
- duração;
- número de passagens;
- artefactos produzidos;
- resultado visual;
- warnings;
- erros;
- comportamento offline;
- necessidade de configuração específica.

O objetivo não deve ser apenas “gera um ficheiro”, mas verificar se o resultado corresponde ao documento real e se a cadeia permanece controlável após alterações externas.

## 19. Evidência

### E1 — TeX Live 2026 e macOS

TeX Live 2026 foi publicado em 2026-03-01; MacTeX é a distribuição macOS baseada em TeX Live.  
Fonte: [TeX Live](https://tug.org/texlive/), [MacTeX download](https://tug.org/mactex/mactex-download.html).

Estabelece: disponibilidade, versões e compatibilidade geral.  
Não estabelece: que MacTeX seja obrigatório para o projeto.

### E2 — Motores PDF

pdfTeX produz PDF diretamente; XeTeX suporta Unicode e fontes modernas; LuaTeX suporta Unicode, fontes OpenType/TrueType e Lua.  
Fontes: [pdfTeX](https://ctan.org/pkg/pdftex?lang=en), [XeTeX](https://ctan.org/pkg/xetex?lang=en), [LuaTeX](https://ctan.org/pkg/luatex?omit-dependencies=true).

Estabelece: diferenças documentadas entre engines.  
Não estabelece: qual engine é usado por uma tese específica.

### E3 — Web2c

Web2c documenta `-output-directory`, `-recorder`, `-halt-on-error` e modos de interação.  
Fonte: [Web2c manual 2026](https://www.tug.org/texinfohtml/web2c.html).

### E4 — `latexmk`

A versão consultada é 4.88, de 2026-03-09. O projeto documenta recompilação contínua, dependências, bibliografia, diretórios de saída e múltiplas passagens.  
Fontes: [CTAN latexmk](https://ctan.org/pkg/latexmk/), [README](https://ctan.org/tex-archive/support/latexmk?lang=en), [manual 4.88](https://www.cantab.net/users/johncollins/latexmk/latexmk-488.pdf).

### E5 — Tectonic

Tectonic oferece executável único, bundles, `--only-cached`, `--untrusted`, `--outdir`, logs e watch mode.  
Fontes: [instalação](https://tectonic-typesetting.github.io/book/latest/installation/), [compile](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html), [build](https://tectonic-typesetting.github.io/book/latest/v2cli/build.html), [watch](https://tectonic-typesetting.github.io/book/latest/v2cli/watch.html).

### E6 — Tectonic 0.17.0 e macOS

A release 0.17.0, de 2026-07-27, regista correções de `SIGBUS` no macOS e melhorias no watch mode.  
Fonte: [Tectonic 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0).

### E7 — Limitação recente do Tectonic

A issue #1345 reportou crashes em Tectonic 0.16.x no macOS ARM64 com `\\setmainfont`; a release posterior declara a correção.  
Fontes: [issue #1345](https://github.com/tectonic-typesetting/tectonic/issues/1345), [release 0.17.0](https://github.com/tectonic-typesetting/tectonic/releases/tag/tectonic@0.17.0).

Estabelece: necessidade de testar versões concretas.  
Não estabelece: uma incompatibilidade geral atual.

### E8 — TeX4ht/make4ht

TeX4ht usa LaTeX modificado e DVI auxiliar; make4ht acrescenta build files, output directories, ferramentas de bibliografia e parsing de logs.  
Fontes: [TeX4ht](https://ctan.org/pkg/tex4ht?lang=en), [comandos](https://tug.ctan.org/support/TeX4ht/doc/mn-commands.html), [make4ht](https://github.com/michal-h21/make4ht).

### E9 — lwarp

lwarp 0.922, de 2026-06-16, suporta muitos pacotes, MathJax/SVG, latexmk, Perl e Poppler.  
Fonte: [lwarp no CTAN](https://www.ctan.org/pkg/lwarp).

### E10 — LaTeXML

LaTeXML 0.8.8 é de 2024-02-29 e documenta bindings, HTML5, MathML, bibliografia, cross-references e splitting.  
Fontes: [release](https://github.com/brucemiller/LaTeXML/releases/tag/v0.8.8), [manual](https://math.nist.gov/~BMiller/LaTeXML/manual/), [conversion](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/conversion/), [postprocessing](https://math.nist.gov/~BMiller/LaTeXML/manual/usage/post/).

### E11 — Bibliografia

BibLaTeX 3.22 e Biber 2.22 foram publicados em 2026-08-13; BibLaTeX declara Biber como backend.  
Fontes: [BibLaTeX](https://ctan.org/pkg/biblatex?lang=en), [Biber](https://ctan.org/pkg/biber/?lang=en), [Tectonic V2 external tools](https://tectonic-typesetting.github.io/book/latest/ref/v2cli.html).

### E12 — Viewer e acessibilidade

PDFKit documenta seleção, cópia, pesquisa e navegação. O LaTeX Tagging Project documenta o estado atual do PDF acessível e as limitações do suporte dos pacotes.  
Fontes: [PDFKit](https://developer.apple.com/documentation/pdfkit), [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview), [Tagging Project](https://latex3.github.io/tagging-project/documentation/).

### E13 — Verificação local

No ambiente consultado em 2026-09-09:

- TeX Live 2026 BasicTeX;
- `pdflatex`, `lualatex`, `xelatex`;
- `make4ht`;
- `lwarpmk`;
- Tectonic 0.16.9;
- sem `latexmk`;
- sem `biber`;
- sem LaTeXML;
- sem `dvisvgm`.

Isto é apenas um snapshot local, não uma exigência do projeto.

## 20. Conflitos e refutações

- A simplicidade de instalação do Tectonic não implica compatibilidade equivalente à de TeX Live completo.
- “Suporta centenas de pacotes” em lwarp ou uma lista extensa de bindings em LaTeXML não prova fidelidade para a combinação específica de classe, macros e pacotes da tese.
- HTML com MathML pode ser estruturalmente melhor, mas requer suporte adequado do viewer e pode precisar de MathJax.
- PDF pode ser pesquisável e selecionável, mas não é automaticamente acessível.
- `watch` em `latexmk` ou Tectonic não resolve descoberta do root, agrupamento de eventos nem cancelamento seguro.
- Instalar pacotes automaticamente reduz o esforço inicial, mas diminui previsibilidade offline.
- Um benchmark externo encontrado durante a pesquisa foi rejeitado: não tinha condições suficientemente verificáveis para generalizar para uma tese privada, engines e corpus do `bp-viewer`.

## 21. Ledger de fontes

### Usadas

- Documentação local do projeto — fonte primária de escopo e restrições.
- TUG/TeX Live/MacTeX — distribuição, versões e macOS.
- Web2c — opções de execução e recorder.
- CTAN e manual do autor — latexmk, TeX4ht, make4ht, lwarp, BibLaTeX e Biber.
- Documentação e repositório oficial Tectonic — engine, bundles, watch, segurança e releases.
- Manual e repositório oficial LaTeXML — conversão, bindings e pós-processamento.
- Apple Developer Documentation — PDFKit.
- LaTeX Project Tagging Project — acessibilidade e tagging.

### Rejeitadas como evidência principal

- Wikipedia — fonte secundária e desnecessária quando havia documentação oficial.
- Reddit e comentários comunitários — úteis para descoberta de problemas, mas não usados para claims materiais.
- Snippets de pesquisa — não tratados como evidência.
- Benchmarks independentes sem corpus/condições equivalentes — não generalizáveis para o caso.
- Comunicações sobre popularidade ou preferência de engine — não demonstram adequação técnica.

## 22. Registo de pesquisas

- Q1 — versões atuais de TeX Live, MacTeX, BasicTeX e MiKTeX.
- Q2 — `latexmk`, dependências, continuous mode, output/aux directories e logs.
- Q3 — Tectonic, bundles, cache, segurança, watch mode e releases macOS.
- Q4 — TeX4ht e make4ht, HTML, MathML, imagens e build files.
- Q5 — lwarp, cobertura, engines, MathJax/SVG e dependências.
- Q6 — LaTeXML, bindings, bibliografia, MathML, splitting e versão.
- Q7 — pdfTeX, XeTeX, LuaTeX e input multi-ficheiro.
- Q8 — BibLaTeX, Biber e compatibilidade de versões.
- Q9 — PDFKit, pesquisa, seleção e navegação.
- Q10 — inventário local de ferramentas e versões.

## 23. Razão para parar

A pesquisa cobriu as estratégias, engines, distribuições, wrappers, multi-ficheiro, bibliografia, imagens, recompilação, artefactos, erros, segurança, licenciamento, acessibilidade e limitações exigidas pelo brief.

O que permanece incerto é empiricamente específico: qual cadeia compila a tese real com fidelidade suficiente, quais pacotes exigem configuração e quais tempos de recompilação são aceitáveis. Isso não pode ser resolvido por documentação genérica; requer os testes locais descritos acima.

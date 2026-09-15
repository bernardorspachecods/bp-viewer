# bp-viewer

Visualizador local para projetos académicos escritos em Markdown, LaTeX, JSON,
Word e PDF no macOS.

O `bp-viewer` abre uma pasta local, acompanha alterações aos ficheiros-fonte e
apresenta o resultado renderizado ou formatado. Ficheiros Markdown podem ser
editados no source, em modo integral ou numa split view com preview live.
Ficheiros PDF podem ser lidos diretamente dentro da app.

## Requisitos

- macOS compatível com a plataforma definida em `Package.swift`;
- toolchain Swift compatível com `Package.swift`;
- instalação local de LaTeX para abrir projetos `.tex`.

## Executar localmente

```bash
swift run BPViewer
```

Para desenvolvimento, use o launcher que observa `Sources/` e recompila a app
quando o código muda:

```bash
./scripts/dev-run.sh
```

Para gerar uma build `.app` local:

```bash
./scripts/build-app.sh
```

Para fechar instâncias antigas, recompilar e abrir uma instância nova:

```bash
./scripts/restart-app.sh
```

O bundle não inclui o TeX Live; a app usa a instalação LaTeX local do Mac.

## Validação rápida

Os runners validam a lógica principal sem depender de interação com a janela:

```bash
swift run BPViewerContractRunner
swift run BPViewerFoundationRunner
```

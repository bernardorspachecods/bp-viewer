# bp-viewer

Visualizador local para projetos académicos escritos em Markdown e LaTeX.

## Objetivo

Permitir navegar pelas pastas do computador e visualizar uma versão renderizada e atualizada dos ficheiros-fonte, sem editar esses ficheiros na aplicação.

O projeto é pessoal e começa focado em macOS.

## Estado

O shell nativo e o vertical slice Markdown estão implementados. O adapter LaTeX ainda está pendente.

## Executar

```bash
swift run BPViewer
```

Para desenvolvimento, o launcher observa `Sources/` e recompila/reinicia a
app automaticamente quando o código muda:

```bash
./scripts/dev-run.sh
```

O launcher é apenas uma ferramenta local de desenvolvimento; a app normal não
fica dependente dele.

## Validação automática

O contract runner valida o adapter Markdown sem precisar de uma janela gráfica:

```bash
swift run BPViewerContractRunner
```

O runner cobre headings/âncoras, links, imagens/dependências, CSP, remoção de HTML raw e matemática TeX comum.

O foundation runner valida as regras puras de filesystem, árvore lazy, filtros,
pesquisa, tabs e restauração:

```bash
swift run BPViewerFoundationRunner
```

Neste momento existem 50 verificações executáveis: 14 do Markdown e 36 das
fundações da app. O target `swift test` continua dependente de um toolchain que
disponha do módulo `Testing`; no CommandLineTools atual esse módulo não está
disponível.

## Princípios

- Os ficheiros raw do utilizador são a fonte única da verdade.
- A app lê, compila quando necessário e apresenta o resultado.
- Alterações feitas por ferramentas externas, incluindo LLMs, devem refletir-se no preview.
- O projeto deve funcionar localmente, sem cloud, contas ou base de dados.
- A complexidade deve ser adicionada apenas quando o fluxo pessoal a justificar.

## Documentação

- [Visão e plano atual](docs/vision.md)
- [Plano técnico inicial](docs/technical-plan.md)
- [Arquitetura de UI](docs/ui-architecture.md)
- [Índice da documentação](docs/README.md)
- [Plano de pesquisa técnica](docs/research/README.md)

# bp-viewer

Visualizador local para projetos académicos escritos em Markdown e LaTeX.

## Objetivo

Permitir navegar pelas pastas do computador e visualizar uma versão renderizada e atualizada dos ficheiros-fonte, sem editar esses ficheiros na aplicação.

O projeto é pessoal e começa focado em macOS.

## Estado

Fase inicial de definição e pesquisa. As decisões técnicas dos adapters de Markdown e LaTeX ainda não estão fechadas.

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

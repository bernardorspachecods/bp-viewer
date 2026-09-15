# Contexto de `Tests/`

Este diretório contém testes do Swift Package. O target atual
`BPViewerAppTests` verifica o core através de `MarkdownAdapterTests.swift`.

Os runners executáveis em [`Sources/`](../Sources/CONTEXT.md) são a validação
determinística usada quando o toolchain local não disponibiliza o módulo
`Testing`. Não duplicar nesses testes a lógica dos runners sem uma razão de
integração clara.

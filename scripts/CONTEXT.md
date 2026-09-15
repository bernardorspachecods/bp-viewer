# Contexto de `scripts/`

Scripts locais para desenvolvimento da app macOS:

- `dev-run.sh` recompila e reinicia a app quando `Sources/` muda.
- `build-app.sh [debug|release]` cria o bundle `.app` local e copia os
  recursos necessários.
- `restart-app.sh` fecha instâncias locais, recompila em `debug` e abre o
  bundle.

São ferramentas de desenvolvimento, não dependências do runtime da app. Os
artefactos são escritos em `.build/`

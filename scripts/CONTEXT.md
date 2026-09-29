# `scripts/` context

Local scripts for macOS app development:

- `dev-run.sh` rebuilds and restarts the app when `Sources/` changes.
- `build-app.sh [debug|release]` creates the local `.app` bundle and copies the
  required resources.
- `restart-app.sh` closes local instances, rebuilds in `debug`, and opens the
  bundle.

These are development tools, not app runtime dependencies. Artifacts are
written to `.build/`.

# `scripts/` context

Local scripts for macOS app development:

- `dev-run.sh` rebuilds and restarts the app when `Sources/` changes.
- `build-app.sh [debug|release]` creates the local `.app` bundle and copies the
  required resources.
- `restart-app.sh` closes local instances, rebuilds in `debug`, and opens the
  bundle.
- `install-app.sh` builds `release`, installs `Viewer.app` into `/Applications`
  (override with `BP_VIEWER_INSTALL_DIR`), and registers it with Launch Services.

These are development tools, not app runtime dependencies. Artifacts are
written to `.build/`.

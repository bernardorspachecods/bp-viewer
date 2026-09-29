# `Resources/` context

Static resources for the macOS bundle: `BPViewer-Info.plist` defines app
metadata, while `BPViewer.icns` and `BPViewer-logo.svg` are visual resources.

`scripts/build-app.sh` copies the plist and icon into the local bundle. Do not
put secrets, project data, or build artifacts in this directory.

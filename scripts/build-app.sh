#!/bin/zsh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
configuration="${1:-debug}"

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    print -u2 "Uso: $0 [debug|release]"
    exit 2
fi

swift build --configuration "$configuration" --product BPViewer
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
app_bundle="$repo_root/.build/$configuration/bp-viewer.app"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_directory/BPViewer" "$app_bundle/Contents/MacOS/BPViewer"
cp "$repo_root/Resources/BPViewer-Info.plist" "$app_bundle/Contents/Info.plist"
cp "$repo_root/Resources/BPViewer.icns" "$app_bundle/Contents/Resources/BPViewer.icns"

print "Created: $app_bundle"
print "Open file: open -a '$app_bundle' /path/to/main.tex"

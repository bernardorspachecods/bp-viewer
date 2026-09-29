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
app_bundle="$repo_root/.build/$configuration/Viewer.app"
legacy_app_bundle="$repo_root/.build/$configuration/bp-viewer.app"
bundle_identifier="com.bernardopacheco.bp-viewer"
signing_identity="${BP_VIEWER_CODESIGN_IDENTITY:-Apple Development: bernardopinvesfore@gmail.com (YA46UAZ7YP)}"

rm -rf "$app_bundle"
if [[ "$legacy_app_bundle" != "$app_bundle" ]]; then
    rm -rf "$legacy_app_bundle"
fi
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_directory/BPViewer" "$app_bundle/Contents/MacOS/BPViewer"
cp "$repo_root/Resources/BPViewer-Info.plist" "$app_bundle/Contents/Info.plist"
cp "$repo_root/Resources/BPViewer.icns" "$app_bundle/Contents/Resources/BPViewer.icns"

# Use the existing stable Apple Development identity so macOS can associate
# Accessibility permission with this app across rebuilds. Never fall back to
# ad-hoc signing, which changes the app identity and causes a permission loop.
codesign --force --sign "$signing_identity" \
    --identifier "$bundle_identifier" \
    "$app_bundle/Contents/MacOS/BPViewer"
codesign --force --sign "$signing_identity" \
    --identifier "$bundle_identifier" \
    "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

print "Created: $app_bundle"
print "Open file: open -a '$app_bundle' /path/to/main.tex"

#!/bin/zsh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
built_app="$repo_root/.build/release/Viewer.app"
install_dir="${BP_VIEWER_INSTALL_DIR:-/Applications}"
installed_app="$install_dir/Viewer.app"
bundle_identifier="com.bernardopacheco.bp-viewer"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

print "[bp-viewer] building release…"
"$repo_root/scripts/build-app.sh" release >/dev/null

print "[bp-viewer] closing running instances…"
osascript -e "tell application id \"$bundle_identifier\" to quit" >/dev/null 2>&1 || true
sleep 0.5

print "[bp-viewer] installing to $installed_app"
rm -rf "$installed_app"
ditto "$built_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"

"$lsregister" -f "$installed_app" >/dev/null
print "[bp-viewer] installed. To make it the default for Markdown: Finder > Get Info on a .md file > Open with > Viewer > Change All…"

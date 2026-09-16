#!/bin/zsh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
app_binary="$repo_root/.build/debug/BPViewer"
app_pid=""

snapshot() {
    {
        stat -f '%m:%z:%N' "$repo_root/Package.swift" "$repo_root/Package.resolved" 2>/dev/null || true
        find "$repo_root/Sources" -type f -print0 \
            | xargs -0 stat -f '%m:%z:%N' 2>/dev/null || true
    } | shasum -a 256 | awk '{print $1}'
}

stop_app() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    app_pid=""
}

build_and_start() {
    stop_app
    print "[bp-viewer] a compilar…"
    if ! (cd "$repo_root" && swift build --product BPViewer); then
        print -u2 "[bp-viewer] build failed; the app will restart when a new change is detected"
        return 1
    fi
    print "[bp-viewer] starting the app"
    "$app_binary" &
    app_pid=$!
}

trap stop_app EXIT INT TERM

last_snapshot="$(snapshot)"
build_and_start || exit 1

print "[bp-viewer] development mode active; changes in Sources/ restart the app"

while true; do
    sleep 1
    current_snapshot="$(snapshot)"
    if [[ "$current_snapshot" != "$last_snapshot" ]]; then
        last_snapshot="$current_snapshot"
        build_and_start || true
    fi
done

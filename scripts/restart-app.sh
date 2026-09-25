#!/bin/zsh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
app_bundle="$repo_root/.build/debug/Viewer.app"
bundle_identifier="com.bernardopacheco.bp-viewer"

stop_running_app() {
    osascript \
        -e "tell application id \"$bundle_identifier\" to quit" \
        >/dev/null 2>&1 || true

    local -a app_pids
    app_pids=("${(@f)$(pgrep -f "$repo_root/.build/.*BPViewer" 2>/dev/null || true)}")

    for pid in "${app_pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    if (( ${#app_pids[@]} > 0 )); then
        sleep 0.2
    fi

    for pid in "${app_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
}

print "[bp-viewer] closing old instances…"
stop_running_app

print "[bp-viewer] building…"
"$repo_root/scripts/build-app.sh" debug >/dev/null

print "[bp-viewer] starting a new instance"
open -na "$app_bundle"

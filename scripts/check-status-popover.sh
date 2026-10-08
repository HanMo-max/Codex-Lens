#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-lens-popover-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
cat "$ROOT/src-tauri/src/status_popover.swift" "$ROOT/native-widget/StatusPopoverHarness.swift" > "$CHECK_DIR/main.swift"
xcrun swiftc -module-cache-path "$CHECK_DIR/module-cache" "$CHECK_DIR/main.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"

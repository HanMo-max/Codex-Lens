#!/bin/zsh
# Development-only targeted WidgetKit refresh. Never call from the app's normal launch path.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: $0 /path/to/Codex Lens.app"
  exit 64
fi

SOURCE_APP="${1:A}"
INSTALL_APP="/Applications/Codex Lens.app"
EXTENSION_RELATIVE_PATH="Contents/PlugIns/CodexLensWidgetExtension.appex"
EXTENSION_EXECUTABLE_RELATIVE_PATH="$EXTENSION_RELATIVE_PATH/Contents/MacOS/CodexLensWidgetExtension"
SOURCE_EXTENSION="$SOURCE_APP/$EXTENSION_RELATIVE_PATH"

if [[ ! -d "$SOURCE_APP" || ! -d "$SOURCE_EXTENSION" ]]; then
  print -u2 "Expected Codex Lens.app with its embedded Widget extension."
  exit 65
fi

if [[ "$SOURCE_APP" == "$INSTALL_APP" ]]; then
  print -u2 "Use a newly built Codex Lens.app as the source, not the installed copy."
  exit 66
fi

codesign --verify --deep --strict "$SOURCE_APP"
codesign --verify --strict "$SOURCE_EXTENSION"

source_bundle_id="$(plutil -extract CFBundleIdentifier raw "$SOURCE_APP/Contents/Info.plist")"
extension_bundle_id="$(plutil -extract CFBundleIdentifier raw "$SOURCE_EXTENSION/Contents/Info.plist")"
[[ "$source_bundle_id" == "dev.codexlens.desktop" ]]
[[ "$extension_bundle_id" == "dev.codexlens.desktop.widget" ]]

staging_parent="$(mktemp -d "${TMPDIR:-/tmp}/codex-lens-widget-install.XXXXXX")"
staging_app="$staging_parent/Codex Lens.app"
cleanup() { rm -rf "$staging_parent"; }
trap cleanup EXIT
ditto "$SOURCE_APP" "$staging_app"

# The target is fixed and explicit; this is a development installation only.
if [[ -e "$INSTALL_APP" ]]; then
  rm -rf "$INSTALL_APP"
fi
mv "$staging_app" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
codesign --verify --strict "$INSTALL_APP/$EXTENSION_RELATIVE_PATH"

old_processes=()
while IFS= read -r pid; do
  executable="$(ps -p "$pid" -o comm= | sed -e 's/^[[:space:]]*//')"
  if [[ "$executable" == "$INSTALL_APP/$EXTENSION_EXECUTABLE_RELATIVE_PATH" ]]; then
    old_processes+=("$pid")
  fi
done < <(pgrep -x CodexLensWidgetExtension || true)

for pid in "${old_processes[@]}"; do
  kill -TERM "$pid"
done

open -a "$INSTALL_APP"
sleep 2

print "PlugInKit registration (if available):"
pluginkit -m -v -i "$extension_bundle_id" || true

replacement_path=""
while IFS= read -r pid; do
  executable="$(ps -p "$pid" -o comm= | sed -e 's/^[[:space:]]*//')"
  if [[ "$executable" == "$INSTALL_APP/$EXTENSION_EXECUTABLE_RELATIVE_PATH" ]]; then
    replacement_path="$executable"
    break
  fi
done < <(pgrep -x CodexLensWidgetExtension || true)

if [[ -n "$replacement_path" ]]; then
  print "Verified Widget extension process: $replacement_path"
else
  print "Installed and launched Codex Lens. WidgetKit has not started the extension yet; add or refresh its widget to start it."
fi

print "Use Codex Lens > Refresh now to publish a real snapshot and request the CodexLensWidget timeline reload."

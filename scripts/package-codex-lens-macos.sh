#!/bin/zsh
set -euo pipefail

: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to an Apple Development identity}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/src-tauri/target/release/bundle/macos/Codex Lens.app"
DERIVED_DATA="$ROOT/native-widget/provisioned-build"
EXTENSION="$DERIVED_DATA/Build/Products/Debug/CodexLensWidgetExtension.appex"
HOST_APP="$DERIVED_DATA/Build/Products/Debug/CodexLensWidgetHost.app"
HOST_PROFILE="$HOST_APP/Contents/embedded.provisionprofile"
EMBEDDED_EXTENSION="$APP/Contents/PlugIns/CodexLensWidgetExtension.appex"
APP_GROUP_CONFIG="$ROOT/native-widget/CodexLensAppGroup.xcconfig"
APP_ENTITLEMENTS_TEMPLATE="$ROOT/src-tauri/CodexLens.entitlements"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-lens-signing.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

APP_ENTITLEMENTS="$TEMP_DIR/CodexLens.expanded.entitlements"
SIGNED_APP_ENTITLEMENTS="$TEMP_DIR/signed-app-entitlements.plist"
SIGNED_EXTENSION_ENTITLEMENTS="$TEMP_DIR/signed-extension-entitlements.plist"

APP_GROUP_SUFFIX="$(sed -n 's/^[[:space:]]*CODEXLENS_APP_GROUP_SUFFIX[[:space:]]*=[[:space:]]*//p' "$APP_GROUP_CONFIG" | tail -n 1 | tr -d '[:space:]')"
test -n "$APP_GROUP_SUFFIX"
if [[ ! "$APP_GROUP_SUFFIX" =~ '^[A-Za-z0-9][A-Za-z0-9.-]*$' ]]; then
  echo "Invalid CODEXLENS_APP_GROUP_SUFFIX in $APP_GROUP_CONFIG" >&2
  exit 1
fi

TEAM_ID="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM_ID" ]]; then
  CERTIFICATE="$TEMP_DIR/signing-certificate.pem"
  security find-certificate -c "$CODE_SIGN_IDENTITY" -p > "$CERTIFICATE"
  TEAM_ID="$(openssl x509 -in "$CERTIFICATE" -noout -subject -nameopt RFC2253 | sed -n 's/.*OU=\([^,]*\).*/\1/p')"
fi
if [[ ! "$TEAM_ID" =~ '^[A-Z0-9]{10}$' ]]; then
  echo "Unable to resolve a valid 10-character Apple Team ID" >&2
  exit 1
fi
APP_GROUP_ID="$TEAM_ID.$APP_GROUP_SUFFIX"

cp "$APP_ENTITLEMENTS_TEMPLATE" "$APP_ENTITLEMENTS"
plutil -replace 'com\.apple\.security\.application-groups' -json "[\"$APP_GROUP_ID\"]" "$APP_ENTITLEMENTS"

cd "$ROOT"
npm run tauri -- build --bundles app

rm -rf "$DERIVED_DATA"
xcodebuild \
  -project "$ROOT/native-widget/CodexLensWidgets.xcodeproj" \
  -scheme CodexLensWidgetHost \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODEXLENS_APP_GROUP_ID="$APP_GROUP_ID" \
  clean build

test -d "$APP"
test -d "$EXTENSION"
plutil -replace CodexLensAppGroupIdentifier -string "$APP_GROUP_ID" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/PlugIns"
rm -rf "$EMBEDDED_EXTENSION"
ditto "$EXTENSION" "$EMBEDDED_EXTENSION"
if [[ -f "$HOST_PROFILE" ]]; then
  ditto "$HOST_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

codesign \
  --force \
  --sign "$CODE_SIGN_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" \
  --options runtime \
  --timestamp=none \
  "$APP"

codesign --verify --strict "$EMBEDDED_EXTENSION"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" > "$SIGNED_APP_ENTITLEMENTS" 2>/dev/null
codesign -d --entitlements :- "$EMBEDDED_EXTENSION" > "$SIGNED_EXTENSION_ENTITLEMENTS" 2>/dev/null

test "$(plutil -extract 'com\.apple\.security\.application-groups.0' raw "$SIGNED_APP_ENTITLEMENTS")" = "$APP_GROUP_ID"
test "$(plutil -extract 'com\.apple\.security\.application-groups.0' raw "$SIGNED_EXTENSION_ENTITLEMENTS")" = "$APP_GROUP_ID"
test "$(plutil -extract 'com\.apple\.security\.application-groups' json -o - "$SIGNED_APP_ENTITLEMENTS" | plutil -extract 1 raw -o - - 2>/dev/null || true)" = ""
test "$(plutil -extract 'com\.apple\.security\.application-groups' json -o - "$SIGNED_EXTENSION_ENTITLEMENTS" | plutil -extract 1 raw -o - - 2>/dev/null || true)" = ""
test "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$SIGNED_EXTENSION_ENTITLEMENTS")" = "true"
test "$(plutil -extract CodexLensAppGroupIdentifier raw "$APP/Contents/Info.plist")" = "$APP_GROUP_ID"
test "$(plutil -extract CodexLensAppGroupIdentifier raw "$EMBEDDED_EXTENSION/Contents/Info.plist")" = "$APP_GROUP_ID"
test "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = "dev.codexlens.desktop"
test "$(plutil -extract CFBundleIdentifier raw "$EMBEDDED_EXTENSION/Contents/Info.plist")" = "dev.codexlens.desktop.widget"
test "$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$TEAM_ID"
test "$(codesign -dv --verbose=4 "$EMBEDDED_EXTENSION" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$TEAM_ID"

if grep -Fq 'group.dev.codexlens.shared' "$SIGNED_APP_ENTITLEMENTS" "$SIGNED_EXTENSION_ENTITLEMENTS"; then
  echo "Legacy App Group leaked into signed entitlements" >&2
  exit 1
fi
if grep -Fq '$(' "$SIGNED_APP_ENTITLEMENTS" "$SIGNED_EXTENSION_ENTITLEMENTS" "$APP/Contents/Info.plist" "$EMBEDDED_EXTENSION/Contents/Info.plist"; then
  echo "Unexpanded build setting leaked into signed product" >&2
  exit 1
fi

echo "APP=$APP"
echo "TEAM_ID=$TEAM_ID"
echo "APP_GROUP_ID=$APP_GROUP_ID"

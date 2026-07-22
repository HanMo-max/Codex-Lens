# First-commit manifest

This is a reviewed proposal only. It does not stage, commit, publish, or create a remote repository.

## A. Commit

| Paths | Purpose | Risk review | Recommendation |
| --- | --- | --- | --- |
| `.gitattributes`, `.gitignore`, `package.json`, `package-lock.json`, `tsconfig.json`, `vite.config.ts`, `index.html` | Repository and frontend build configuration | No credentials or local paths found | Commit |
| `src/**` | React/TypeScript application source and unit tests | Source-only; no embedded secrets found | Commit |
| `src-tauri/Cargo.toml`, `Cargo.lock`, `build.rs`, `capabilities/**`, `gen/schemas/**`, `icons/**`, `src/**`, `tauri.conf.json`, `Info.plist`, `CodexLens.entitlements` | Tauri/Rust source, generated Tauri schemas, capabilities, and original application assets | No Team ID, signing product, profile, or account snapshot found | Commit |
| `native-widget/CodexLensAppGroup.xcconfig`, `CodexLensWidgetExtension/**`, `CodexLensWidgetHost/**`, `CodexLensWidgets.xcodeproj/project.pbxproj` | Native WidgetKit source and Xcode project | App Group remains build-setting driven; no personal Team ID | Commit |
| `native-widget/Fixtures/**`, `DecoderHarness.swift`, `SharedContainerHarness.swift`, `IMPLEMENTATION.md`, `README.md` | Sanitized fixture coverage, test harnesses, and widget documentation | Fixtures contain no account, token, path, or production snapshot | Commit |
| `scripts/package-codex-lens-macos.sh`, `scripts/refresh-codex-lens-widget-development.sh` | Explicit development packaging and targeted extension-refresh tooling | Refresh script is opt-in, scopes process handling to the Codex Lens extension, and does not clear system/widget data | Commit |
| `README.md`, `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `docs/*.md` | Open-source documentation, attribution, privacy/security boundary, and release templates | Upstream attribution and MIT notice retained | Commit |
| `.github/ISSUE_TEMPLATE/**`, `.github/workflows/**` | Issue templates and CI/release definitions | No secret values checked in | Commit |
| `docs/previews/codex-lens-five-hour-weekly.png`, `codex-lens-medium-dual.png`, `codex-lens-medium-weekly.png`, `codex-lens-small-dual.png`, `codex-lens-weekly-only.png`, `codex-lens-widget-comparison.png` | Reviewed WidgetKit Preview assets using fixture data | Not represented as account screenshots | Commit |

## B. Do not commit

| Paths | Purpose / risk | Recommendation |
| --- | --- | --- |
| `node_modules/`, `dist/`, `src-tauri/target/` | Dependency and frontend/Rust build output | Ignored; do not stage |
| `native-widget/provisioned-build/`, `native-widget/regression-build/`, `native-widget/integrated-build/`, `native-widget/unsigned-verify/`, `native-widget/build/`, `native-widget/signed-build/` | Xcode DerivedData, `.app`, `.appex`, signing/build output; existing output may contain local paths | Ignored; do not stage |
| `docs/previews/codex-lens-widget-desktop.png` | Full desktop capture containing private workspace/account-adjacent context | Ignored; keep private or redact and re-review before publishing |
| `docs/images/` | Legacy upstream product images not used by the Codex Lens README and not revalidated as current public assets | Ignored; do not stage unless individually re-reviewed |
| `scripts/*.bak.*`, `*.log`, `*.tmp`, `.DS_Store`, `.env*`, `auth.json`, `credentials.json`, `token.json` | Backup, log, local configuration, and credential-risk files | Ignored; do not stage |
| `*.app`, `*.appex`, `*.mobileprovision`, `*.p12`, `*.cer` | Installable/signing artifacts | Ignored by applicable patterns or excluded by review; never stage |
| `.agents/`, `.codex/`, `.idea/`, `.vscode/`, `**/xcuserdata/` | Local assistant/IDE/Xcode state | Ignored; do not stage |

## C. Manual confirmation

No unclassified files remain after the review. A future addition of a screenshot, account snapshot, certificate, profile, installer, or local configuration file requires a separate review before staging.

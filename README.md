# Codex Lens

Codex Lens is a local-first macOS utility that reads the current Codex model and quota state from an existing Codex Desktop login, then publishes a display-only snapshot to an integrated WidgetKit widget. It is an independent, unofficial project and is not affiliated with or endorsed by OpenAI.

## Features

- Shows the active model, weekly limit, optional rolling five-hour limit, and reset times returned by the quota service.
- Provides Small and Medium WidgetKit families. A weekly-only response uses a single-window layout; a five-hour window appears automatically when present and disappears automatically when absent.
- Keeps a last-known-good display-only snapshot so a damaged response or transient refresh failure does not fabricate quota data.
- Uses an Apple Team-ID-prefixed App Group shared only by the host app and its embedded Widget extension.
- Performs no telemetry, analytics, crash reporting, account changes, or reset-credit redemption.

## Widget previews and screenshots

The images below are WidgetKit Preview assets for documented layouts, not browser, HTML, React, or AI-generated mockups. They use fixture data rather than an account snapshot.

| Weekly only | Five-hour and weekly |
| --- | --- |
| ![WidgetKit Preview: weekly-only layout](docs/previews/codex-lens-weekly-only.png) | ![WidgetKit Preview: five-hour and weekly layout](docs/previews/codex-lens-five-hour-weekly.png) |

![WidgetKit Preview: layout comparison](docs/previews/codex-lens-widget-comparison.png)

The repository deliberately does not publish full-desktop captures or account-specific screenshots. A real desktop screenshot may be used for private validation only after all visible personal information has been reviewed and redacted.

## Requirements

- macOS 14 or later for the integrated WidgetKit extension.
- Node.js 20 or later, Rust stable, Xcode, and Tauri 2 prerequisites for a local build.
- An existing Codex Desktop login on the same Mac to read live quota data.
- An Apple Development Team selected in Xcode to install a signed local widget.

## Local development and build

```bash
npm install
npm run test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
cargo check --manifest-path src-tauri/Cargo.toml
npm run tauri dev
```

Browser development uses mock data. Live quota reads and WidgetKit integration require the Tauri application on a Mac with an existing Codex Desktop login.

To build the Widget extension without signing:

```bash
xcodebuild -project native-widget/CodexLensWidgets.xcodeproj \
  -scheme CodexLensWidgetExtension \
  -configuration Debug \
  -derivedDataPath /tmp/codex-lens-widget-build \
  CODE_SIGNING_ALLOWED=NO build
```

To create an integrated, locally signed application, choose a Team in Xcode and run:

```bash
CODE_SIGN_IDENTITY="Apple Development: …" DEVELOPMENT_TEAM="…" \
  scripts/package-codex-lens-macos.sh
```

The package script embeds `CodexLensWidgetExtension.appex` in `Codex Lens.app/Contents/PlugIns`, checks both signatures strictly, and checks the App Group and Team match. It does not publish, notarize, or distribute the result.

## Apple Team and App Group configuration

`native-widget/CodexLensAppGroup.xcconfig` keeps only the suffix:

```text
CODEXLENS_APP_GROUP_SUFFIX = dev.codexlens.shared
CODEXLENS_APP_GROUP_ID = $(DEVELOPMENT_TEAM).$(CODEXLENS_APP_GROUP_SUFFIX)
```

The selected Xcode Team expands this to `<YOUR_TEAM_ID>.dev.codexlens.shared`. Use the same Team for the main application and Widget extension. Do not commit a Team ID, certificate, provisioning profile, or account configuration.

The shared files are `widget-snapshot.json` and `widget-snapshot.last-known-good.json`. They contain only schema/version information, active model, normalized limit windows, timestamps, source, and stale state—never a token, cookie, account ID, or raw quota response.

## Install and add the widget

1. Build the signed integrated app with the same Apple Team for the app and extension.
2. Install the resulting `Codex Lens.app` locally and launch it.
3. Choose **Refresh now** from the tray menu to request a live snapshot.
4. On the desktop, choose **Edit Widgets**, search for **Codex Lens**, then add the Small or Medium widget.

## Refresh behavior and development troubleshooting

The app refreshes at startup, after wake, on manual refresh, and when reopened. After publishing a valid snapshot it calls `WidgetCenter.reloadTimelines(ofKind: "CodexLensWidget")`.

During development, macOS can keep an old Widget extension process alive after a new application has been installed. Use the explicit development-only command below only when that happens:

```bash
scripts/refresh-codex-lens-widget-development.sh /path/to/Codex\ Lens.app
```

It verifies the source app and embedded extension signatures, installs only `Codex Lens.app` to `/Applications`, terminates only a process whose executable path is the Codex Lens Widget extension, relaunches the app, and verifies that any replacement extension process comes from `/Applications/Codex Lens.app`. It never clears WidgetKit databases, removes desktop widgets, resets LaunchServices, changes App Group data, or terminates other widgets. The normal user launch path never invokes this command.

## Privacy

Codex Lens reads the local Codex Desktop login only to make the quota requests needed to display live status. It does not persist tokens, account IDs, prompts, chat history, raw quota responses, or local auth paths. It makes no calls to analytics, tracking, or crash-reporting services. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Known limitations

- Codex quota responses are not a public stable API; an unsupported response is shown as unavailable or stale rather than guessed.
- A signed local install requires a valid Apple Development Team and matching entitlements.
- The Widget can display only windows returned by the current quota response. When only the weekly window exists, it intentionally shows only that window.

## Frequently Asked Questions

### Why is Codex Lens missing from Widget Gallery?

Confirm that `CodexLensWidgetExtension.appex` is embedded inside the installed `Codex Lens.app/Contents/PlugIns`, the app and extension are signed with the same Team, and both have the same expanded App Group entitlement. Then launch the installed app once and search for **Codex Lens** in Widget Gallery.

### Why does the widget say it is waiting for synchronized data?

Launch Codex Lens and select **Refresh now**. The widget waits until the host app has published its first valid display-only snapshot to the shared App Group. It will not invent a value when login, signing, App Group access, or quota reading is unavailable.

### Why must I choose an Apple Development Team?

macOS requires a signing identity and entitlement authorization for a locally installed Widget extension. The Team supplies that authorization during development.

### How is the App Group generated automatically?

The source stores a suffix only. Xcode expands `$(DEVELOPMENT_TEAM).dev.codexlens.shared`, and the packaging script supplies the same expanded value to the main app before signing.

### Why must the main app and widget use the same Team?

They need matching signing authority and the same App Group entitlement to exchange the display-only snapshot. Mismatched Teams cannot safely share that container.

### Why might old UI remain after reinstalling?

WidgetKit may keep an old extension process alive. This does not mean WidgetKit storage is corrupt. Use the targeted development refresh command in the troubleshooting section; do not clear WidgetKit databases or delete unrelated widgets.

### How do I refresh only the Codex Lens Widget extension during development?

Run `scripts/refresh-codex-lens-widget-development.sh /path/to/Codex\ Lens.app`. It identifies the exact extension executable by its Codex Lens installation path before signalling it, then verifies the replacement path.

### Why does the widget currently show only the weekly limit?

The current quota response contains only a weekly window. The widget intentionally renders only data actually supplied by the service.

### Will the five-hour limit reappear automatically?

Yes. When a valid rolling five-hour window returns in a later snapshot, the Small and Medium widgets automatically switch to the dual-window layout.

### Does Codex Lens upload my account, model, or quota data?

No. It uses the existing local login only to make the required quota requests from the desktop process. It does not send data to a separate Codex Lens service and does not include tracking.

### Is Codex Lens an official OpenAI project?

No. Codex Lens is an independent, unofficial project and is not affiliated with or endorsed by OpenAI.

### Why can local builds fail at signing?

The selected Team may be missing, the signing identity may not match the provisioning authorization, or the host and extension entitlements may not match. Choose one Team for both targets and do not hard-code a Team ID.

### How do I refresh data manually?

Launch Codex Lens and use **Refresh now** in its tray menu. A successful snapshot publish requests a timeline reload for the Codex Lens widget kind.

### Do I need to clear WidgetKit data or remove every desktop widget?

No. Do not clear the WidgetKit database, remove other desktop widgets, reset LaunchServices, or delete App Group data as part of normal troubleshooting. The targeted development refresh command is the safe escalation for a stale Codex Lens extension process.

## Acknowledgements and upstream project

Codex Lens is based on and extends [Quota Float](https://github.com/change-42-yhmm/quota-float). The upstream project, repository address, MIT license, and copyright notice are retained. This repository is a copied-and-modified derivative, not a GitHub fork; the relationship and material changes are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

This project is released under the [MIT License](LICENSE), including the retained Quota Float copyright notice. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.

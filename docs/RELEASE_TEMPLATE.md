# Codex Lens <version>

Codex Lens is an independent, unofficial local macOS utility with a **desktop widget (桌面组件)** and a **menu bar status capsule (状态栏胶囊)** for viewing Codex quota and model status.

## Features

- Small and Medium WidgetKit desktop widgets show supported quota windows returned by the service, including weekly-only layouts.
- The native menu bar capsule shows five-hour remaining quota, a quota ring, and a reset countdown.
- Click the capsule for model, reset time, sync status, **Refresh now**, **Start at login**, and **Quit**.
- The capsule does not substitute weekly quota when five-hour data is missing; it displays stale or unavailable state.

## Downloads

List the exact attached filenames and platforms here. The current workflow uses `quota-float-windows-unsigned.zip` and `quota-float-macos-universal-unsigned.zip`.

State whether the macOS attachment is a plain Tauri build or a signed integrated app with `CodexLensWidgetExtension.appex`. A plain Tauri build includes the macOS capsule but does not automatically include the desktop widget extension. Windows builds do not include these macOS native surfaces.

## Install

1. Sign in to Codex Desktop on the same Mac to read live quota.
2. Install and launch the macOS app to use the status capsule.
3. For an integrated app with the signed embedded extension, use desktop **Edit Widgets** to add the Small or Medium Codex Lens widget.

Describe the actual signing and notarization status of each attachment. Do not mark an unsigned or unverified build as signed, notarized, or ready for public WidgetKit distribution.

## Privacy

Display-only shared snapshots contain model, normalized quota windows, reset/update times, source, and stale state. Tokens, account IDs, prompts, chats, and raw quota responses are not persisted. See [PRIVACY.md](../PRIVACY.md).

## Validation

Record the actual frontend, Rust, native popover, build, CI, and installation results for this release. Leave unperformed checks explicitly unverified.

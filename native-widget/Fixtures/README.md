# Widget development fixtures

These sanitized JSON snapshots are for SwiftUI previews, WidgetKit snapshot tests and development-only rendering. Production-format fixtures use `schemaVersion: 1`, `activeModel`, normalized `limitWindows`, `updatedAt`, `source`, and `isStale`. They contain no account, token, path, or production snapshot data. The production widget does not expose a fixture switch.

The fixture set covers weekly-only, five-hour-plus-weekly, five-hour-only, no-limits, unknown-window, malformed-data, partial-window corruption, invalid JSON, stale-cache, reset-time-missing, long-model-name, zero-percent, and full-percent states.

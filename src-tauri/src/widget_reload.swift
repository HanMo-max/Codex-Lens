import AppKit
import Dispatch
import OSLog
import WidgetKit

private let widgetReloadLogger = Logger(
    subsystem: "dev.codexlens.desktop",
    category: "widget-reload"
)

private let refreshLifecycleLogger = Logger(
    subsystem: "dev.codexlens.desktop",
    category: "refresh-lifecycle"
)

private var systemWakeObserver: NSObjectProtocol?

@_cdecl("codex_lens_reload_widget_timelines")
public func codexLensReloadWidgetTimelines() {
    let requestedAt = ISO8601DateFormatter().string(from: .now)
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    widgetReloadLogger.info(
        "Requested WidgetKit timeline reload bundle=\(bundleIdentifier, privacy: .public) kind=CodexLensWidget at=\(requestedAt, privacy: .public)"
    )
    DispatchQueue.main.async {
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexLensWidget")
        widgetReloadLogger.info(
            "Submitted WidgetKit timeline reload kind=CodexLensWidget at=\(requestedAt, privacy: .public)"
        )
    }
}

@_cdecl("codex_lens_start_power_observer")
public func codexLensStartPowerObserver(
    _ callback: @escaping @convention(c) () -> Void
) {
    guard systemWakeObserver == nil else { return }
    systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
    ) { _ in
        refreshLifecycleLogger.notice("system-wake-observed")
        callback()
    }
    refreshLifecycleLogger.notice("system-wake-observer-started")
}

@_cdecl("codex_lens_log_refresh_event")
public func codexLensLogRefreshEvent(_ message: UnsafePointer<CChar>) {
    refreshLifecycleLogger.notice("\(String(cString: message), privacy: .public)")
}

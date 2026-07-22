import Foundation
import OSLog
import SwiftUI
import WidgetKit

private let widgetTimelineLogger = Logger(
    subsystem: "dev.codexlens.desktop",
    category: "widget-timeline"
)

private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
    let path = codingPath.map { key in
        key.intValue.map { "[\($0)]" } ?? key.stringValue
    }.joined(separator: ".")
    return path.isEmpty ? "root" : path
}

private func logDecodingFailure(_ error: Error, file: String) {
    switch error {
    case let DecodingError.keyNotFound(key, context):
        widgetTimelineLogger.error(
            "Snapshot decode keyNotFound file=\(file, privacy: .public) key=\(key.stringValue, privacy: .public) path=\(codingPathDescription(context.codingPath), privacy: .public)"
        )
    case let DecodingError.typeMismatch(_, context):
        widgetTimelineLogger.error(
            "Snapshot decode typeMismatch file=\(file, privacy: .public) path=\(codingPathDescription(context.codingPath), privacy: .public)"
        )
    case let DecodingError.valueNotFound(_, context):
        widgetTimelineLogger.error(
            "Snapshot decode valueNotFound file=\(file, privacy: .public) path=\(codingPathDescription(context.codingPath), privacy: .public)"
        )
    case let DecodingError.dataCorrupted(context):
        widgetTimelineLogger.error(
            "Snapshot decode dataCorrupted file=\(file, privacy: .public) path=\(codingPathDescription(context.codingPath), privacy: .public)"
        )
    default:
        let nsError = error as NSError
        widgetTimelineLogger.error(
            "Snapshot decode failed file=\(file, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }
}

/// Display-only normalized window written by Codex Lens. Widget views never
/// inspect the unnormalized API response or depend on array order/labels.
struct LimitWindow: Decodable {
    let id: String
    let kind: String
    let durationSeconds: UInt64
    let remainingPercent: Double
    let resetAt: String?
    let isAvailable: Bool
    let usedPercent: Double?
    let sourceLabel: String?

    init(id: String, kind: String, durationSeconds: UInt64, remainingPercent: Double, resetAt: String?, isAvailable: Bool, usedPercent: Double? = nil, sourceLabel: String? = nil) {
        self.id = id
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.isAvailable = isAvailable
        self.usedPercent = usedPercent
        self.sourceLabel = sourceLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, durationSeconds, durationSecondsSnake = "duration_seconds"
        case remainingPercent, remainingPercentSnake = "remaining_percent"
        case usedPercent, usedPercentSnake = "used_percent"
        case resetAt, resetAtSnake = "reset_at"
        case isAvailable, isAvailableSnake = "is_available"
        case sourceLabel, sourceLabelSnake = "source_label"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = values.decodeFlexibleString(for: [.kind]) ?? "unknown"
        switch rawKind {
        case "weekly": kind = "weekly"
        case "rollingFiveHour", "rolling_five_hour", "fiveHour", "five_hour":
            kind = "rollingFiveHour"
        default: kind = "unknown"
        }
        id = values.decodeFlexibleString(for: [.id]) ?? "\(kind)-unknown"
        durationSeconds = values.decodeFlexibleUInt64(for: [.durationSeconds, .durationSecondsSnake]) ?? 0
        usedPercent = values.decodeFlexibleDouble(for: [.usedPercent, .usedPercentSnake])
        if let remaining = values.decodeFlexibleDouble(for: [.remainingPercent, .remainingPercentSnake]),
           remaining.isFinite {
            remainingPercent = remaining.clamped(to: 0 ... 100)
        } else if let usedPercent, usedPercent.isFinite {
            remainingPercent = (100 - usedPercent).clamped(to: 0 ... 100)
        } else {
            throw DecodingError.valueNotFound(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Limit window has neither a finite remainingPercent nor usedPercent"
                )
            )
        }
        resetAt = values.decodeFlexibleTimestamp(for: [.resetAt, .resetAtSnake])
        isAvailable = values.decodeFlexibleBool(for: [.isAvailable, .isAvailableSnake]) ?? true
        sourceLabel = values.decodeFlexibleString(for: [.sourceLabel, .sourceLabelSnake])
    }

    var roundedPercent: Int { Int(remainingPercent.clamped(to: 0 ... 100).rounded()) }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(for keys: [Key]) -> String? {
        for key in keys where contains(key) {
            if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        }
        return nil
    }

    func decodeFlexibleDouble(for keys: [Key]) -> Double? {
        for key in keys where contains(key) {
            if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
            if let text = try? decodeIfPresent(String.self, forKey: key),
               let value = Double(text), value.isFinite { return value }
        }
        return nil
    }

    func decodeFlexibleUInt64(for keys: [Key]) -> UInt64? {
        for key in keys where contains(key) {
            if let value = try? decodeIfPresent(UInt64.self, forKey: key) { return value }
            if let text = try? decodeIfPresent(String.self, forKey: key),
               let value = UInt64(text) { return value }
        }
        return nil
    }

    func decodeFlexibleBool(for keys: [Key]) -> Bool? {
        for key in keys where contains(key) {
            if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
            if let text = try? decodeIfPresent(String.self, forKey: key) {
                if text.lowercased() == "true" { return true }
                if text.lowercased() == "false" { return false }
            }
        }
        return nil
    }

    func decodeFlexibleTimestamp(for keys: [Key]) -> String? {
        for key in keys where contains(key) {
            if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
            if let seconds = try? decodeIfPresent(Double.self, forKey: key), seconds.isFinite {
                let unixSeconds = seconds > 10_000_000_000 ? seconds / 1_000 : seconds
                return SnapshotDateParser.canonicalString(fromUnixSeconds: unixSeconds)
            }
        }
        return nil
    }
}

enum SnapshotDateParser {
    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO8601Formatter = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date? {
        if let numeric = Double(value), numeric.isFinite {
            let seconds = numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            return Date(timeIntervalSince1970: seconds)
        }
        return fractionalISO8601Formatter.date(from: value)
            ?? standardISO8601Formatter.date(from: value)
    }

    static func canonicalString(fromUnixSeconds seconds: Double) -> String {
        standardISO8601Formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}

struct LegacyUsageWindow: Decodable {
    let remainingPercent: Double
    let resetsAt: String?
    let windowSeconds: UInt64
}

private struct LossyLimitWindowList: Decodable {
    let values: [LimitWindow]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [LimitWindow] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            let itemDecoder = try container.superDecoder()
            do {
                decoded.append(try LimitWindow(from: itemDecoder))
            } catch {
                logDecodingFailure(error, file: "limitWindows[\(index)]")
            }
        }
        values = decoded
    }
}

struct QuotaSnapshot: Decodable {
    let schemaVersion: Int
    let displayName: String
    let plan: String?
    let activeModel: String?
    let limitWindows: [LimitWindow]?
    // Read only for a short compatibility window with Codex Lens 0.1.x.
    let shortWindow: LegacyUsageWindow?
    let weeklyWindow: LegacyUsageWindow?
    let updatedAt: String
    let source: String
    let isStale: Bool
    let status: String
    let message: String?

    init(
        schemaVersion: Int = 1,
        displayName: String,
        plan: String?,
        activeModel: String?,
        limitWindows: [LimitWindow]?,
        shortWindow: LegacyUsageWindow?,
        weeklyWindow: LegacyUsageWindow?,
        updatedAt: String,
        source: String = "preview",
        isStale: Bool = false,
        status: String,
        message: String?
    ) {
        self.schemaVersion = schemaVersion
        self.displayName = displayName
        self.plan = plan
        self.activeModel = activeModel
        self.limitWindows = limitWindows
        self.shortWindow = shortWindow
        self.weeklyWindow = weeklyWindow
        self.updatedAt = updatedAt
        self.source = source
        self.isStale = isStale
        self.status = status
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, schemaVersionSnake = "schema_version"
        case displayName, displayNameSnake = "display_name"
        case plan
        case activeModel, activeModelSnake = "active_model"
        case limitWindows, limitWindowsSnake = "limit_windows"
        case shortWindow, shortWindowSnake = "short_window"
        case weeklyWindow, weeklyWindowSnake = "weekly_window"
        case updatedAt, updatedAtSnake = "updated_at"
        case source
        case isStale, isStaleSnake = "is_stale"
        case status, message
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Int(values.decodeFlexibleString(for: [.schemaVersion, .schemaVersionSnake]) ?? "")
            ?? Int(values.decodeFlexibleUInt64(for: [.schemaVersion, .schemaVersionSnake]) ?? 0)
        displayName = values.decodeFlexibleString(for: [.displayName, .displayNameSnake]) ?? "CODEX"
        plan = values.decodeFlexibleString(for: [.plan])
        activeModel = values.decodeFlexibleString(for: [.activeModel, .activeModelSnake])
        if let list = try values.decodeIfPresent(LossyLimitWindowList.self, forKey: .limitWindows) {
            limitWindows = list.values
        } else if let list = try values.decodeIfPresent(LossyLimitWindowList.self, forKey: .limitWindowsSnake) {
            limitWindows = list.values
        } else {
            limitWindows = nil
        }
        shortWindow = (try? values.decodeIfPresent(LegacyUsageWindow.self, forKey: .shortWindow))
            ?? (try? values.decodeIfPresent(LegacyUsageWindow.self, forKey: .shortWindowSnake))
        weeklyWindow = (try? values.decodeIfPresent(LegacyUsageWindow.self, forKey: .weeklyWindow))
            ?? (try? values.decodeIfPresent(LegacyUsageWindow.self, forKey: .weeklyWindowSnake))
        updatedAt = values.decodeFlexibleTimestamp(for: [.updatedAt, .updatedAtSnake]) ?? ""
        source = values.decodeFlexibleString(for: [.source]) ?? ""
        isStale = values.decodeFlexibleBool(for: [.isStale, .isStaleSnake]) ?? false
        status = values.decodeFlexibleString(for: [.status]) ?? "unavailable"
        message = values.decodeFlexibleString(for: [.message])
    }

    static let placeholder = QuotaSnapshot(
        displayName: "CODEX",
        plan: "PLUS",
        activeModel: "gpt-5.6-sol",
        limitWindows: [
            LimitWindow(id: "five-hour", kind: "rollingFiveHour", durationSeconds: 18_000, remainingPercent: 42, resetAt: PreviewFixtures.fiveHourReset, isAvailable: true),
            LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 11, resetAt: PreviewFixtures.weeklyReset, isAvailable: true),
        ],
        shortWindow: nil,
        weeklyWindow: nil,
        updatedAt: PreviewFixtures.updatedAt,
        status: "ok",
        message: nil
    )

    static let unavailable = QuotaSnapshot(
        displayName: "CODEX",
        plan: nil,
        activeModel: nil,
        limitWindows: [],
        shortWindow: nil,
        weeklyWindow: nil,
        updatedAt: ISO8601DateFormatter().string(from: .now),
        status: "unavailable",
        message: "等待 Codex Lens 同步数据"
    )

    private static func parseDate(_ value: String) -> Date? {
        SnapshotDateParser.parse(value)
    }

    var effectiveStatus: String {
        guard schemaVersion == 1 else { return "unavailable" }
        if isStale { return "stale" }
        guard status == "ok" else { return status }
        guard let updated = Self.parseDate(updatedAt) else { return "stale" }
        return Date().timeIntervalSince(updated) > 180 ? "stale" : "ok"
    }

    var currentModel: String? { activeModel }

    /// Legacy fields are converted only when a normalized list is absent. A
    /// fresh list therefore always controls layout, including window removal.
    var availableWindows: [LimitWindow] {
        let normalized = (limitWindows ?? []).filter(\.isAvailable)
        guard normalized.isEmpty else { return normalized }
        var legacy: [LimitWindow] = []
        if let shortWindow {
            legacy.append(LimitWindow(id: "legacy-five-hour", kind: "rollingFiveHour", durationSeconds: shortWindow.windowSeconds, remainingPercent: shortWindow.remainingPercent, resetAt: shortWindow.resetsAt, isAvailable: true))
        }
        if let weeklyWindow {
            legacy.append(LimitWindow(id: "legacy-weekly", kind: "weekly", durationSeconds: weeklyWindow.windowSeconds, remainingPercent: weeklyWindow.remainingPercent, resetAt: weeklyWindow.resetsAt, isAvailable: true))
        }
        return legacy
    }

    var fiveHourWindow: LimitWindow? {
        availableWindows.first { $0.kind == "rollingFiveHour" || $0.durationSeconds.isApproximately(18_000, tolerance: 600) }
    }

    var weeklyLimitWindow: LimitWindow? {
        availableWindows.first { $0.kind == "weekly" || $0.durationSeconds.isApproximately(604_800, tolerance: 3_600) }
    }
}

private extension UInt64 {
    func isApproximately(_ expected: UInt64, tolerance: UInt64) -> Bool {
        absDiff(expected) <= tolerance
    }

    func absDiff(_ other: UInt64) -> UInt64 { self >= other ? self - other : other - self }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}

enum QuotaSnapshotStore {
    private static let heartbeatFileName = "widget-timeline-heartbeat.txt"

    static func load() -> QuotaSnapshot {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        guard let appGroupIdentifier = CodexLensSharedContainer.appGroupIdentifier else {
            widgetTimelineLogger.error(
                "App Group read unavailable bundle=\(bundleIdentifier, privacy: .public) reason=missing-runtime-configuration"
            )
            return .unavailable
        }
        guard let containerURL = CodexLensSharedContainer.containerURL() else {
            widgetTimelineLogger.error(
                "App Group read unavailable bundle=\(bundleIdentifier, privacy: .public) resolvedAppGroupID=\(appGroupIdentifier, privacy: .public) containerURL=nil"
            )
            return .unavailable
        }
        let snapshotURL = containerURL.appendingPathComponent(CodexLensSharedContainer.snapshotFileName)
        let lastKnownGoodURL = containerURL.appendingPathComponent(CodexLensSharedContainer.lastKnownGoodFileName)
        logFileState(bundleIdentifier: bundleIdentifier, appGroupIdentifier: appGroupIdentifier, containerURL: containerURL, fileURL: snapshotURL)

        if let snapshot = decode(at: snapshotURL, source: "current") {
            logLoaded(snapshot, source: "current")
            return snapshot
        }
        if let cached = decode(at: lastKnownGoodURL, source: "last-known-good") {
            let stale = staleCopy(cached)
            logLoaded(stale, source: "last-known-good")
            return stale
        }
        widgetTimelineLogger.error("Snapshot load fallback reason=no-valid-current-or-last-known-good")
        return .unavailable
    }

    static func recordTimelineRequest(at date: Date) {
        guard let containerURL = CodexLensSharedContainer.containerURL() else {
            widgetTimelineLogger.error("Timeline heartbeat failed reason=container-unavailable")
            return
        }
        let heartbeatURL = containerURL.appendingPathComponent(heartbeatFileName)
        do {
            try Data(ISO8601DateFormatter().string(from: date).utf8)
                .write(to: heartbeatURL, options: .atomic)
            widgetTimelineLogger.info(
                "Timeline heartbeat wrote path=\(heartbeatURL.path, privacy: .public)"
            )
        } catch {
            let nsError = error as NSError
            widgetTimelineLogger.error(
                "Timeline heartbeat failed path=\(heartbeatURL.path, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
        }
    }

    static func decodeForDiagnostics(at url: URL) -> QuotaSnapshot? {
        decode(at: url, source: "diagnostic")
    }

    private static func decode(at url: URL, source: String) -> QuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            widgetTimelineLogger.error(
                "Snapshot read failed source=\(source, privacy: .public) reason=file-not-found path=\(url.path, privacy: .public)"
            )
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            let reason = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError
                ? "permission-denied" : "file-read-error"
            widgetTimelineLogger.error(
                "Snapshot read failed source=\(source, privacy: .public) reason=\(reason, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            return nil
        }
        guard !data.isEmpty else {
            widgetTimelineLogger.error("Snapshot read failed source=\(source, privacy: .public) reason=file-empty")
            return nil
        }
        guard String(data: data, encoding: .utf8) != nil else {
            widgetTimelineLogger.error("Snapshot read failed source=\(source, privacy: .public) reason=invalid-utf8")
            return nil
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            widgetTimelineLogger.error("Snapshot read failed source=\(source, privacy: .public) reason=invalid-json")
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                widgetTimelineLogger.error(
                    "Snapshot read failed source=\(source, privacy: .public) reason=schema-incompatible schema=\(snapshot.schemaVersion, privacy: .public)"
                )
                return nil
            }
            if !snapshot.updatedAt.isEmpty, SnapshotDateParser.parse(snapshot.updatedAt) == nil {
                widgetTimelineLogger.error("Snapshot date parse failed source=\(source, privacy: .public) field=updatedAt")
            }
            for window in snapshot.availableWindows where window.resetAt.map({ SnapshotDateParser.parse($0) == nil }) == true {
                widgetTimelineLogger.error(
                    "Snapshot date parse failed source=\(source, privacy: .public) field=limitWindows.resetAt window=\(window.id, privacy: .public)"
                )
            }
            return snapshot
        } catch {
            logDecodingFailure(error, file: url.lastPathComponent)
            return nil
        }
    }

    private static func logFileState(bundleIdentifier: String, appGroupIdentifier: String, containerURL: URL, fileURL: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let exists = attributes != nil
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        let modified = (attributes?[.modificationDate] as? Date)
            .map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        widgetTimelineLogger.info(
            "App Group read state bundle=\(bundleIdentifier, privacy: .public) resolvedAppGroupID=\(appGroupIdentifier, privacy: .public) container=\(containerURL.path, privacy: .public) snapshot=\(fileURL.path, privacy: .public) exists=\(exists, privacy: .public) size=\(size, privacy: .public) modified=\(modified, privacy: .public)"
        )
    }

    private static func logLoaded(_ snapshot: QuotaSnapshot, source: String) {
        widgetTimelineLogger.info(
            "Snapshot loaded source=\(source, privacy: .public) model=\(snapshot.activeModel ?? "nil", privacy: .public) windows=\(snapshot.availableWindows.count, privacy: .public) weekly=\(snapshot.weeklyLimitWindow != nil, privacy: .public) fiveHour=\(snapshot.fiveHourWindow != nil, privacy: .public) updatedAt=\(snapshot.updatedAt, privacy: .public) stale=\(snapshot.isStale, privacy: .public)"
        )
    }

    private static func staleCopy(_ snapshot: QuotaSnapshot) -> QuotaSnapshot {
        QuotaSnapshot(
            schemaVersion: snapshot.schemaVersion,
            displayName: snapshot.displayName,
            plan: snapshot.plan,
            activeModel: snapshot.activeModel,
            limitWindows: snapshot.limitWindows,
            shortWindow: snapshot.shortWindow,
            weeklyWindow: snapshot.weeklyWindow,
            updatedAt: snapshot.updatedAt,
            source: snapshot.source,
            isStale: true,
            status: snapshot.status,
            message: snapshot.message
        )
    }
}

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot
}

private struct QuotaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        widgetTimelineLogger.info(
            "WidgetKit snapshot requested preview=\(context.isPreview, privacy: .public)"
        )
        let snapshot = context.isPreview ? QuotaSnapshot.placeholder : QuotaSnapshotStore.load()
        completion(QuotaEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        widgetTimelineLogger.info("WidgetKit requested a new quota timeline preview=\(context.isPreview, privacy: .public)")
        let now = Date.now
        QuotaSnapshotStore.recordTimelineRequest(at: now)
        let entry = QuotaEntry(date: now, snapshot: QuotaSnapshotStore.load())
        widgetTimelineLogger.info(
            "Timeline entry ready model=\(entry.snapshot.activeModel ?? "nil", privacy: .public) windows=\(entry.snapshot.availableWindows.count, privacy: .public) status=\(entry.snapshot.effectiveStatus, privacy: .public)"
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

#if CODEX_LENS_WIDGET_EXTENSION
@main
struct CodexLensWidgetBundle: WidgetBundle {
    var body: some Widget { CodexLensWidget() }
}
#endif

struct CodexLensWidget: Widget {
    let kind = "CodexLensWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaTimelineProvider()) { entry in
            QuotaWidgetView(entry: entry).widgetURL(URL(string: "codexlens://open"))
        }
        .configurationDisplayName("Codex Lens")
        .description("View your Codex model, quota, and reset time directly on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry

    private var layoutBranch: String {
        let count = entry.snapshot.availableWindows.count
        switch family {
        case .systemMedium: return count > 1 ? "medium-dual" : "medium-weekly"
        case .systemSmall: return count > 1 ? "small-dual" : "small-weekly"
        default: return "small-fallback"
        }
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                MediumQuotaWidget(snapshot: entry.snapshot)
            } else {
                CompactQuotaWidget(snapshot: entry.snapshot)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: WidgetAvailableSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(WidgetAvailableSizeKey.self) { size in
            widgetTimelineLogger.info(
                "Widget layout family=\(widgetFamilyDescription(family), privacy: .public) available=\(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public) branch=\(layoutBranch, privacy: .public)"
            )
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }
}

private struct WidgetAvailableSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.17, blue: 0.25).opacity(0.88),
                    Color(red: 0.07, green: 0.12, blue: 0.19).opacity(0.90),
                    Color(red: 0.035, green: 0.07, blue: 0.12).opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct CompactQuotaWidget: View {
    let snapshot: QuotaSnapshot
    private var windows: [LimitWindow] {
        [snapshot.fiveHourWindow, snapshot.weeklyLimitWindow].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SmallWidgetHeader(snapshot: snapshot)
            ModelLine(model: snapshot.currentModel, compact: true)
            if windows.count > 1 {
                SmallDualLimits(windows: windows)
            } else if let window = windows.first {
                SmallWeeklyLimit(window: window)
            } else {
                UnavailableLimitView(snapshot: snapshot, showsUpdate: true).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactAccessibilityDescription(snapshot, windows.first))
    }
}

struct MediumQuotaWidget: View {
    let snapshot: QuotaSnapshot
    private var windows: [LimitWindow] { [snapshot.fiveHourWindow, snapshot.weeklyLimitWindow].compactMap { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(snapshot: snapshot)
            if windows.isEmpty {
                UnavailableLimitView(snapshot: snapshot, showsUpdate: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.count == 1, let window = windows.first {
                MediumWeeklyLimit(snapshot: snapshot, window: window)
            } else {
                MediumDualLimits(snapshot: snapshot, windows: windows)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mediumAccessibilityDescription(snapshot, windows))
    }
}

private struct SmallWeeklyLimit: View {
    let window: LimitWindow

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            QuotaRing(window: window, size: 76)
                .layoutPriority(1)
            Text(resetDescription(window.resetAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SmallDualLimits: View {
    let windows: [LimitWindow]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(windows.prefix(2), id: \.id) { window in
                VStack(spacing: 4) {
                    QuotaRing(window: window, size: 55)
                    Text(shortResetDescription(window.resetAt))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Candidate A: the quota remains the single visual anchor while the right
/// column uses typography—not another card—to create a native macOS hierarchy.
private struct MediumWeeklyLimit: View {
    let snapshot: QuotaSnapshot
    let window: LimitWindow

    var body: some View {
        HStack(spacing: 17) {
            VStack(spacing: 5) {
                QuotaRing(window: window, size: 92)
                Text("剩余额度")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }
            .layoutPriority(1)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                ModelLine(model: snapshot.currentModel, compact: false)
                Spacer(minLength: 0)
                Text("周限额重置")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                Text(resetDescription(window.resetAt))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(resetMomentDescription(window.resetAt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Label(updatedDescription(snapshot.updatedAt), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediumDualLimits: View {
    let snapshot: QuotaSnapshot
    let windows: [LimitWindow]

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 14) {
                ForEach(windows.prefix(2), id: \.id) { window in
                    HStack(spacing: 8) {
                        QuotaRing(window: window, size: 70)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(windowCaption(window))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.56))
                            Text(resetDescription(window.resetAt))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(2)
                                .minimumScaleFactor(0.86)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                ModelLine(model: snapshot.currentModel, compact: true)
                Spacer(minLength: 4)
                Text(updatedDescription(snapshot.updatedAt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModelLine: View {
    let model: String?
    let compact: Bool

    var body: some View {
        Label(model ?? "模型待识别", systemImage: "cpu")
            .font(.system(size: compact ? 9 : 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(compact ? 0.58 : 0.78))
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.86)
    }
}

private struct SmallWidgetHeader: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "viewfinder.circle.fill")
            Text(snapshot.displayName)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            if let plan = snapshot.plan { AccountBadge(text: plan) }
            Spacer(minLength: 2)
            StatusDot(status: snapshot.effectiveStatus)
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.82))
        .accessibilityLabel(snapshot.effectiveStatus == "ok" ? "已同步" : "待刷新")
    }
}

private struct WidgetHeader: View {
    let snapshot: QuotaSnapshot
    var body: some View {
        HStack(spacing: 6) {
            Label(snapshot.displayName, systemImage: "viewfinder.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
            if let plan = snapshot.plan { AccountBadge(text: plan) }
            Spacer(minLength: 0)
            StatusDot(status: snapshot.effectiveStatus)
            Text(snapshot.effectiveStatus == "ok" ? "已同步" : "待刷新")
                .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.60))
        }
    }
}

private struct UnavailableLimitView: View {
    let snapshot: QuotaSnapshot
    let showsUpdate: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash").font(.title3).foregroundStyle(.white.opacity(0.58))
            Text(snapshot.message ?? "暂时无法读取额度")
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center).lineLimit(2)
            if showsUpdate {
                Text(updatedDescription(snapshot.updatedAt))
                    .font(.caption2).foregroundStyle(.white.opacity(0.50))
            }
        }
    }
}

private struct AccountBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78)).lineLimit(1).padding(.horizontal, 5).padding(.vertical, 2)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}

private struct QuotaRing: View {
    let window: LimitWindow
    let size: CGFloat
    private var color: Color {
        switch window.roundedPercent {
        case 0 ... 19: .red
        case 20 ... 49: .orange
        default: .green
        }
    }
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 8)
            Circle().trim(from: 0, to: max(0.02, Double(window.roundedPercent) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 4)
            VStack(spacing: -1) {
                Text("\(window.roundedPercent)%").font(.system(size: size * 0.29, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(windowCaption(window)).font(.system(size: max(8, size * 0.14), weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62)).lineLimit(1).minimumScaleFactor(0.72)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct StatusDot: View {
    let status: String
    private var color: Color { status == "ok" ? .green : (status == "stale" ? .yellow : .red) }
    var body: some View { Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.75), radius: 4) }
}

private func windowCaption(_ window: LimitWindow) -> String {
    window.kind == "weekly" || window.durationSeconds.isApproximately(604_800, tolerance: 3_600) ? "本周" : "5 小时"
}

private func resetDescription(_ value: String?) -> String {
    guard let value, let date = parseISO8601(value) else { return "重置时间待定" }
    let seconds = max(0, Int(date.timeIntervalSinceNow.rounded()))
    if seconds < 60 { return "即将重置" }
    if seconds < 86_400 { return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分后重置" }
    return "\(seconds / 86_400)天\((seconds % 86_400) / 3_600)小时后重置"
}

private func shortResetDescription(_ value: String?) -> String {
    guard let value, let date = parseISO8601(value) else { return "时间待定" }
    let seconds = max(0, Int(date.timeIntervalSinceNow.rounded()))
    if seconds < 3_600 { return "\(max(1, seconds / 60)) 分" }
    if seconds < 86_400 { return "\(seconds / 3_600) 时 \((seconds % 3_600) / 60) 分" }
    return "\(seconds / 86_400) 天 \((seconds % 86_400) / 3_600) 时"
}

private func resetMomentDescription(_ value: String?) -> String {
    guard let value, let date = parseISO8601(value) else { return "具体时间待定" }
    return date.formatted(
        Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: "zh_CN"))
    )
}

private func updatedDescription(_ value: String) -> String {
    guard let date = parseISO8601(value) else { return "更新时间未知" }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    return seconds < 60 ? "刚刚更新" : "\(min(seconds / 60, 999)) 分钟前"
}

private func parseISO8601(_ value: String) -> Date? {
    SnapshotDateParser.parse(value)
}

private func widgetFamilyDescription(_ family: WidgetFamily) -> String {
    switch family {
    case .systemSmall: "systemSmall"
    case .systemMedium: "systemMedium"
    case .systemLarge: "systemLarge"
    case .systemExtraLarge: "systemExtraLarge"
    default: "other"
    }
}

private func compactAccessibilityDescription(_ snapshot: QuotaSnapshot, _ window: LimitWindow?) -> String {
    "当前模型 \(snapshot.currentModel ?? "未知")；\(window.map { "\(windowCaption($0))剩余 \($0.roundedPercent)%；\(resetDescription($0.resetAt))" } ?? "额度暂时不可用")"
}

private func mediumAccessibilityDescription(_ snapshot: QuotaSnapshot, _ windows: [LimitWindow]) -> String {
    "当前模型 \(snapshot.currentModel ?? "未知")；" + windows.map { "\(windowCaption($0))剩余 \($0.roundedPercent)%；\(resetDescription($0.resetAt))" }.joined(separator: "；")
}

enum PreviewFixtures {
    static let referenceDate = Date.now
    static let updatedAt = ISO8601DateFormatter().string(from: referenceDate)
    static let fiveHourReset = ISO8601DateFormatter().string(from: referenceDate.addingTimeInterval((1 * 3_600) + (18 * 60)))
    static let weeklyReset = ISO8601DateFormatter().string(from: referenceDate.addingTimeInterval((4 * 86_400) + (4 * 3_600)))

    static let weeklyOnly = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 11, resetAt: weeklyReset, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let fiveHourAndWeekly = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 11, resetAt: weeklyReset, isAvailable: true), LimitWindow(id: "five-hour", kind: "rollingFiveHour", durationSeconds: 18_000, remainingPercent: 42, resetAt: fiveHourReset, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let fiveHourOnly = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "five-hour", kind: "rollingFiveHour", durationSeconds: 18_000, remainingPercent: 42, resetAt: fiveHourReset, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let noLimits = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "unavailable", message: "暂时无法读取额度")
    static let longModelName = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol extended reasoning preview", limitWindows: weeklyOnly.limitWindows, shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let zeroPercent = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 0, resetAt: weeklyReset, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let fullPercent = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 100, resetAt: weeklyReset, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
    static let missingReset = QuotaSnapshot(displayName: "CODEX", plan: "PLUS", activeModel: "gpt-5.6-sol", limitWindows: [LimitWindow(id: "weekly", kind: "weekly", durationSeconds: 604_800, remainingPercent: 11, resetAt: nil, isAvailable: true)], shortWindow: nil, weeklyWindow: nil, updatedAt: updatedAt, status: "ok", message: nil)
}

#Preview("Small · Weekly", as: .systemSmall) {
    CodexLensWidget()
} timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.weeklyOnly)
}

#Preview("Small · Dual", as: .systemSmall) {
    CodexLensWidget()
} timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.fiveHourAndWeekly)
}

#Preview("Medium · Weekly", as: .systemMedium) {
    CodexLensWidget()
} timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.weeklyOnly)
}

#Preview("Medium · Dual", as: .systemMedium) {
    CodexLensWidget()
} timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.fiveHourAndWeekly)
}

#Preview("Validation · 0%", as: .systemSmall) { CodexLensWidget() } timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.zeroPercent)
}
#Preview("Validation · 100%", as: .systemSmall) { CodexLensWidget() } timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.fullPercent)
}
#Preview("Validation · Long model", as: .systemMedium) { CodexLensWidget() } timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.longModelName)
}
#Preview("Validation · No reset", as: .systemMedium) { CodexLensWidget() } timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.missingReset)
}
#Preview("Validation · No limits", as: .systemMedium) { CodexLensWidget() } timeline: {
    QuotaEntry(date: .now, snapshot: PreviewFixtures.noLimits)
}

import Foundation
import OSLog

// The final identifier is injected into each product's Info.plist from
// CodexLensAppGroup.xcconfig. The Tauri packaging script injects the same
// expanded value before it signs the manually packaged host application.
enum CodexLensSharedContainer {
    static let appGroupInfoKey = "CodexLensAppGroupIdentifier"
    // Legacy migration source only. Production reads and writes never use it.
    static let legacyAppGroupIdentifier = "group.dev.codexlens.shared"
    static let snapshotFileName = "widget-snapshot.json"
    static let lastKnownGoodFileName = "widget-snapshot.last-known-good.json"

    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: appGroupInfoKey
        ) as? String else { return nil }
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !identifier.contains("$(") else { return nil }
        return identifier
    }

    static func containerURL() -> URL? {
        guard let appGroupIdentifier else { return nil }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    static func snapshotURL(lastKnownGood: Bool = false) -> URL? {
        containerURL()?
            .appendingPathComponent(lastKnownGood ? lastKnownGoodFileName : snapshotFileName)
    }

    static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    static func containsValidJSON(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else { return false }
        return true
    }

    static func migrateLegacySnapshots(from legacyContainer: URL, to newContainer: URL) throws -> Int {
        let names = [snapshotFileName, lastKnownGoodFileName]
        let newContainerHasValidSnapshot = names.contains {
            containsValidJSON(at: newContainer.appendingPathComponent($0))
        }
        guard !newContainerHasValidSnapshot else { return 0 }

        var migrated = 0
        for name in names {
            let source = legacyContainer.appendingPathComponent(name)
            guard containsValidJSON(at: source), let data = try? Data(contentsOf: source) else {
                continue
            }
            try writeAtomically(data, to: newContainer.appendingPathComponent(name))
            migrated += 1
        }
        return migrated
    }

    static func migrateLegacySnapshotsIfNeeded(to newContainer: URL) {
        let fileManager = FileManager.default
        let fallbackLegacyURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(legacyAppGroupIdentifier, isDirectory: true)
        let legacyContainer = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: legacyAppGroupIdentifier
        ) ?? fallbackLegacyURL

        do {
            let migrated = try migrateLegacySnapshots(from: legacyContainer, to: newContainer)
            sharedSnapshotLogger.info(
                "Legacy snapshot migration completed source=legacy-app-group migrated=\(migrated, privacy: .public) oldDataPreserved=true"
            )
        } catch {
            let nsError = error as NSError
            sharedSnapshotLogger.error(
                "Legacy snapshot migration skipped reason=read-or-write-failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) oldDataPreserved=true"
            )
        }
    }
}

private let sharedSnapshotLogger = Logger(subsystem: "dev.codexlens.desktop", category: "app-group")

/// Return codes are intentionally coarse: no filesystem path or account data
/// is logged when a developer has not configured the entitlement.
@_cdecl("codex_lens_write_widget_snapshot")
public func codexLensWriteWidgetSnapshot(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> Int32 {
    guard let bytes, length > 0 else { return 2 }
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    guard let appGroupIdentifier = CodexLensSharedContainer.appGroupIdentifier else {
        sharedSnapshotLogger.error(
            "App Group configuration unavailable bundle=\(bundleIdentifier, privacy: .public) infoKey=\(CodexLensSharedContainer.appGroupInfoKey, privacy: .public)"
        )
        return 4
    }
    guard let containerURL = CodexLensSharedContainer.containerURL() else {
        sharedSnapshotLogger.error(
            "App Group container unavailable bundle=\(bundleIdentifier, privacy: .public) resolvedAppGroupID=\(appGroupIdentifier, privacy: .public) containerURL=nil"
        )
        return 1
    }
    let snapshotURL = containerURL.appendingPathComponent(CodexLensSharedContainer.snapshotFileName)
    let backupURL = containerURL.appendingPathComponent(CodexLensSharedContainer.lastKnownGoodFileName)
    sharedSnapshotLogger.info(
        "App Group publish begin bundle=\(bundleIdentifier, privacy: .public) resolvedAppGroupID=\(appGroupIdentifier, privacy: .public) container=\(containerURL.path, privacy: .public) snapshot=\(snapshotURL.path, privacy: .public) bytes=\(length, privacy: .public)"
    )

    do {
        let data = Data(bytes: bytes, count: length)
        CodexLensSharedContainer.migrateLegacySnapshotsIfNeeded(to: containerURL)
        try CodexLensSharedContainer.writeAtomically(data, to: snapshotURL)
        try CodexLensSharedContainer.writeAtomically(data, to: backupURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? -1
        let modificationDate = (attributes[.modificationDate] as? Date)
            .map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        sharedSnapshotLogger.info(
            "App Group publish success bundle=\(bundleIdentifier, privacy: .public) snapshot=\(snapshotURL.path, privacy: .public) exists=true size=\(fileSize, privacy: .public) modified=\(modificationDate, privacy: .public)"
        )
        return 0
    } catch {
        let cocoaError = error as NSError
        sharedSnapshotLogger.error(
            "App Group snapshot write failed bundle=\(bundleIdentifier, privacy: .public) snapshot=\(snapshotURL.path, privacy: .public) domain=\(cocoaError.domain, privacy: .public) code=\(cocoaError.code, privacy: .public)"
        )
        return 3
    }
}

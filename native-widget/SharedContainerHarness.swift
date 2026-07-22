import Foundation

@main
struct SharedContainerHarness {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-lens-shared-container-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        let current = root.appendingPathComponent("current", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let valid = Data("{\"schemaVersion\":1,\"activeModel\":\"fixture\"}".utf8)
        let legacySnapshot = legacy.appendingPathComponent(CodexLensSharedContainer.snapshotFileName)
        let legacyBackup = legacy.appendingPathComponent(CodexLensSharedContainer.lastKnownGoodFileName)
        try valid.write(to: legacySnapshot)
        try valid.write(to: legacyBackup)

        let migrated = try CodexLensSharedContainer.migrateLegacySnapshots(from: legacy, to: current)
        guard migrated == 2 else { throw HarnessError.failed("migration-count") }
        guard CodexLensSharedContainer.containsValidJSON(
            at: current.appendingPathComponent(CodexLensSharedContainer.snapshotFileName)
        ) else { throw HarnessError.failed("migration-json") }
        guard FileManager.default.fileExists(atPath: legacySnapshot.path) else {
            throw HarnessError.failed("legacy-preservation")
        }

        let replacement = Data("{\"schemaVersion\":1,\"activeModel\":\"replacement\"}".utf8)
        let atomicTarget = current.appendingPathComponent("atomic.json")
        try CodexLensSharedContainer.writeAtomically(valid, to: atomicTarget)
        try CodexLensSharedContainer.writeAtomically(replacement, to: atomicTarget)
        guard try Data(contentsOf: atomicTarget) == replacement else {
            throw HarnessError.failed("atomic-replacement")
        }

        print("migration=success migrated=2 legacyPreserved=true")
        print("atomicWrite=success")
    }
}

private enum HarnessError: Error {
    case failed(String)
}

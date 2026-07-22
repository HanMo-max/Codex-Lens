import Foundation

@main
struct DecoderHarness {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: decoder-harness <snapshot.json>\n".utf8))
            exit(64)
        }

        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let snapshot = QuotaSnapshotStore.decodeForDiagnostics(at: url) else {
            print("decode=failed")
            exit(1)
        }

        print("decode=success")
        print("schemaVersion=\(snapshot.schemaVersion)")
        print("activeModel=\(snapshot.activeModel ?? "nil")")
        print("validLimitWindows=\(snapshot.availableWindows.count)")
        print("weekly=\(snapshot.weeklyLimitWindow != nil)")
        print("fiveHour=\(snapshot.fiveHourWindow != nil)")
        print("updatedAt=\(snapshot.updatedAt)")
        print("isStale=\(snapshot.isStale)")
    }
}

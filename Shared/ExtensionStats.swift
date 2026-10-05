import Foundation

/// Diagnostic snapshot written by the broadcast extension into the App Group
/// so the host app can surface why chunks may be missing.
struct ExtensionStats: Codable, Equatable {
    var micBuffers = 0
    var systemBuffers = 0
    var videoBuffers = 0
    var resampleFailures = 0
    var framesEmitted = 0
    var chunksWritten: UInt64 = 0
    var lastError = ""

    var summary: String {
        "mic=\(micBuffers) sys=\(systemBuffers) vid=\(videoBuffers) fail=\(resampleFailures) chunks=\(chunksWritten)"
    }

    func write(to directory: URL) {
        let url = directory.appendingPathComponent("_stats.json")
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read(from directory: URL) -> ExtensionStats? {
        let url = directory.appendingPathComponent("_stats.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtensionStats.self, from: data)
    }
}

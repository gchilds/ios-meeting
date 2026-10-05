import Foundation

enum AppGroup {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AudioConstants.appGroupID)
    }

    static var chunksDirectoryURL: URL? {
        guard let root = containerURL else { return nil }
        return root.appendingPathComponent(AudioConstants.chunksDirectoryName, isDirectory: true)
    }

    /// Creates the chunks directory if needed. Returns nil when the App Group is unavailable.
    @discardableResult
    static func ensureChunksDirectory() -> URL? {
        guard let dir = chunksDirectoryURL else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func clearChunks() {
        guard let dir = chunksDirectoryURL else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

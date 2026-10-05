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

    /// Removes only PCM chunk files — keeps the directory and any live sentinel.
    static func clearChunks() {
        guard let dir = ensureChunksDirectory() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == AudioConstants.chunkFilenameExtension {
            try? fm.removeItem(at: url)
        }
    }
}

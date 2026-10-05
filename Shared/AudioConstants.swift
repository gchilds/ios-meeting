import Foundation

/// Shared between the broadcast extension and the host app.
enum AudioConstants {
    static let sampleRate: Double = 16_000
    static let channels = 2          // stereo: L = mic, R = system
    static let bitsPerSample = 16
    static let framesPerChunk = 512  // 32 ms @ 16 kHz
    static let bytesPerFrame = channels * (bitsPerSample / 8) // 4
    static let bytesPerChunk = framesPerChunk * bytesPerFrame // 2048

    /// App Group used to share the chunk directory.
    static let appGroupID = "group.com.granola.ios-meeting"

    /// Relative path inside the App Group container.
    static let chunksDirectoryName = "audio_chunks"

    /// Filename prefix + zero-padded sequence, e.g. `chunk_00000042.pcm`
    static let chunkFilenamePrefix = "chunk_"
    static let chunkFilenameExtension = "pcm"

    /// Present while the extension is capturing; removed after the final chunk is written.
    static let liveSentinelName = "_broadcast_live"
    /// Written by the app to ask the extension to finish the broadcast.
    static let stopRequestName = "_stop_requested"

    static func chunkURL(in directory: URL, sequence: UInt64) -> URL {
        let name = String(format: "%@%08llu.%@", chunkFilenamePrefix, sequence, chunkFilenameExtension)
        return directory.appendingPathComponent(name)
    }

    static func parseSequence(from filename: String) -> UInt64? {
        guard filename.hasPrefix(chunkFilenamePrefix),
              filename.hasSuffix(".\(chunkFilenameExtension)") else { return nil }
        let start = chunkFilenamePrefix.count
        let end = filename.count - chunkFilenameExtension.count - 1
        guard start < end else { return nil }
        let digits = filename[filename.index(filename.startIndex, offsetBy: start)
                              ..< filename.index(filename.startIndex, offsetBy: end)]
        return UInt64(digits)
    }
}

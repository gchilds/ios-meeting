import Foundation
import Combine

/// Watches the App Group chunks directory for new 512-frame PCM files
/// and publishes their raw Data in sequence order.
final class ChunkWatcher: ObservableObject {
    @Published private(set) var isWatching = false
    @Published private(set) var chunksDelivered: UInt64 = 0

    private var source: DispatchSourceFileSystemObject?
    private var directory: URL?
    private var nextSequence: UInt64 = 0
    private var onChunk: ((Data) -> Void)?
    private let ioQueue = DispatchQueue(label: "com.granola.ios-meeting.chunk-watcher")

    func start(onChunk: @escaping (Data) -> Void) {
        stop()
        guard let dir = AppGroup.ensureChunksDirectory() else {
            NSLog("[ChunkWatcher] App Group unavailable")
            return
        }
        directory = dir
        self.onChunk = onChunk
        nextSequence = 0

        DispatchQueue.main.async { [weak self] in
            self?.chunksDelivered = 0
            self?.isWatching = true
        }

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[ChunkWatcher] failed to open %@", dir.path)
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: ioQueue
        )
        src.setEventHandler { [weak self] in
            self?.drainAvailableChunks()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src

        ioQueue.async { [weak self] in self?.drainAvailableChunks() }
        NSLog("[ChunkWatcher] watching %@", dir.path)
    }

    func stop() {
        source?.cancel()
        source = nil
        onChunk = nil
        directory = nil
        DispatchQueue.main.async { [weak self] in
            self?.isWatching = false
        }
    }

    private func drainAvailableChunks() {
        guard let directory, let onChunk else { return }
        let fm = FileManager.default

        while true {
            let url = AudioConstants.chunkURL(in: directory, sequence: nextSequence)
            guard fm.fileExists(atPath: url.path) else { break }

            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber,
                  size.intValue >= AudioConstants.bytesPerChunk else {
                break
            }

            do {
                let data = try Data(contentsOf: url)
                nextSequence += 1
                DispatchQueue.main.async { [weak self] in
                    self?.chunksDelivered += 1
                }
                onChunk(data)
                try? fm.removeItem(at: url)
            } catch {
                NSLog("[ChunkWatcher] read failed %@: %@", url.lastPathComponent, error.localizedDescription)
                break
            }
        }
    }
}

import Foundation
import Combine

/// Watches the App Group chunks directory for new 512-frame PCM files
/// and publishes their raw Data in sequence order.
///
/// Uses polling — kqueue/FSEvents often do not cross App Group processes.
final class ChunkWatcher: ObservableObject {
    @Published private(set) var isWatching = false
    @Published private(set) var chunksDelivered: UInt64 = 0
    @Published private(set) var broadcastLive = false
    @Published private(set) var extensionStats: ExtensionStats?

    private var directory: URL?
    private var nextSequence: UInt64 = 0
    private var onChunk: ((Data) -> Void)?
    private var pollTimer: DispatchSourceTimer?
    private let ioQueue = DispatchQueue(label: "com.granola.iosmeeting.chunk-watcher")

    func start(onChunk: @escaping (Data) -> Void) {
        stop()
        guard let dir = AppGroup.ensureChunksDirectory() else {
            NSLog("[ChunkWatcher] App Group unavailable — enable group.com.granola.ios-meeting on both targets")
            return
        }
        directory = dir
        self.onChunk = onChunk
        nextSequence = 0

        // Catch up to whatever sequence already exists on disk.
        nextSequence = highestExistingSequence(in: dir).map { $0 + 1 } ?? 0

        DispatchQueue.main.async { [weak self] in
            self?.chunksDelivered = 0
            self?.isWatching = true
        }

        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        pollTimer = timer

        NSLog("[ChunkWatcher] polling %@ from seq %llu", dir.path, nextSequence)
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        onChunk = nil
        directory = nil
        DispatchQueue.main.async { [weak self] in
            self?.isWatching = false
            self?.broadcastLive = false
        }
    }

    private func tick() {
        guard let directory else { return }

        let live = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("_broadcast_live").path
        )
        let stats = ExtensionStats.read(from: directory)

        DispatchQueue.main.async { [weak self] in
            self?.broadcastLive = live
            self?.extensionStats = stats
        }

        drainAvailableChunks()
    }

    private func highestExistingSequence(in directory: URL) -> UInt64? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.compactMap { AudioConstants.parseSequence(from: $0.lastPathComponent) }.max()
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

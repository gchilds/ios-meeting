import Foundation

/// Watches the App Group chunks directory for broadcast start/stop and new
/// 512-frame PCM files. Events are delivered in order on a private queue:
/// `.started`, then every `.chunk`, then `.ended` once the extension has
/// removed its live sentinel (which it does only after writing its final chunk).
///
/// Uses polling — kqueue/FSEvents often do not cross App Group processes.
final class ChunkWatcher {
    enum Event {
        case started
        case chunk(Data)
        case ended
    }

    private var directory: URL?
    private var nextSequence: UInt64 = 0
    private var wasLive = false
    private var handler: ((Event) -> Void)?
    private var pollTimer: DispatchSourceTimer?
    private let ioQueue = DispatchQueue(label: "com.granola.iosmeeting.chunk-watcher")

    func start(handler: @escaping (Event) -> Void) {
        guard let dir = AppGroup.ensureChunksDirectory() else {
            NSLog("[ChunkWatcher] App Group unavailable — enable group.com.granola.ios-meeting on both targets")
            return
        }
        ioQueue.async { [self] in
            directory = dir
            self.handler = handler
            wasLive = false
            if !isLive(in: dir) {
                AppGroup.clearChunks()
            }

            let timer = DispatchSource.makeTimerSource(queue: ioQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            pollTimer = timer
        }
    }

    /// Asks the extension to finish; it flushes its last chunk and removes the sentinel.
    func requestStop() {
        ioQueue.async { [self] in
            guard let directory else { return }
            let url = directory.appendingPathComponent(AudioConstants.stopRequestName)
            try? Data().write(to: url)
        }
    }

    /// Ends the session even if the extension never responded (e.g. it was killed
    /// and left a stale sentinel). Remaining chunks are still drained.
    func forceEnd() {
        ioQueue.async { [self] in
            guard let directory else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: directory.appendingPathComponent(AudioConstants.liveSentinelName))
            try? fm.removeItem(at: directory.appendingPathComponent(AudioConstants.stopRequestName))
        }
    }

    private func isLive(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(AudioConstants.liveSentinelName).path)
    }

    private func tick() {
        guard let directory, let handler else { return }

        // Read liveness before draining: chunks written before the sentinel
        // disappeared are guaranteed to be picked up by this drain.
        let live = isLive(in: directory)

        if live && !wasLive {
            wasLive = true
            nextSequence = lowestExistingSequence(in: directory, atLeast: 0) ?? 0
            handler(.started)
        }

        guard wasLive else { return }
        drainAvailableChunks(in: directory, handler: handler)

        if !live {
            wasLive = false
            AppGroup.clearChunks()
            handler(.ended)
        }
    }

    private func drainAvailableChunks(in directory: URL, handler: (Event) -> Void) {
        let fm = FileManager.default

        // Skip gaps (e.g. the extension was already past seq 0 when we noticed).
        if !fm.fileExists(atPath: AudioConstants.chunkURL(in: directory, sequence: nextSequence).path),
           let lowest = lowestExistingSequence(in: directory, atLeast: nextSequence) {
            nextSequence = lowest
        }

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
                handler(.chunk(data))
                try? fm.removeItem(at: url)
            } catch {
                NSLog("[ChunkWatcher] read failed %@: %@", url.lastPathComponent, error.localizedDescription)
                break
            }
        }
    }

    private func lowestExistingSequence(in directory: URL, atLeast minimum: UInt64) -> UInt64? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files
            .compactMap { AudioConstants.parseSequence(from: $0.lastPathComponent) }
            .filter { $0 >= minimum }
            .min()
    }
}

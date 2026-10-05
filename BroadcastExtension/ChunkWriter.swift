import Foundation

/// Accumulates interleaved stereo Int16 frames and writes them to disk
/// as fixed-size 512-frame PCM chunks inside the App Group container.
final class ChunkWriter {
    private var pending: [Int16] = []
    private var sequence: UInt64 = 0
    private let framesPerChunk: Int
    private let directory: URL
    private let lock = NSLock()

    init(directory: URL, framesPerChunk: Int = AudioConstants.framesPerChunk) {
        self.directory = directory
        self.framesPerChunk = framesPerChunk
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Appends interleaved stereo samples (L/R/L/R…) and flushes full chunks.
    func append(interleavedStereo samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        pending.append(contentsOf: samples)
        let samplesPerChunk = framesPerChunk * AudioConstants.channels

        while pending.count >= samplesPerChunk {
            let chunk = Array(pending.prefix(samplesPerChunk))
            pending.removeFirst(samplesPerChunk)
            writeChunk(chunk)
        }
    }

    /// Flushes any remainder as a zero-padded final chunk.
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return }
        let samplesPerChunk = framesPerChunk * AudioConstants.channels
        var chunk = pending
        pending.removeAll(keepingCapacity: true)
        if chunk.count < samplesPerChunk {
            chunk.append(contentsOf: repeatElement(Int16(0), count: samplesPerChunk - chunk.count))
        }
        writeChunk(chunk)
    }

    func reset() {
        lock.lock()
        pending.removeAll(keepingCapacity: true)
        sequence = 0
        lock.unlock()
    }

    /// Current write sequence (number of chunks already written).
    var sequenceValue: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }

    private func writeChunk(_ samples: [Int16]) {
        let url = AudioConstants.chunkURL(in: directory, sequence: sequence)
        sequence += 1

        samples.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            // Atomic-ish write: temp then replace.
            let tmp = url.appendingPathExtension("tmp")
            do {
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
            } catch {
                NSLog("[ChunkWriter] failed to write %@: %@", url.lastPathComponent, error.localizedDescription)
            }
        }
    }
}

import Foundation

/// Buffers independently-arriving mic and system-audio streams, aligns them
/// by consuming equal frame counts, and emits interleaved stereo Int16 frames
/// (left = mic, right = system).
final class StereoAligner {
    private var micQueue: [Int16] = []
    private var systemQueue: [Int16] = []
    private let lock = NSLock()

    func appendMic(_ samples: [Int16]) {
        lock.lock()
        micQueue.append(contentsOf: samples)
        lock.unlock()
    }

    func appendSystem(_ samples: [Int16]) {
        lock.lock()
        systemQueue.append(contentsOf: samples)
        lock.unlock()
    }

    /// Pulls as many aligned stereo frames as possible.
    /// When one channel leads by more than `maxSkewFrames`, the lagging
    /// channel is zero-padded so capture never stalls forever.
    func pullAlignedFrames(maxSkewFrames: Int = 1_600) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        if maxSkewFrames > 0 {
            if micQueue.count > systemQueue.count + maxSkewFrames {
                systemQueue.append(contentsOf: repeatElement(0, count: micQueue.count - systemQueue.count))
            } else if systemQueue.count > micQueue.count + maxSkewFrames {
                micQueue.append(contentsOf: repeatElement(0, count: systemQueue.count - micQueue.count))
            }
        }

        let available = min(micQueue.count, systemQueue.count)
        guard available > 0 else { return [] }

        var stereo = [Int16](repeating: 0, count: available * 2)
        for i in 0..<available {
            stereo[i * 2] = micQueue[i]        // left  = mic
            stereo[i * 2 + 1] = systemQueue[i] // right = system
        }
        micQueue.removeFirst(available)
        systemQueue.removeFirst(available)
        return stereo
    }

    /// Force-pad whichever side is shorter and drain everything.
    func drainWithSilencePadding() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        let target = max(micQueue.count, systemQueue.count)
        if micQueue.count < target {
            micQueue.append(contentsOf: repeatElement(0, count: target - micQueue.count))
        }
        if systemQueue.count < target {
            systemQueue.append(contentsOf: repeatElement(0, count: target - systemQueue.count))
        }
        guard target > 0 else { return [] }

        var stereo = [Int16](repeating: 0, count: target * 2)
        for i in 0..<target {
            stereo[i * 2] = micQueue[i]
            stereo[i * 2 + 1] = systemQueue[i]
        }
        micQueue.removeAll(keepingCapacity: true)
        systemQueue.removeAll(keepingCapacity: true)
        return stereo
    }

    func reset() {
        lock.lock()
        micQueue.removeAll(keepingCapacity: true)
        systemQueue.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

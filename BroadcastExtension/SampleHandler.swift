import ReplayKit
import AVFoundation
import CoreMedia

/// Broadcast Upload Extension entry point.
/// Discards video, resamples mic + system audio to 16 kHz Int16,
/// aligns into stereo (L=mic, R=system), and writes 512-frame PCM chunks.
class SampleHandler: RPBroadcastSampleHandler {
    private let micResampler = AudioResampler()
    private let systemResampler = AudioResampler()
    private let aligner = StereoAligner()
    private var chunkWriter: ChunkWriter?
    private var stats = ExtensionStats()
    private var directory: URL?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let dir = AppGroup.ensureChunksDirectory() else {
            finishBroadcastWithError(NSError(
                domain: "MeetingBroadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable. Check App Groups entitlement."]
            ))
            return
        }
        directory = dir

        try? FileManager.default.removeItem(at: dir.appendingPathComponent(AudioConstants.stopRequestName))
        let sentinel = dir.appendingPathComponent(AudioConstants.liveSentinelName)
        try? "\(Date().timeIntervalSince1970)".write(to: sentinel, atomically: true, encoding: .utf8)

        let writer = ChunkWriter(directory: dir)
        chunkWriter = writer

        // Prove the write path works even before any audio arrives.
        let silence = [Int16](repeating: 0, count: AudioConstants.framesPerChunk * AudioConstants.channels)
        writer.append(interleavedStereo: silence)
        stats.chunksWritten = 1
        stats.lastError = "started"
        stats.write(to: dir)

        NSLog("[SampleHandler] broadcast started → %@", dir.path)
    }

    override func broadcastPaused() {
        stats.lastError = "paused"
        if let directory { stats.write(to: directory) }
    }

    override func broadcastResumed() {
        stats.lastError = "resumed"
        if let directory { stats.write(to: directory) }
    }

    override func broadcastFinished() {
        finalizeCapture()
    }

    /// Writes every remaining frame, then removes the live sentinel so the app
    /// knows all chunks are on disk. Safe to call more than once.
    private func finalizeCapture() {
        guard let writer = chunkWriter else { return }
        chunkWriter = nil

        let drained = aligner.drainWithSilencePadding()
        if !drained.isEmpty {
            writer.append(interleavedStereo: drained)
        }
        writer.flush()
        stats.chunksWritten = writer.sequenceValue
        stats.lastError = "finished"
        if let directory {
            stats.write(to: directory)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(AudioConstants.stopRequestName))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(AudioConstants.liveSentinelName))
        }
        aligner.reset()
        NSLog("[SampleHandler] finished %@", stats.summary)
    }

    private var lastStopCheck = Date.distantPast
    private func stopRequested() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastStopCheck) >= 0.25, let directory else { return false }
        lastStopCheck = now
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(AudioConstants.stopRequestName).path)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard chunkWriter != nil else { return }
        if stopRequested() {
            finalizeCapture()
            finishBroadcastWithError(NSError(
                domain: "MeetingBroadcast",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Müsli finished capturing your meeting."]
            ))
            return
        }

        // Process on the ReplayKit thread: buffers are only valid here.
        switch sampleBufferType {
        case .video:
            stats.videoBuffers += 1
            maybeFlushStats()
            return

        case .audioMic:
            stats.micBuffers += 1
            ingest(sampleBuffer, side: .mic)

        case .audioApp:
            stats.systemBuffers += 1
            ingest(sampleBuffer, side: .system)

        @unknown default:
            return
        }
    }

    private enum Side { case mic, system }

    private func ingest(_ sampleBuffer: CMSampleBuffer, side: Side) {
        let resampler = (side == .mic) ? micResampler : systemResampler
        guard let mono = resampler.resample(sampleBuffer) else {
            stats.resampleFailures += 1
            if let asbd = sampleBufferFormatSummary(sampleBuffer) {
                stats.lastError = "resample fail: \(asbd)"
            } else {
                stats.lastError = "resample fail (no format)"
            }
            maybeFlushStats()
            return
        }

        switch side {
        case .mic:    aligner.appendMic(mono)
        case .system: aligner.appendSystem(mono)
        }

        let stereo = aligner.pullAlignedFrames(maxSkewFrames: AudioConstants.framesPerChunk)
        if !stereo.isEmpty {
            chunkWriter?.append(interleavedStereo: stereo)
            stats.chunksWritten = chunkWriter?.sequenceValue ?? stats.chunksWritten
            stats.framesEmitted += stereo.count / 2
        }
        maybeFlushStats()
    }

    private var statsCounter = 0
    private func maybeFlushStats() {
        statsCounter += 1
        guard statsCounter == 1 || statsCounter % 30 == 0, let directory else { return }
        stats.write(to: directory)
    }

    private func sampleBufferFormatSummary(_ sampleBuffer: CMSampleBuffer) -> String? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }
        return String(format: "%.0fHz ch=%u bits=%u flags=0x%08x frames=%d",
                      asbd.mSampleRate,
                      asbd.mChannelsPerFrame,
                      asbd.mBitsPerChannel,
                      asbd.mFormatFlags,
                      CMSampleBufferGetNumSamples(sampleBuffer))
    }
}

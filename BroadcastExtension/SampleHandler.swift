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
    private let processQueue = DispatchQueue(label: "com.granola.iosmeeting.audio", qos: .userInitiated)
    private var micBuffers = 0
    private var systemBuffers = 0
    private var resampleFailures = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Don't clear here if the app is already listening — just ensure the dir exists.
        guard let dir = AppGroup.ensureChunksDirectory() else {
            finishBroadcastWithError(NSError(
                domain: "MeetingBroadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable. Check App Groups entitlement."]
            ))
            return
        }
        // Write a sentinel so the host app can confirm the extension launched.
        let sentinel = dir.appendingPathComponent("_broadcast_live")
        try? "\(Date().timeIntervalSince1970)".write(to: sentinel, atomically: true, encoding: .utf8)

        chunkWriter = ChunkWriter(directory: dir)
        micBuffers = 0
        systemBuffers = 0
        resampleFailures = 0
        NSLog("[SampleHandler] broadcast started → %@", dir.path)
    }

    override func broadcastPaused() {
        NSLog("[SampleHandler] paused")
    }

    override func broadcastResumed() {
        NSLog("[SampleHandler] resumed")
    }

    override func broadcastFinished() {
        processQueue.sync {
            let drained = aligner.drainWithSilencePadding()
            chunkWriter?.append(interleavedStereo: drained)
            chunkWriter?.flush()
            chunkWriter = nil
            aligner.reset()
        }
        if let dir = AppGroup.chunksDirectoryURL {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("_broadcast_live"))
        }
        NSLog("[SampleHandler] finished mic=%d sys=%d fail=%d", micBuffers, systemBuffers, resampleFailures)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            return // discard video

        case .audioMic, .audioApp:
            // ReplayKit buffers are only valid during this callback — copy before async work.
            var copied: CMSampleBuffer?
            let status = CMSampleBufferCreateCopy(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleBufferOut: &copied
            )
            guard status == noErr, let copied else {
                NSLog("[SampleHandler] CMSampleBufferCreateCopy failed: %d", status)
                return
            }
            let side: Side = (sampleBufferType == .audioMic) ? .mic : .system
            processQueue.async { [weak self] in
                self?.ingest(copied, side: side)
            }

        @unknown default:
            return
        }
    }

    private enum Side { case mic, system }

    private func ingest(_ sampleBuffer: CMSampleBuffer, side: Side) {
        switch side {
        case .mic:    micBuffers += 1
        case .system: systemBuffers += 1
        }

        let resampler = (side == .mic) ? micResampler : systemResampler
        guard let mono = resampler.resample(sampleBuffer) else {
            resampleFailures += 1
            if resampleFailures <= 5 || resampleFailures % 50 == 0 {
                NSLog("[SampleHandler] resample failed (%d) side=%@", resampleFailures, side == .mic ? "mic" : "sys")
            }
            return
        }

        switch side {
        case .mic:    aligner.appendMic(mono)
        case .system: aligner.appendSystem(mono)
        }

        // Pad the lagging channel after ~32 ms so a single source still produces chunks.
        let stereo = aligner.pullAlignedFrames(maxSkewFrames: AudioConstants.framesPerChunk)
        if !stereo.isEmpty {
            chunkWriter?.append(interleavedStereo: stereo)
        }
    }
}

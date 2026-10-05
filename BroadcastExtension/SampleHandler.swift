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
    private let processQueue = DispatchQueue(label: "com.granola.ios-meeting.audio", qos: .userInitiated)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        AppGroup.clearChunks()
        guard let dir = AppGroup.ensureChunksDirectory() else {
            finishBroadcastWithError(NSError(
                domain: "MeetingBroadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable. Check entitlements."]
            ))
            return
        }
        chunkWriter = ChunkWriter(directory: dir)
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
        NSLog("[SampleHandler] broadcast finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            return // discard video

        case .audioMic:
            processQueue.async { [weak self] in
                self?.ingest(sampleBuffer, side: .mic)
            }

        case .audioApp:
            processQueue.async { [weak self] in
                self?.ingest(sampleBuffer, side: .system)
            }

        @unknown default:
            return
        }
    }

    private enum Side { case mic, system }

    private func ingest(_ sampleBuffer: CMSampleBuffer, side: Side) {
        let resampler = (side == .mic) ? micResampler : systemResampler
        guard let mono = resampler.resample(sampleBuffer) else { return }

        switch side {
        case .mic:    aligner.appendMic(mono)
        case .system: aligner.appendSystem(mono)
        }

        let stereo = aligner.pullAlignedFrames()
        if !stereo.isEmpty {
            chunkWriter?.append(interleavedStereo: stereo)
        }
    }
}

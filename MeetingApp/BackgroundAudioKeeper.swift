import AVFoundation

/// Keeps the app eligible for `UIBackgroundModes: audio` while Listen is active:
/// mixable playback session + a running engine with an idle player node.
final class BackgroundAudioKeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        if player.engine == nil {
            engine.attach(player)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        try engine.start()
        player.play()
        isRunning = true
        NSLog("[BackgroundAudioKeeper] started (mixable playback)")
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        NSLog("[BackgroundAudioKeeper] stopped")
    }
}

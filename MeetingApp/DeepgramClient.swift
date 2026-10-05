import Foundation

/// Minimal Deepgram streaming client.
/// Sends stereo linear16 PCM with `multichannel=true` so each channel
/// is transcribed independently (channel 0 = mic/us, channel 1 = system/them).
final class DeepgramClient: NSObject {
    enum Speaker: String {
        case us   // channel 0 — microphone
        case them // channel 1 — system audio
    }

    struct TranscriptEvent: Equatable {
        let speaker: Speaker
        let text: String
        let isFinal: Bool
        let channelIndex: Int
    }

    var onTranscript: ((TranscriptEvent) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepAliveTimer: Timer?
    private let apiKey: String

    init(apiKey: String) {
        var key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("token ") {
            key = String(key.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.apiKey = key
        super.init()
    }

    func connect() {
        disconnect()

        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "2"),
            URLQueryItem(name: "multichannel", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "endpointing", value: "300"),
        ]

        guard let url = components.url else { return }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        listen()
        startKeepAlive()
        onStatus?("Connecting to Deepgram…")
    }

    func send(pcmChunk data: Data) {
        guard let webSocket, webSocket.state == .running else { return }
        webSocket.send(.data(data)) { [weak self] error in
            if let error {
                self?.onError?(error)
            }
        }
    }

    /// Sends CloseStream and waits for Deepgram to return its final results and
    /// close the socket (or `timeout`), then tears down. Call on the main thread;
    /// `completion` runs on main after every transcript has been delivered.
    func finish(timeout: TimeInterval = 5, completion: @escaping () -> Void) {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        guard let webSocket, webSocket.state == .running else {
            disconnect()
            completion()
            return
        }
        finishCompletion = completion
        webSocket.send(.string(#"{"type":"CloseStream"}"#)) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.completeFinish()
        }
    }

    func disconnect() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private var finishCompletion: (() -> Void)?

    private func completeFinish() {
        guard let completion = finishCompletion else { return }
        finishCompletion = nil
        disconnect()
        completion()
    }

    private func socketDidEnd() {
        DispatchQueue.main.async { [weak self] in
            self?.completeFinish()
        }
    }

    // MARK: - Private

    private func startKeepAlive() {
        DispatchQueue.main.async { [weak self] in
            self?.keepAliveTimer?.invalidate()
            self?.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
                let msg = #"{"type":"KeepAlive"}"#
                self?.webSocket?.send(.string(msg)) { _ in }
            }
        }
    }

    private func listen() {
        guard let task = webSocket else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    if self.webSocket === task && self.finishCompletion == nil {
                        self.onError?(error)
                    }
                }
                self.socketDidEnd()
            case .success(let message):
                self.handle(message)
                self.listen()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text): data = text.data(using: .utf8)
        case .data(let d): data = d
        @unknown default: data = nil
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Deepgram Results message.
        guard (json["type"] as? String) == "Results" || json["channel"] != nil || json["channel_index"] != nil else {
            if let type = json["type"] as? String, type == "Metadata" {
                onStatus?("Deepgram connected")
            }
            return
        }

        let isFinal = (json["is_final"] as? Bool) ?? false
        // Multichannel: channel_index is [channel, alternative]
        let channelIndex: Int
        if let idx = json["channel_index"] as? [Int], let first = idx.first {
            channelIndex = first
        } else if let idx = json["channel_index"] as? Int {
            channelIndex = idx
        } else {
            channelIndex = 0
        }

        guard let channel = json["channel"] as? [String: Any],
              let alts = channel["alternatives"] as? [[String: Any]],
              let first = alts.first,
              let transcript = first["transcript"] as? String,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let speaker: Speaker = (channelIndex == 0) ? .us : .them
        let event = TranscriptEvent(
            speaker: speaker,
            text: transcript,
            isFinal: isFinal,
            channelIndex: channelIndex
        )
        DispatchQueue.main.async { [weak self] in
            self?.onTranscript?(event)
        }
    }
}

extension DeepgramClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onStatus?("Deepgram connected")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onStatus?("Deepgram closed (\(closeCode.rawValue))")
        socketDidEnd()
    }
}

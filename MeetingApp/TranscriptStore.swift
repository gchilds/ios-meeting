import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let speaker: DeepgramClient.Speaker
    var text: String
    var isFinal: Bool
    let createdAt: Date

    init(speaker: DeepgramClient.Speaker, text: String, isFinal: Bool) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
        self.createdAt = Date()
    }
}

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var extensionStatus = "Idle"
    @Published var deepgramStatus = "Idle"
    @Published var isLive = false
    @Published var chunksSent: UInt64 = 0
    @Published var broadcastLive = false
    @Published var extensionStats: ExtensionStats?

    @Published var summaryMarkdown: String = ""
    @Published var isSummarizing = false
    @Published var summaryError: String?

    private let watcher = ChunkWatcher()
    private let backgroundAudio = BackgroundAudioKeeper()
    private var deepgram: DeepgramClient?
    private var interimIDs: [DeepgramClient.Speaker: UUID] = [:]
    private var statusCancellable: AnyCancellable?
    private var statsCancellable: AnyCancellable?
    private var wasBroadcastLive = false

    var deepgramAPIKey: String = ""
    var openAIAPIKey: String = ""

    func start() {
        guard !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            deepgramStatus = "Error"
            return
        }

        do {
            try backgroundAudio.start()
        } catch {
            deepgramStatus = "Error"
            return
        }

        AppGroup.clearChunks()
        messages.removeAll()
        interimIDs.removeAll()
        chunksSent = 0
        summaryMarkdown = ""
        summaryError = nil
        wasBroadcastLive = false
        extensionStatus = "Waiting"
        deepgramStatus = "Connecting"

        let client = DeepgramClient(apiKey: deepgramAPIKey)
        client.onStatus = { [weak self] s in
            Task { @MainActor in self?.applyDeepgramStatus(s) }
        }
        client.onError = { [weak self] _ in
            Task { @MainActor in self?.deepgramStatus = "Error" }
        }
        client.onTranscript = { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
        }
        client.connect()
        deepgram = client

        statusCancellable = watcher.$broadcastLive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] live in
                guard let self else { return }
                let ended = self.wasBroadcastLive && !live
                self.wasBroadcastLive = live
                self.broadcastLive = live
                self.extensionStatus = live ? "Recording" : (self.isLive ? "Waiting" : "Idle")
                if ended {
                    self.requestSummary(reason: "Broadcast ended")
                }
            }

        statsCancellable = watcher.$extensionStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.extensionStats = stats
            }

        watcher.start { [weak self] data in
            Task { @MainActor in
                self?.deepgram?.send(pcmChunk: data)
                self?.chunksSent += 1
            }
        }

        isLive = true
    }

    func stop() {
        statusCancellable?.cancel()
        statusCancellable = nil
        statsCancellable?.cancel()
        statsCancellable = nil
        watcher.stop()
        deepgram?.disconnect()
        deepgram = nil
        backgroundAudio.stop()
        isLive = false
        broadcastLive = false
        extensionStats = nil
        extensionStatus = "Idle"
        deepgramStatus = "Idle"
        requestSummary(reason: "Listen stopped")
    }

    func requestSummary(reason: String) {
        guard !isSummarizing else { return }
        let finals = messages.filter(\.isFinal)
        guard !finals.isEmpty else {
            summaryError = "No final transcript yet (\(reason))"
            return
        }
        guard !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            summaryError = "Set your OpenAI API key to generate a summary"
            return
        }

        let transcript = finals.map { msg in
            let who = msg.speaker == .us ? "Us" : "Them"
            return "\(who): \(msg.text)"
        }.joined(separator: "\n")

        isSummarizing = true
        summaryError = nil

        let key = openAIAPIKey
        Task {
            do {
                let sanitized = OpenAIClient.sanitize(key)
                if !sanitized.hasPrefix("sk-") {
                    summaryError = "OpenAI key should start with sk-…"
                    isSummarizing = false
                    return
                }
                let client = OpenAIClient(apiKey: sanitized)
                let markdown = try await client.summarizeMeeting(transcript: transcript)
                summaryMarkdown = markdown
            } catch {
                summaryError = error.localizedDescription
            }
            isSummarizing = false
        }
    }

    private func applyDeepgramStatus(_ raw: String) {
        let lower = raw.lowercased()
        if lower.contains("connect") && !lower.contains("connected") {
            deepgramStatus = "Connecting"
        } else if lower.contains("connected") {
            deepgramStatus = "Connected"
        } else if lower.contains("closed") || lower.contains("disconnect") {
            deepgramStatus = isLive ? "Connecting" : "Idle"
        } else if lower.contains("error") {
            deepgramStatus = "Error"
        }
    }

    private func ingest(_ event: DeepgramClient.TranscriptEvent) {
        if event.isFinal {
            if let interimID = interimIDs[event.speaker],
               let idx = messages.firstIndex(where: { $0.id == interimID }) {
                messages[idx].text = event.text
                messages[idx].isFinal = true
                interimIDs[event.speaker] = nil
            } else {
                messages.append(ChatMessage(speaker: event.speaker, text: event.text, isFinal: true))
            }
        } else {
            if let interimID = interimIDs[event.speaker],
               let idx = messages.firstIndex(where: { $0.id == interimID }) {
                messages[idx].text = event.text
            } else {
                let msg = ChatMessage(speaker: event.speaker, text: event.text, isFinal: false)
                interimIDs[event.speaker] = msg.id
                messages.append(msg)
            }
        }
    }
}

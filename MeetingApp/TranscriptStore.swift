import Foundation

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

extension DeepgramClient.Speaker {
    var displayName: String {
        switch self {
        case .us: return "Gordon"
        case .them: return "Chris"
        }
    }
}

/// A transcription session follows the broadcast: it starts when the extension
/// goes live and ends once its final chunk has been sent and Deepgram has
/// returned its last results.
@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var broadcastLive = false
    @Published private(set) var isStopping = false
    @Published private(set) var sessionError: String?

    @Published var summaryMarkdown: String = ""
    @Published var isSummarizing = false
    @Published var summaryError: String?

    private let watcher = ChunkWatcher()
    private let backgroundAudio = BackgroundAudioKeeper()
    private var deepgram: DeepgramClient?
    private var interimIDs: [DeepgramClient.Speaker: UUID] = [:]
    private var forceEndWork: DispatchWorkItem?

    var deepgramAPIKey: String = ""
    var openAIAPIKey: String = ""

    init() {
        watcher.start { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    /// Asks the extension to finish. If it doesn't respond, ends the session anyway.
    func stop() {
        guard broadcastLive, !isStopping else { return }
        isStopping = true
        watcher.requestStop()
        let work = DispatchWorkItem { [weak self] in self?.watcher.forceEnd() }
        forceEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func handle(_ event: ChunkWatcher.Event) {
        switch event {
        case .started:
            beginSession()
        case .chunk(let data):
            deepgram?.send(pcmChunk: data)
        case .ended:
            endSession()
        }
    }

    private func beginSession() {
        broadcastLive = true
        isStopping = false
        messages.removeAll()
        interimIDs.removeAll()
        summaryMarkdown = ""
        summaryError = nil
        sessionError = nil

        guard !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sessionError = "Add your Deepgram key to transcribe."
            return
        }

        do {
            try backgroundAudio.start()
        } catch {
            sessionError = "Couldn't keep running in the background: \(error.localizedDescription)"
        }

        let client = DeepgramClient(apiKey: deepgramAPIKey)
        client.onError = { [weak self] error in
            Task { @MainActor in self?.sessionError = "Deepgram: \(error.localizedDescription)" }
        }
        // Delivered on main; handled synchronously so the last results land before `finish` completes.
        client.onTranscript = { [weak self] event in
            MainActor.assumeIsolated { self?.ingest(event) }
        }
        client.connect()
        deepgram = client
    }

    private func endSession() {
        forceEndWork?.cancel()
        forceEndWork = nil
        broadcastLive = false
        isStopping = true

        let finishUp = { [weak self] in
            guard let self else { return }
            self.deepgram = nil
            self.promoteInterims()
            self.backgroundAudio.stop()
            self.isStopping = false
            self.requestSummary(reason: "Broadcast ended")
        }

        if let deepgram {
            deepgram.finish { MainActor.assumeIsolated { finishUp() } }
        } else {
            finishUp()
        }
    }

    private func promoteInterims() {
        for id in interimIDs.values {
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].isFinal = true
            }
        }
        interimIDs.removeAll()
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

        let transcript = finals.map { "\($0.speaker.displayName): \($0.text)" }.joined(separator: "\n")

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

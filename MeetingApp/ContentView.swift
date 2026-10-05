import SwiftUI
import ReplayKit

struct ContentView: View {
    @EnvironmentObject private var store: TranscriptStore
    @AppStorage("deepgramAPIKey") private var deepgramAPIKey = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var showKeyField = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                Divider()
                TabView(selection: $selectedTab) {
                    chatList
                        .tabItem { Label("Transcript", systemImage: "bubble.left.and.bubble.right") }
                        .tag(0)
                    summaryPane
                        .tabItem { Label("Summary", systemImage: "doc.text") }
                        .tag(1)
                }
                Divider()
                controlBar
            }
            .navigationTitle("Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showKeyField.toggle()
                    } label: {
                        Image(systemName: keysConfigured ? "key.fill" : "key")
                    }
                }
            }
            .sheet(isPresented: $showKeyField) {
                apiKeySheet
            }
            .onAppear { syncKeys() }
            .onChange(of: deepgramAPIKey) { _, _ in syncKeys() }
            .onChange(of: openAIAPIKey) { _, _ in syncKeys() }
            .onChange(of: store.summaryMarkdown) { _, newValue in
                if !newValue.isEmpty { selectedTab = 1 }
            }
        }
    }

    private var keysConfigured: Bool {
        !deepgramAPIKey.isEmpty && !openAIAPIKey.isEmpty
    }

    private func syncKeys() {
        store.deepgramAPIKey = deepgramAPIKey
        store.openAIAPIKey = openAIAPIKey
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(store.broadcastLive ? Color.green : (store.isLive ? Color.orange : Color.secondary.opacity(0.4)))
                .frame(width: 8, height: 8)
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(store.chunksSent) chunks")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.messages.isEmpty {
                        emptyTranscript
                    }
                    ForEach(store.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: store.messages.count) { _, _ in
                if let last = store.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var summaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.isSummarizing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing meeting notes…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = store.summaryError, store.summaryMarkdown.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button("Retry summary") {
                        store.requestSummary(reason: "Retry")
                    }
                    .buttonStyle(.bordered)
                } else if store.summaryMarkdown.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No summary yet")
                            .font(.headline)
                        Text("Notes are generated with OpenAI when you Stop, or when the broadcast ends.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(LocalizedStringKey(store.summaryMarkdown))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if store.summaryError != nil {
                        Button("Regenerate") {
                            store.requestSummary(reason: "Regenerate")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
    }

    private var emptyTranscript: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Start a broadcast, then tap Listen")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Mic → Us (left) · System audio → Them (right)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            BroadcastPicker()
                .frame(width: 44, height: 44)

            Button {
                if store.isLive {
                    store.stop()
                } else {
                    syncKeys()
                    store.start()
                }
            } label: {
                Label(
                    store.isLive ? "Stop" : "Listen",
                    systemImage: store.isLive ? "stop.circle.fill" : "ear.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isLive ? .red : .accentColor)
            .disabled(deepgramAPIKey.isEmpty && !store.isLive)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Deepgram API key", text: $deepgramAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("From console.deepgram.com — used for live streaming transcription.")
                }

                Section {
                    SecureField("OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("From platform.openai.com → API keys. Used only for the end-of-meeting summary (gpt-4o-mini). Create a key, enable billing if needed, and paste it here.")
                }
            }
            .navigationTitle("API Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showKeyField = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.granola.iosmeeting.BroadcastExtension"
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    ContentView()
        .environmentObject(TranscriptStore())
}

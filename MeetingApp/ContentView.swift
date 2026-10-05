import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TranscriptStore
    @AppStorage("deepgramAPIKey") private var deepgramAPIKey = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var showKeyField = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MusliBackground()
                VStack(spacing: 0) {
                    statusBar
                    TabView(selection: $selectedTab) {
                        chatList
                            .tabItem { Label("Transcript", systemImage: "text.bubble") }
                            .tag(0)
                        summaryPane
                            .tabItem { Label("Notes", systemImage: "leaf") }
                            .tag(1)
                    }
                    .tint(MusliTheme.forest)
                    controlBar
                }
            }
            .navigationTitle("Müsli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MusliTheme.paper.opacity(0.95), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showKeyField.toggle()
                    } label: {
                        Image(systemName: keysConfigured ? "key.fill" : "key")
                            .foregroundStyle(MusliTheme.forest)
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

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 10) {
            StatusPill(label: "Extension", value: store.extensionStatus, tint: extensionTint)
            StatusPill(label: "Deepgram", value: store.deepgramStatus, tint: deepgramTint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var extensionTint: Color {
        switch store.extensionStatus {
        case "Recording": return MusliTheme.forest
        case "Waiting": return MusliTheme.honey
        case "Error": return .red
        default: return MusliTheme.inkMuted.opacity(0.5)
        }
    }

    private var deepgramTint: Color {
        switch store.deepgramStatus {
        case "Connected": return MusliTheme.forest
        case "Connecting": return MusliTheme.honey
        case "Error": return .red
        default: return MusliTheme.inkMuted.opacity(0.5)
        }
    }

    // MARK: - Transcript

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
    }

    private var emptyTranscript: some View {
        VStack(spacing: 14) {
            Text("🥣")
                .font(.system(size: 52))
            Text("Your meeting, transcribed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MusliTheme.ink)
            Text("Broadcast to capture · Listen to transcribe\nYou on mic · Others on system audio")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MusliTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }

    // MARK: - Summary

    private var summaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.isSummarizing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(MusliTheme.forest)
                        Text("Stirring your notes…")
                            .font(.subheadline)
                            .foregroundStyle(MusliTheme.inkMuted)
                    }
                } else if let error = store.summaryError, store.summaryMarkdown.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button("Try again") {
                        store.requestSummary(reason: "Retry")
                    }
                    .buttonStyle(MusliSecondaryButtonStyle())
                } else if store.summaryMarkdown.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes appear here")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(MusliTheme.ink)
                        Text("When the broadcast ends or you tap Stop, Müsli writes a short summary.")
                            .font(.subheadline)
                            .foregroundStyle(MusliTheme.inkMuted)
                    }
                } else {
                    MeetingNotesView(markdown: store.summaryMarkdown)
                        .padding(16)
                        .background(MusliTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button("Regenerate notes") {
                        store.requestSummary(reason: "Regenerate")
                    }
                    .buttonStyle(MusliSecondaryButtonStyle())
                }
            }
            .padding(16)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                BroadcastPickerView(isLive: store.broadcastLive)

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.isLive ? "Listening…" : "Ready when you are")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MusliTheme.ink)

                    Button {
                        if store.isLive {
                            store.stop()
                        } else {
                            syncKeys()
                            store.start()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.isLive ? "stop.fill" : "waveform")
                            Text(store.isLive ? "Stop" : "Listen")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(MusliPrimaryButtonStyle(isDestructive: store.isLive))
                    .disabled(deepgramAPIKey.isEmpty && !store.isLive)
                }
            }
        }
        .padding(16)
        .background(
            MusliTheme.oat.opacity(0.85),
            in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
        )
    }

    // MARK: - Keys sheet

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Deepgram API key", text: $deepgramAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Live transcription via Deepgram.")
                }

                Section {
                    SecureField("OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Meeting notes via OpenAI (sk-…).")
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

// MARK: - Button styles

struct MusliPrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .background {
                Capsule().fill(buttonFill)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var buttonFill: AnyShapeStyle {
        if isDestructive {
            AnyShapeStyle(LinearGradient(colors: [.red.opacity(0.85), .red], startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            AnyShapeStyle(MusliTheme.listenGradient)
        }
    }
}

struct MusliSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(MusliTheme.forest)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(MusliTheme.oat, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

#Preview {
    ContentView()
        .environmentObject(TranscriptStore())
}

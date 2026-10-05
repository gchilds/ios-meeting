import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TranscriptStore
    @AppStorage("deepgramAPIKey") private var deepgramAPIKey = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var showKeys = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(MusliTheme.line)
                .frame(height: 1)
            Group {
                if selectedTab == 0 {
                    transcriptPane
                } else {
                    notesPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlBar
        }
        .background(MusliTheme.paper.ignoresSafeArea())
        .sheet(isPresented: $showKeys) { keysSheet }
        .onAppear { syncKeys() }
        .onChange(of: deepgramAPIKey) { _, _ in syncKeys() }
        .onChange(of: openAIAPIKey) { _, _ in syncKeys() }
        .onChange(of: store.summaryMarkdown) { _, newValue in
            if !newValue.isEmpty {
                withAnimation { selectedTab = 1 }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Müsli")
                    .font(MusliTheme.title(30))
                    .foregroundStyle(MusliTheme.ink)
                Spacer()
                Button {
                    showKeys = true
                } label: {
                    Image(systemName: "key")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(keysConfigured ? MusliTheme.inkMuted : MusliTheme.berry)
                        .frame(width: 34, height: 34)
                        .background(MusliTheme.oat, in: Circle())
                }
                .accessibilityLabel("API keys")
            }

            SegmentedTabs(selection: $selectedTab, titles: ["Transcript", "Notes"])
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: - Transcript

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.messages.isEmpty {
                        emptyBowl
                    }
                    ForEach(store.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
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

    private var emptyBowl: some View {
        VStack(spacing: 10) {
            Text("🥣")
                .font(.system(size: 56))
            Text("Nothing in the bowl yet")
                .font(MusliTheme.title(22))
                .foregroundStyle(MusliTheme.ink)
            Text("Tap the bowl to start capturing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(MusliTheme.inkMuted)
            if let error = store.sessionError {
                Text(error)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MusliTheme.berry)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }

    // MARK: - Notes

    private var notesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting notes")
                    .font(MusliTheme.title(26))
                    .foregroundStyle(MusliTheme.ink)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(MusliTheme.inkMuted)
                    .padding(.bottom, 8)

                if store.isSummarizing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(MusliTheme.leaf)
                        Text("Stirring your müsli…")
                            .foregroundStyle(MusliTheme.inkMuted)
                    }
                    .padding(.top, 12)
                } else if store.summaryMarkdown.isEmpty {
                    if let error = store.summaryError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(MusliTheme.berry)
                            .padding(.top, 8)
                        regenerateButton(title: "Try again")
                    } else {
                        Text("Notes appear here when the capture ends.")
                            .foregroundStyle(MusliTheme.inkMuted)
                            .padding(.top, 8)
                    }
                } else {
                    MeetingNotesView(markdown: store.summaryMarkdown)
                    regenerateButton(title: "Regenerate")
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func regenerateButton(title: String) -> some View {
        Button {
            store.requestSummary(reason: title)
        } label: {
            Label(title, systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MusliTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MusliTheme.oat, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 14) {
            BroadcastBowlButton(isLive: store.broadcastLive)

            VStack(alignment: .leading, spacing: 2) {
                Text(controlTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MusliTheme.ink)
                Text(controlSubtitle)
                    .font(.caption)
                    .foregroundStyle(MusliTheme.inkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if store.isStopping {
                ProgressView()
                    .tint(MusliTheme.leaf)
                    .padding(.horizontal, 20)
            } else if store.broadcastLive {
                Button {
                    store.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(MusliStopButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.broadcastLive)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.isStopping)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(MusliTheme.card)
                .shadow(color: .black.opacity(0.06), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var controlTitle: String {
        if store.isStopping { return "Wrapping up" }
        return store.broadcastLive ? "Capturing & transcribing" : "Ready"
    }

    private var controlSubtitle: String {
        if store.isStopping { return "Catching the last few words…" }
        if store.broadcastLive { return "Hop over to your call — Müsli's got it." }
        return deepgramAPIKey.isEmpty
            ? "Add your Deepgram key, then tap the bowl."
            : "Tap the bowl to capture your meeting."
    }

    // MARK: - Keys

    private var keysSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Deepgram API key", text: $deepgramAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Live transcription.")
                }
                Section {
                    SecureField("OpenAI API key", text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Meeting notes. Starts with sk-.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MusliTheme.paper)
            .navigationTitle("API keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showKeys = false }
                }
            }
        }
        .tint(MusliTheme.leaf)
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
        .environmentObject(TranscriptStore())
}

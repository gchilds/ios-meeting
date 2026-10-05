import SwiftUI
import ReplayKit

struct ContentView: View {
    @EnvironmentObject private var store: TranscriptStore
    @AppStorage("deepgramAPIKey") private var apiKey = ""
    @State private var showKeyField = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                Divider()
                chatList
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
                        Image(systemName: apiKey.isEmpty ? "key" : "key.fill")
                    }
                }
            }
            .sheet(isPresented: $showKeyField) {
                apiKeySheet
            }
            .onAppear {
                store.apiKey = apiKey
            }
            .onChange(of: apiKey) { _, newValue in
                store.apiKey = newValue
            }
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(store.isLive ? Color.green : Color.secondary.opacity(0.4))
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
                        emptyState
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

    private var emptyState: some View {
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
            // System broadcast picker — user chooses this app's extension.
            BroadcastPicker()
                .frame(width: 44, height: 44)

            Button {
                if store.isLive {
                    store.stop()
                } else {
                    store.apiKey = apiKey
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
            .disabled(apiKey.isEmpty && !store.isLive)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Deepgram API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Stored in UserDefaults on this device. Sent only as the Deepgram Authorization header.")
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showKeyField = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Thin wrapper around ReplayKit's broadcast activity picker.
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.granola.ios-meeting.BroadcastExtension"
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    ContentView()
        .environmentObject(TranscriptStore())
}

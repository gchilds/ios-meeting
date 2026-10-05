import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    private var isYou: Bool { message.speaker == .us }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isYou { Spacer(minLength: 40) }

            VStack(alignment: isYou ? .trailing : .leading, spacing: 4) {
                Text(isYou ? "You" : "Others")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isYou ? MusliTheme.forest : MusliTheme.inkMuted)
                    .padding(.horizontal, 4)

                Group {
                    if isYou {
                        Text(message.text)
                            .foregroundStyle(.white)
                            .background(MusliTheme.listenGradient)
                    } else {
                        Text(message.text)
                            .foregroundStyle(MusliTheme.ink)
                            .background(MusliTheme.othersBubble)
                    }
                }
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(message.isFinal ? 1.0 : 0.7)
            }

            if !isYou { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    ZStack {
        MusliBackground()
        VStack(spacing: 12) {
            ChatBubbleView(message: ChatMessage(speaker: .them, text: "How are the Q3 numbers looking?", isFinal: true))
            ChatBubbleView(message: ChatMessage(speaker: .us, text: "Ahead of plan — shipping next week.", isFinal: true))
            ChatBubbleView(message: ChatMessage(speaker: .them, text: "Great, can you…", isFinal: false))
        }
        .padding()
    }
}

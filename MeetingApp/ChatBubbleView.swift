import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    private var isMe: Bool { message.speaker == .us }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 48) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                Text(message.speaker.displayName)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(isMe ? MusliTheme.leaf : MusliTheme.inkMuted)
                    .padding(.horizontal, 4)

                Text(message.text)
                    .italic(!message.isFinal)
                    .font(.body)
                    .foregroundStyle(message.isFinal ? MusliTheme.ink : MusliTheme.inkMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isMe ? MusliTheme.leafWash : MusliTheme.card,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isMe ? .clear : MusliTheme.line, lineWidth: 1)
                    )
            }

            if !isMe { Spacer(minLength: 48) }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ChatBubbleView(message: ChatMessage(speaker: .them, text: "How are the Q3 numbers looking?", isFinal: true))
        ChatBubbleView(message: ChatMessage(speaker: .us, text: "Ahead of plan — shipping next week.", isFinal: true))
        ChatBubbleView(message: ChatMessage(speaker: .them, text: "Great, can you…", isFinal: false))
    }
    .padding()
    .background(MusliTheme.paper)
}

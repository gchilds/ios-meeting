import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    private var isUs: Bool { message.speaker == .us }

    var body: some View {
        HStack {
            if isUs { Spacer(minLength: 48) }

            VStack(alignment: isUs ? .trailing : .leading, spacing: 4) {
                Text(isUs ? "Us" : "Them")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isUs ? Color.accentColor : Color.orange)
                    .padding(.horizontal, 4)

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isUs ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isUs ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                    .opacity(message.isFinal ? 1.0 : 0.65)
            }

            if !isUs { Spacer(minLength: 48) }
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
}

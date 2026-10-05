import SwiftUI

enum MusliTheme {
    static let paper = Color(red: 0.980, green: 0.976, blue: 0.965)
    static let card = Color.white
    static let oat = Color(red: 0.953, green: 0.937, blue: 0.902)
    static let line = Color(red: 0.898, green: 0.886, blue: 0.859)
    static let ink = Color(red: 0.110, green: 0.106, blue: 0.098)
    static let inkMuted = Color(red: 0.463, green: 0.451, blue: 0.427)
    static let leaf = Color(red: 0.400, green: 0.620, blue: 0.180)
    static let leafWash = Color(red: 0.925, green: 0.953, blue: 0.886)
    static let honey = Color(red: 0.890, green: 0.660, blue: 0.250)
    static let berry = Color(red: 0.840, green: 0.310, blue: 0.330)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

struct StatusDot: View {
    let label: String
    let value: String
    let color: Color
    var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(paused: !pulsing)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.6 + 0.4 * cos(t * 4) : 1)
            }
            .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(MusliTheme.inkMuted)
            Text(value)
                .foregroundStyle(MusliTheme.ink)
        }
        .font(.caption.weight(.medium))
    }
}

struct SegmentedTabs: View {
    @Binding var selection: Int
    let titles: [String]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = index
                    }
                } label: {
                    Text(titles[index])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == index ? MusliTheme.ink : MusliTheme.inkMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if selection == index {
                                Capsule()
                                    .fill(MusliTheme.card)
                                    .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(MusliTheme.oat, in: Capsule())
    }
}

struct MusliListenButtonStyle: ButtonStyle {
    var isStop = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isStop ? MusliTheme.berry : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isStop ? MusliTheme.card : MusliTheme.ink, in: Capsule())
            .overlay(Capsule().strokeBorder(isStop ? MusliTheme.berry.opacity(0.5) : .clear, lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

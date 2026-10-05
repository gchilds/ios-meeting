import SwiftUI

/// Granola-adjacent palette: warm paper, oat cream, soft forest green, honey accent.
enum MusliTheme {
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let oat = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let honey = Color(red: 0.92, green: 0.72, blue: 0.38)
    static let forest = Color(red: 0.22, green: 0.48, blue: 0.36)
    static let forestSoft = Color(red: 0.35, green: 0.58, blue: 0.46)
    static let ink = Color(red: 0.18, green: 0.17, blue: 0.15)
    static let inkMuted = Color(red: 0.45, green: 0.43, blue: 0.40)
    static let card = Color.white.opacity(0.72)
    static let othersBubble = Color(red: 0.96, green: 0.95, blue: 0.92)

    static let recordGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.55, blue: 0.42),
            Color(red: 0.91, green: 0.38, blue: 0.48)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let listenGradient = LinearGradient(
        colors: [forestSoft, forest],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct MusliBackground: View {
    var body: some View {
        ZStack {
            MusliTheme.paper.ignoresSafeArea()
            RadialGradient(
                colors: [MusliTheme.honey.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [MusliTheme.forest.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}

struct StatusPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MusliTheme.inkMuted)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(MusliTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MusliTheme.card, in: Capsule())
    }
}

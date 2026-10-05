import SwiftUI
import ReplayKit

/// A cereal bowl that wobbles and ripples while capturing.
/// The real `RPSystemBroadcastPickerView` sits on top as an invisible tap target.
struct BroadcastBowlButton: View {
    var isLive: Bool

    var body: some View {
        ZStack {
            if isLive {
                ripples
            }

            Circle()
                .fill(isLive ? MusliTheme.leafWash : MusliTheme.oat)
                .overlay(Circle().strokeBorder(isLive ? MusliTheme.leaf : MusliTheme.line, lineWidth: 1.5))
                .frame(width: 56, height: 56)

            TimelineView(.animation(paused: !isLive)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Text("🥣")
                    .font(.system(size: 28))
                    .rotationEffect(.degrees(isLive ? sin(t * 3) * 9 : 0))
                    .offset(y: isLive ? sin(t * 6) * 1.5 : 0)
            }

            if isLive {
                Circle()
                    .fill(MusliTheme.berry)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 20, y: -20)
            }

            BroadcastPicker()
                .frame(width: 56, height: 56)
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel(isLive ? "Capturing — tap to stop" : "Start capture")
    }

    private var ripples: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let phase = (t / 1.8 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(MusliTheme.leaf.opacity(0.45 * (1 - phase)), lineWidth: 2)
                        .frame(width: 56, height: 56)
                        .scaleEffect(1 + phase * 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.preferredExtension = "com.granola.iosmeeting.BroadcastExtension"
        picker.showsMicrophoneButton = true
        hideSystemGlyph(picker)
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        hideSystemGlyph(uiView)
    }

    private func hideSystemGlyph(_ picker: RPSystemBroadcastPickerView) {
        picker.backgroundColor = .clear
        for case let button as UIButton in picker.subviews {
            button.setImage(nil, for: .normal)
            button.setImage(nil, for: .highlighted)
            button.setImage(nil, for: .selected)
            button.tintColor = .clear
        }
    }
}

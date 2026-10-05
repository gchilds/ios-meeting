import SwiftUI
import ReplayKit

/// A cereal bowl that wobbles and ripples while capturing.
/// Tapping it fires a hidden `RPSystemBroadcastPickerView`, which presents the system sheet.
struct BroadcastBowlButton: View {
    var isLive: Bool
    @State private var trigger = BroadcastPickerTrigger()

    var body: some View {
        Button {
            trigger.fire()
        } label: {
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
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(BowlPressStyle())
        .background {
            BroadcastPicker(trigger: trigger)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(isLive ? "Capturing — open broadcast controls" : "Start capture")
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

private struct BowlPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

final class BroadcastPickerTrigger {
    weak var picker: RPSystemBroadcastPickerView?

    func fire() {
        guard let picker else { return }
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .allTouchEvents)
        }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    let trigger: BroadcastPickerTrigger

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.granola.iosmeeting.BroadcastExtension"
        picker.showsMicrophoneButton = true
        trigger.picker = picker
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        trigger.picker = uiView
    }
}

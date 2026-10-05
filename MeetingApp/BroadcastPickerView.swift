import SwiftUI
import ReplayKit

/// Styled wrapper around RPSystemBroadcastPickerView — oat card, pulsing ring when live.
struct BroadcastPickerView: View {
    var isLive: Bool

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .stroke(MusliTheme.recordGradient, lineWidth: 3)
                    .frame(width: 76, height: 76)
                    .opacity(0.85)
                    .scaleEffect(isLive ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isLive)
            }

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(MusliTheme.recordGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: MusliTheme.honey.opacity(0.35), radius: 10, y: 4)

                    BroadcastPicker()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                }

                Text(isLive ? "Recording" : "Broadcast")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MusliTheme.ink)
            }
        }
        .accessibilityLabel(isLive ? "Broadcast recording" : "Start broadcast")
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        picker.preferredExtension = "com.granola.iosmeeting.BroadcastExtension"
        picker.showsMicrophoneButton = true
        stylePicker(picker)
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        stylePicker(uiView)
    }

    private func stylePicker(_ picker: RPSystemBroadcastPickerView) {
        picker.backgroundColor = .clear
        for case let button as UIButton in picker.subviews {
            button.tintColor = UIColor.white
            button.setImage(
                UIImage(systemName: "dot.radiowaves.left.and.right")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)),
                for: .normal
            )
        }
    }
}

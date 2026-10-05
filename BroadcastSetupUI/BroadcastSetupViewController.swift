import ReplayKit
import UIKit

/// Minimal Setup UI so the broadcast service is discoverable via
/// RPBroadcastActivityViewController / Control Center flows.
/// RPSystemBroadcastPickerView talks to the Upload extension directly;
/// this companion still helps iOS register the service.
class BroadcastSetupViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Meeting Audio"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textAlignment = .center

        let start = UIButton(type: .system)
        start.setTitle("Start Broadcast", for: .normal)
        start.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        start.addTarget(self, action: #selector(userDidFinishSetup), for: .touchUpInside)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(userDidCancelSetup), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, start, cancel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc func userDidFinishSetup() {
        // URL is unused by sample-buffer upload extensions but required by the API.
        let url = URL(string: "https://granola.com/meeting")!
        extensionContext?.completeRequest(withBroadcast: url, setupInfo: nil)
    }

    @objc func userDidCancelSetup() {
        let error = NSError(
            domain: "MeetingBroadcastSetup",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}

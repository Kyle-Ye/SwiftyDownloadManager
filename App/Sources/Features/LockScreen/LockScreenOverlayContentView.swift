#if os(macOS)
import SwiftUI

@MainActor
final class LockScreenOverlayContentView: NSView {
    init(service: DownloadService) {
        super.init(frame: .zero)

        let hostingView = NSHostingView(
            rootView: LockScreenDownloadsView(service: service)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
#endif

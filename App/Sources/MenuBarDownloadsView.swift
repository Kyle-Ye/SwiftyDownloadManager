import SwiftUI

struct MenuBarDownloadsView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var service: DownloadService

    var body: some View {
        VStack(spacing: 0) {
            MenuBarDownloadList(service: service)

            Divider()
                .padding(.horizontal, 12)

            MenuBarActionRow(
                title: "Open Swifty Download Manager",
                systemImage: "macwindow",
                action: openMainWindow
            )

            Divider()
                .padding(.horizontal, 12)

            MenuBarActionRow(
                title: "Exit",
                systemImage: "power",
                action: exitApplication
            )
        }
        .padding(.vertical, 6)
        .frame(width: 360)
    }

    private func openMainWindow() {
        NSApp.activate()
        openWindow(id: AppWindowID.main)
    }

    private func exitApplication() {
        Task { @MainActor in
            await service.shutdown()
            NSApp.terminate(nil)
        }
    }
}

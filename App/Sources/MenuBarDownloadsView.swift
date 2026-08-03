import SwiftUI

struct MenuBarDownloadsView: View {
    @Environment(\.openWindow) private var openWindow
    let service: DownloadService

    var body: some View {
        VStack(spacing: 0) {
            MenuBarDownloadList(service: service)

            Divider()

            VStack {
                Button(action: openMainWindow) {
                    Label("Open Swifty Download Manager", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Exit", systemImage: "power", action: exitApplication)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .frame(width: 400)
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

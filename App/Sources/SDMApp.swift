import SDMCore
import SwiftUI

@main
struct SDMApp: App {
    @NSApplicationDelegateAdaptor(SDMApplicationDelegate.self)
    private var applicationDelegate
    @State private var downloadService = DownloadService.live()

    var body: some Scene {
        Window("Swifty Download Manager", id: AppWindowID.main) {
            ContentView(service: downloadService)
        }
        .defaultSize(width: 1_080, height: 680)
        .commands {
            DownloadCommands()
        }

        MenuBarExtra(
            "Swifty Download Manager",
            image: "SDMMenuBarIcon"
        ) {
            MenuBarDownloadsView(service: downloadService)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Download Info", for: DownloadID.self) { $downloadID in
            if let downloadID {
                DownloadInfoView(
                    service: downloadService,
                    downloadID: downloadID
                )
            }
        }
        .defaultSize(width: 760, height: 620)

        Settings {
            SettingsView(databaseURL: downloadService.databaseURL)
        }
    }
}

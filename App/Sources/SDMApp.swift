import SDMCore
import SwiftUI

@main
struct SDMApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SDMApplicationDelegate.self)
    private var applicationDelegate
    #else
    @UIApplicationDelegateAdaptor(SDMApplicationDelegate.self)
    private var applicationDelegate
    #endif
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @State private var downloadService = DownloadService.live()

    var body: some Scene {
        #if os(macOS)
        Window("Swifty Download Manager", id: AppWindowID.main) {
            ContentView(service: downloadService)
        }
        .defaultSize(width: 1_080, height: 680)
        .commands {
            DownloadCommands()
            BrowserCommands()
        }

        Window("Browser Extensions", id: AppWindowID.browsers) {
            BrowsersView()
        }
        .defaultSize(width: 760, height: 500)
        .windowResizability(.contentMinSize)

        MenuBarExtra(
            "Swifty Download Manager",
            image: "SDMMenuBarIcon",
            isInserted: $showsMenuBarIcon
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
            SettingsView(service: downloadService)
        }
        #else
        WindowGroup {
            MobileContentView(service: downloadService)
        }
        #endif
    }
}

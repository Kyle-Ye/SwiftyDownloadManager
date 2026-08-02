import SDMCore
import SwiftUI

@main
struct SDMApp: App {
    @State private var downloadService = DownloadService.live()

    var body: some Scene {
        WindowGroup("Swifty Download Manager") {
            ContentView(service: downloadService)
        }
        .defaultSize(width: 1_080, height: 680)

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
            SettingsView()
        }
    }
}

import SwiftUI

@main
struct SDMApp: App {
    @State private var downloadService = DownloadService.live()

    var body: some Scene {
        WindowGroup("Swifty Download Manager") {
            ContentView(service: downloadService)
        }
        .defaultSize(width: 1_080, height: 680)

        Settings {
            SettingsView()
        }
    }
}

import SwiftUI

@main
struct SDMApp: App {
    var body: some Scene {
        WindowGroup("Swifty Download Manager") {
            ContentView()
        }
        .defaultSize(width: 1_080, height: 680)

        Settings {
            SettingsView()
        }
    }
}

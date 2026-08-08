#if os(macOS)
import SwiftUI

struct BrowsersView: View {
    @State private var chromeIsInstalled = false
    @State private var safariExtensionIsEnabled: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Connect a browser to send supported downloads directly to Swifty Download Manager.")
                    .font(.title3)

                ChromeExtensionCard(
                    chromeIsInstalled: chromeIsInstalled,
                    webStoreURL: ChromeExtensionSupport.webStoreURL
                )

                SafariExtensionCard(
                    isEnabled: safariExtensionIsEnabled,
                    openSettings: SafariExtensionSupport.showPreferences
                )
            }
            .padding()
        }
        .task {
            await refreshBrowserStates()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task {
                await refreshBrowserStates()
            }
        }
    }

    private func refreshBrowserStates() async {
        chromeIsInstalled = ChromeExtensionSupport.isChromeInstalled()
        safariExtensionIsEnabled = await SafariExtensionSupport.isEnabled()
    }
}

#Preview {
    BrowsersView()
        .frame(width: 680, height: 520)
}
#endif

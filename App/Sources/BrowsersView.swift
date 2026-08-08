#if os(macOS)
import SwiftUI

struct BrowsersView: View {
    @State private var chromeIsInstalled = false
    @State private var safariExtensionIsEnabled: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserExtensionDesign.sectionSpacing) {
            HStack(spacing: BrowserExtensionDesign.headerSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: BrowserExtensionDesign.headerIconRadius)
                        .fill(Color.accentColor.gradient)

                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(
                    width: BrowserExtensionDesign.headerIconSize,
                    height: BrowserExtensionDesign.headerIconSize
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrowserExtensionDesign.compactSpacing) {
                    Text("Browser Extensions")
                        .font(.title2)
                        .bold()

                    Text("Send supported downloads from your browser straight to SDM.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ChromeExtensionCard(
                chromeIsInstalled: chromeIsInstalled,
                webStoreURL: ChromeExtensionSupport.webStoreURL
            )

            SafariExtensionCard(
                isEnabled: safariExtensionIsEnabled,
                openSettings: SafariExtensionSupport.showPreferences
            )
        }
        .padding(BrowserExtensionDesign.pagePadding)
        .frame(
            minWidth: BrowserExtensionDesign.minimumWindowWidth,
            minHeight: BrowserExtensionDesign.minimumWindowHeight,
            alignment: .topLeading
        )
        .background(Color(nsColor: .windowBackgroundColor))
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
        .frame(width: 760, height: 500)
}
#endif

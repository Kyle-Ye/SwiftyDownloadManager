import Foundation
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
    @State private var downloadService: DownloadService
    private let preparesStoreScreenshots: Bool
    private let storeScreenshotColorScheme: ColorScheme?
    private let storeScreenshotWindowSize: CGSize?
    #if os(macOS)
    private let lockScreenDownloadCoordinator: LockScreenDownloadCoordinator
    #endif

    init() {
        #if DEBUG && os(macOS)
        let storeScreenshotConfiguration = StoreScreenshotConfiguration()
        let preparesStoreScreenshots = storeScreenshotConfiguration.isEnabled
        let storeScreenshotColorScheme = storeScreenshotConfiguration.colorScheme
        let storeScreenshotWindowSize = storeScreenshotConfiguration.windowSize
        #else
        let preparesStoreScreenshots = false
        let storeScreenshotColorScheme: ColorScheme? = nil
        let storeScreenshotWindowSize: CGSize? = nil
        #endif
        self.preparesStoreScreenshots = preparesStoreScreenshots
        self.storeScreenshotColorScheme = storeScreenshotColorScheme
        self.storeScreenshotWindowSize = storeScreenshotWindowSize

        #if DEBUG
        if preparesStoreScreenshots {
            let service = DownloadService.preview(
                snapshots: DownloadPreviewFixtures.storeScreenshotSnapshots,
                destinationDirectory: URL(filePath: "/Downloads")
            )
            _downloadService = State(initialValue: service)
            #if os(macOS)
            lockScreenDownloadCoordinator = LockScreenDownloadCoordinator(
                service: service
            )
            #endif
            return
        }
        #endif
        let service = DownloadService.live()
        _downloadService = State(initialValue: service)
        #if os(macOS)
        lockScreenDownloadCoordinator = LockScreenDownloadCoordinator(
            service: service
        )
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window("Swifty Download Manager", id: AppWindowID.main) {
            ContentView(service: downloadService)
                .preferredColorScheme(storeScreenshotColorScheme)
                .frame(
                    width: storeScreenshotWindowSize?.width,
                    height: storeScreenshotWindowSize?.height
                )
        }
        .defaultSize(
            width: storeScreenshotWindowSize?.width ?? 1_080,
            height: storeScreenshotWindowSize?.height ?? 680
        )
        .windowResizability(
            preparesStoreScreenshots ? .contentSize : .automatic
        )
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

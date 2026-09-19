// swift-tools-version: 6.0
import PackageDescription

// The app and Safari extension compile these sources directly. This package
// tests their private transport independently of app signing and UI lifecycle.
let package = Package(
    name: "SDMBrowserHandoff",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(name: "SDMBrowserHandoff", path: ".", exclude: ["Shared", "Tests"],
                sources: ["Native", "ChromeNative"]),
        .testTarget(name: "SDMBrowserHandoffTests", dependencies: ["SDMBrowserHandoff"], path: "Tests/Native"),
    ]
)

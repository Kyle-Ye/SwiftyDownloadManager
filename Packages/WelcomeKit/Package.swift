// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WelcomeKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WelcomeKit", type: .static, targets: ["WelcomeKit"]),
    ],
    targets: [
        .target(
            name: "WelcomeKit",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "WelcomeKitTests", dependencies: ["WelcomeKit"]),
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SDMCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SDMCore",
            type: .static,
            targets: ["SDMCore"]
        ),
    ],
    dependencies: [
        .package(path: "../CurlBinary"),
    ],
    targets: [
        .target(
            name: "SDMEngine",
            dependencies: [
                .product(name: "CurlBinary", package: "CurlBinary"),
            ],
            path: "Sources/SDMEngine",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z"),
                .linkedLibrary("ldap", .when(platforms: [.macOS])),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "SDMEngineBridge",
            dependencies: ["SDMEngine"],
            path: "Sources/SDMEngineBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "SDMCore",
            dependencies: ["SDMEngineBridge"],
            path: "Sources/SDMCore",
            resources: [
                .copy("Resources/cacert.pem"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "SDMEngineTestSupport",
            dependencies: ["SDMEngine"],
            path: "Tests/SDMEngineTestSupport",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "SDMCoreTests",
            dependencies: ["SDMCore", "SDMEngineTestSupport"],
            path: "Tests/SDMCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)

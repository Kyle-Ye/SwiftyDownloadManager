// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SDMCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SDMCore",
            type: .static,
            targets: ["SDMCore"]
        ),
    ],
    targets: [
        .target(
            name: "SDMEngine",
            path: "Sources/SDMEngine",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("curl"),
                .linkedLibrary("sqlite3"),
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
            path: "Sources/SDMCore"
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

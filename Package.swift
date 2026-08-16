// swift-tools-version: 6.0

import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "SDMCore": .staticFramework,
    ],
    targetSettings: [
        "SDMCore": .settings(base: [
            "PRODUCT_BUNDLE_IDENTIFIER": "top.kyleye.swifty-download-manager",
        ]),
    ]
)
#endif

let package = Package(
    name: "SDMDependencies",
    dependencies: [
        .package(
            url: "https://github.com/LookInsideApp/LookInside-Release.git",
            exact: "0.2.7"
        ),
        .package(
            url: "https://github.com/Lakr233/SkyLightWindow.git",
            exact: "1.0.0"
        ),
        .package(path: "Packages/SDMCore"),
    ]
)

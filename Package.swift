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
        .package(path: "Packages/SDMCore"),
    ]
)

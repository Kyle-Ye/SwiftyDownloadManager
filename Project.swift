import ProjectDescription

let project = Project(
    name: "SDM",
    settings: .settings(
        base: [
            "CLANG_CXX_LANGUAGE_STANDARD": "c++20",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_VERSION": "6.0",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "SDMApp",
            destinations: .macOS,
            product: .app,
            bundleId: "top.kyleye.swifty-download-manager-app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": "Swifty Download Manager",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
                "NSPrincipalClass": "NSApplication",
            ]),
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            entitlements: .file(path: "App/Support/SDMApp.entitlements"),
            dependencies: [
                .external(name: "SDMCore"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "PRODUCT_NAME": "SDMApp",
            ]),
            metadata: .metadata(tags: [
                "tag:feature:downloads",
                "tag:layer:ui",
            ])
        ),
        .target(
            name: "SDMAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "top.kyleye.swifty-download-manager-app-tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: ["App/Tests"],
            dependencies: [
                .target(name: "SDMApp"),
            ],
            metadata: .metadata(tags: [
                "tag:feature:downloads",
                "tag:layer:tests",
            ])
        ),
    ]
)

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
                "CFBundleURLTypes": [
                    [
                        "CFBundleTypeRole": "Editor",
                        "CFBundleURLName": "top.kyleye.swifty-download-manager.download",
                        "CFBundleURLSchemes": ["swifty-download-manager"],
                    ],
                ],
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
                .target(name: "SDMSafariExtension"),
                .external(name: "SDMCore"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "EXECUTABLE_NAME": "SDMApp",
                "PRODUCT_MODULE_NAME": "SDMApp",
                "PRODUCT_NAME": "Swifty Download Manager",
            ]),
            metadata: .metadata(tags: [
                "tag:feature:downloads",
                "tag:layer:ui",
            ])
        ),
        .target(
            name: "SDMSafariExtension",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "top.kyleye.swifty-download-manager-app.safari-extension",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": "Swifty Download Manager Extension",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "XPC!",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
                ],
            ]),
            buildableFolders: [
                "SafariExtension/Sources",
                "SafariExtension/Resources",
            ],
            entitlements: .file(path: "SafariExtension/Support/SDMSafariExtension.entitlements"),
            settings: .settings(base: [
                "APPLICATION_EXTENSION_API_ONLY": "YES",
                "CODE_SIGN_STYLE": "Automatic",
                "PRODUCT_NAME": "Swifty Download Manager Extension",
                "SKIP_INSTALL": "YES",
            ]),
            metadata: .metadata(tags: [
                "tag:feature:browser-extension",
                "tag:layer:integration",
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

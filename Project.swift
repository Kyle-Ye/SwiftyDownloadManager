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
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "top.kyleye.swifty-download-manager-app",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                "CFBundleDisplayName": "Swifty Download Manager",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.3.0",
                "CFBundleURLTypes": [
                    [
                        "CFBundleTypeRole": "Editor",
                        "CFBundleURLName": "top.kyleye.swifty-download-manager.download",
                        "CFBundleURLSchemes": ["swifty-download-manager"],
                    ],
                ],
                "CFBundleVersion": "4",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "LSSupportsOpeningDocumentsInPlace": true,
                "NSAppTransportSecurity": [
                    "NSAllowsArbitraryLoads": true,
                ],
                "UIFileSharingEnabled": true,
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
            ]),
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: [
                .target(name: "SDMSafariExtension"),
                .external(name: "SDMCore"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "App/Support/SDMApp.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "App/Support/SDMApp-iOS.entitlements",
                "DEVELOPMENT_TEAM": "VB7MJ8R223",
                "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
                "EXECUTABLE_NAME": "SDMApp",
                "PRODUCT_MODULE_NAME": "SDMApp",
                "PRODUCT_NAME": "Swifty Download Manager",
                "TARGETED_DEVICE_FAMILY[sdk=iphone*]": "1,2",
            ], configurations: [
                .debug(name: "Debug", settings: [
                    "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Development",
                    "CODE_SIGN_STYLE": "Automatic",
                ]),
                .release(name: "Release", settings: [
                    "CODE_SIGN_IDENTITY[sdk=macosx*]": "Developer ID Application",
                    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS[sdk=macosx*]": "NO",
                    "CODE_SIGN_STYLE[sdk=iphoneos*]": "Automatic",
                    "CODE_SIGN_STYLE[sdk=macosx*]": "Manual",
                ]),
            ]),
            metadata: .metadata(tags: [
                "tag:feature:downloads",
                "tag:layer:ui",
            ])
        ),
        .target(
            name: "SDMSafariExtension",
            destinations: [.iPhone, .iPad, .mac],
            product: .appExtension,
            bundleId: "top.kyleye.swifty-download-manager-app.safari-extension",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                "CFBundleDisplayName": "Swifty Download Manager Extension",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "XPC!",
                "CFBundleShortVersionString": "0.3.0",
                "CFBundleVersion": "4",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
                ],
            ]),
            resources: [
                .folderReference(path: "BrowserExtension/Shared"),
            ],
            buildableFolders: [
                "SafariExtension/Sources",
                "SafariExtension/Resources",
            ],
            settings: .settings(base: [
                "APPLICATION_EXTENSION_API_ONLY": "YES",
                "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "SafariExtension/Support/SDMSafariExtension.entitlements",
                "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "SafariExtension/Support/SDMSafariExtension-iOS.entitlements",
                "DEVELOPMENT_TEAM": "VB7MJ8R223",
                "ENABLE_HARDENED_RUNTIME[sdk=macosx*]": "YES",
                "PRODUCT_NAME": "Swifty Download Manager Extension",
                "SKIP_INSTALL": "YES",
                "TARGETED_DEVICE_FAMILY[sdk=iphone*]": "1,2",
            ], configurations: [
                .debug(name: "Debug", settings: [
                    "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Development",
                    "CODE_SIGN_STYLE": "Automatic",
                ]),
                .release(name: "Release", settings: [
                    "CODE_SIGN_IDENTITY[sdk=macosx*]": "Developer ID Application",
                    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS[sdk=macosx*]": "NO",
                    "CODE_SIGN_STYLE[sdk=iphoneos*]": "Automatic",
                    "CODE_SIGN_STYLE[sdk=macosx*]": "Manual",
                ]),
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
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "Apple Development",
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "VB7MJ8R223",
            ]),
            metadata: .metadata(tags: [
                "tag:feature:downloads",
                "tag:layer:tests",
            ])
        ),
    ]
)

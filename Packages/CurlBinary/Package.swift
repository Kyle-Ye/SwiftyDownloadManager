// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CurlBinary",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CurlBinary", targets: ["curl"]),
    ],
    targets: [
        .binaryTarget(
            name: "curl",
            url: "https://github.com/greatfire/curl-apple/releases/download/8.21.0/curl.xcframework.zip",
            checksum: "56bee7fbef0051707c5b3b4f129f703092df61005da371b9c8a3bd0450a0ae88"
        ),
    ]
)

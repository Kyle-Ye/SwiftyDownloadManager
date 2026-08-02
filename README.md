# Swifty Download Manager

Swifty Download Manager (SDM) is a native macOS multi-connection download
manager. The application UI is built with Swift and SwiftUI. Its download
engine is implemented in C++ and distributed to the app through a local
SwiftPM package and a Tuist-generated Xcode project.

The repository is under active development. The M0 repository and build
bootstrap is complete; M1 will define the engine lifecycle contracts and
consume the local HTTP range fixture. Project planning is maintained outside
the application repository in the surrounding workspace.

## Build

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
xcodebuild build \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64'
```

The core package can be verified independently:

```bash
swift test --package-path Packages/SDMCore
```

## Local HTTP fixture

Run the threaded Range server used by download-engine integration tests:

```bash
python3 Fixture/range_server.py
```

It serves a 1 KiB zero-filled file at
`http://127.0.0.1:8080/1kb-zero.bin` and limits each connection to 20 B/s.
See [`Fixture/README.md`](Fixture/README.md) for supported Range behavior and
test commands.

## Naming

- Product: `Swifty Download Manager`
- Short name and internal code name: `SDM`
- App target: `SDMApp`
- SwiftPM package and product: `SDMCore`
- C++ target: `SDMEngine`
- Framework bundle identifier: `top.kyleye.swifty-download-manager`
- App bundle identifier: `top.kyleye.swifty-download-manager-app`

## Reference material

The locally supplied NDM application and screenshots are research inputs only.
They are intentionally excluded from Git and must not be copied into SDM or its
distributed artifacts.

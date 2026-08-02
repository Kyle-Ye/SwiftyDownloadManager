# Swifty Download Manager

Swifty Download Manager (SDM) is a native macOS multi-connection download
manager. The application UI is built with Swift and SwiftUI. Its download
engine is implemented in C++ and distributed to the app through a local
SwiftPM package and a Tuist-generated Xcode project.

The core download stack now supports HTTP probing, single and segmented Range
transfers, pause/resume/cancel/retry, bounded scheduling and bandwidth,
SQLite-backed recovery, and atomic file finalization. The SwiftUI application
uses `DownloadService` to enqueue direct URLs, observe engine snapshots, show
filterable progress and status, and issue pause, resume, cancel, retry, and
remove commands. Project planning is maintained outside the application
repository in the surrounding workspace.

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

Run the complete local validation suite:

```bash
bash Scripts/test.sh
```

Swift integration tests start isolated Fixture processes on ephemeral loopback
ports and clean them up automatically.

## Local HTTP fixture

Run the threaded Range server used by download-engine integration tests:

```bash
python3 Fixture/range_server.py
```

It serves a configurable virtual file at
`http://127.0.0.1:8080/empty.bin`. See [`Fixture/README.md`](Fixture/README.md)
for configuration, Range behavior, and test commands.

## SDMCore

Applications import only `SDMCore`; C++, libcurl, SQLite, worker threads, and
file descriptors remain behind its C ABI. See [`Docs/SDMCore.md`](Docs/SDMCore.md)
for lifecycle and integration guidance.

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

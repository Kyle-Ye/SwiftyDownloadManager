# Swifty Download Manager

Swifty Download Manager (SDM) is a native macOS, iOS, and iPadOS download
manager. The application UI is built with Swift and SwiftUI. Its download
stack offers a C++/libcurl engine and a native URLSession engine behind one
Swift API, distributed through local SwiftPM packages and a Tuist-generated
Xcode project.

The core download stack now supports HTTP probing, single and adaptively
segmented Range transfers, pause/resume/cancel/retry, bounded scheduling and
bandwidth, SQLite-backed recovery, and atomic file finalization. Idle
connections split the largest eligible remaining Range so uneven transfers do
not leave available connection capacity unused. The SwiftUI application
uses `DownloadService` to enqueue direct URLs, observe engine snapshots, show
filterable progress and status, and issue pause, resume, cancel, retry, and
remove commands. Every task can open a live Info window with transfer metadata,
per-Range progress, lifecycle controls, and a bounded persistent activity
history. Project planning is maintained outside the application repository in
the surrounding workspace.

## Download engines

Choose the default engine in Settings. Switching affects new downloads only;
existing tasks remain attached to the engine that created them.

| Capability | libcurl | URLSession |
| --- | --- | --- |
| Adaptive multi-connection Range transfers | Yes | No |
| Per-download bandwidth limit | Yes | No |
| Persistent recovery | Yes | Yes |
| Native background transfer | No | Yes |
| Certificate trust | Apple roots on macOS; audited CA bundle on iOS | Apple system trust |

Unsupported combinations return `DownloadErrorCode.unsupportedFeature` instead
of silently changing behavior. The app automatically uses one connection when
URLSession is selected.

## Download history

The libcurl engine stores tasks, segment checkpoints, lifecycle timestamps, and
diagnostics in SQLite. URLSession keeps its state and opaque resume data in a
separate JSON store. The manager merges both histories for the UI. All state is
stored below the sandboxed app's Application Support container.

Completed, failed, cancelled, and paused tasks remain until the user chooses
**Remove from History**. Removing history also removes partial data and
diagnostics, but never deletes a finalized file. **Delete Downloaded File** is a
separate confirmed action. Finalized downloads stay in Downloads or another
user-selected directory, and security-scoped bookmarks preserve access to
custom destinations across launches. Select multiple rows on macOS, or tap
**Edit** on iOS and iPadOS, to remove several eligible tasks from history at
once.

## Build

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
xcodebuild build \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64'

xcodebuild build \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'generic/platform=iOS Simulator'
```

Run the complete local validation suite:

```bash
bash Scripts/test.sh
```

Swift integration tests start isolated Fixture processes on ephemeral loopback
ports and clean them up automatically.

See [`Docs/Releasing.md`](Docs/Releasing.md) for the versioning, validation,
archive, App packaging, GitHub Release, and post-release development workflow.

## LookInside

Debug builds embed the
[`LookInsideServer`](https://github.com/LookInsideApp/LookInside-Release)
package so the running macOS or iOS app can be inspected from LookInside.
Install dependencies, generate the workspace, and run the `SDMApp` scheme in
the Debug configuration. The app then appears in LookInside's connection list.

The server binary is excluded from Release builds. Keep any future direct
`LookInsideServer` API calls behind `#if DEBUG` guards.

To resolve private Swift type discriminators, open **Private Discriminator
Settings…** in LookInside, import module `SDMApp`, and select `App/Sources` as
its source folder. LookInside indexes filenames locally without uploading the
source files.

## Browser extensions

The macOS app provides a **Browser Extensions…** window for setting up Google
Chrome and Safari. The Chrome integration is a separate Manifest V3 extension
prepared for Chrome Web Store distribution. It recognizes common direct file
links, eligible downloads opened after a click, and the **Download with SDM**
link context-menu command. See [`Docs/ChromeExtension.md`](Docs/ChromeExtension.md)
for local installation, packaging, permissions, and store-publishing steps.
Chrome and Safari use the same browser-independent interception and download
recognition sources under `BrowserExtension/Shared`; only their platform
adapters and manifests are maintained separately.

The Chrome extension is macOS-only. Its in-app **Add Chrome Extension** button
opens the Chrome Web Store search until the listing receives its permanent item
ID, at which point the centralized URL can be changed to the direct listing.

### Safari

The macOS, iOS, and iPadOS apps embed a Safari Web Extension that sends direct HTTP and HTTPS
download links to SDM. Run the containing app once, open **Settings > Safari
Extension**, enable it in Safari, and grant access to the websites where it
should operate. Links with a `download` attribute, common downloadable file
extensions, and downloadable URLs opened programmatically after a click are
captured automatically. Use **Download with SDM** from Safari's link context
menu for download endpoints without a recognizable filename.

Holding a modifier key while clicking bypasses SDM and preserves Safari's
normal link handling. This first version forwards direct GET URLs and suggested
filenames; authenticated requests that depend on browser-only cookies or custom
headers are not yet transferred.

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

The pinned libcurl binary and all redistribution notices are documented in
[`Docs/ThirdPartyLicensing.md`](Docs/ThirdPartyLicensing.md).

## Naming

- Product: `Swifty Download Manager`
- Short name and internal code name: `SDM`
- App target: `SDMApp`
- SwiftPM package and product: `SDMCore`
- C++ target: `SDMEngine`
- Framework bundle identifier: `top.kyleye.swifty-download-manager`
- App bundle identifier: `top.kyleye.swifty-download-manager-app`

## License

The source code and documentation in this repository are available under the
[Functional Source License, Version 1.1, MIT Future License](LICENSE.md). You
may use, study, modify, and redistribute the Software for any permitted purpose,
but may not offer it as a competing commercial product or service. Each version
automatically becomes available under the MIT License two years after it is
made available.

This is a Fair Source license; a version becomes Open Source when its future MIT
license takes effect. The Swifty Download Manager name, icons, and visual assets
are excluded from the Software license as described in [`BRANDING.md`](BRANDING.md).
Official App Store builds may be distributed under separate end-user terms.

Contributions are accepted under the terms in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Reference material

The locally supplied NDM application and screenshots are research inputs only.
They are intentionally excluded from Git and must not be copied into SDM or its
distributed artifacts.

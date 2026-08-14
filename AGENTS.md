# Swifty Download Manager repository instructions

## Repository boundaries

- This directory is the standalone SDM Git repository. Do not include files
  from the surrounding Mono workspace in SDM commits or release artifacts.
- Project planning lives in the parent workspace's `PLANS/` directory.
- Store-submission-only assets live in the parent workspace's `Resources/`
  directory.
- Keep `README.md` user-facing. Put agent instructions and local development
  details in this file instead.

## Build and validation

Install the pinned tools, generate the workspace, and run the complete local
validation suite:

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
bash Scripts/test.sh
```

Representative builds:

```bash
xcodebuild build \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64'

xcodebuild build \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'generic/platform=iOS Simulator'
```

Swift integration tests start isolated Fixture processes on ephemeral loopback
ports and clean them up automatically. The Range fixture can also be started
manually with `python3 Fixture/range_server.py`; see `Fixture/README.md` for its
configuration and test commands.

## Architecture and naming

- Product: `Swifty Download Manager`
- Short name and internal code name: `SDM`
- App target: `SDMApp`
- SwiftPM package and product: `SDMCore`
- C++ target: `SDMEngine`
- Framework bundle identifier: `top.kyleye.swifty-download-manager`
- App bundle identifier: `top.kyleye.swifty-download-manager-app`

Applications import only `SDMCore`; C++, libcurl, SQLite, worker threads, and
file descriptors remain behind its C ABI. Read `Docs/SDMCore.md` before
changing the lifecycle or public integration surface. Redistribution notices
and the pinned libcurl binary are documented in
`Docs/ThirdPartyLicensing.md`.

The Chrome and Safari extensions share browser-independent interception and
download-recognition code in `BrowserExtension/Shared`. Keep platform adapters
and manifests separate. See `Docs/ChromeExtension.md` before changing extension
permissions, packaging, or store metadata.

## LookInside

Debug builds embed `LookInsideServer`; Release builds must not include it. Keep
future direct `LookInsideServer` API calls behind `#if DEBUG` guards.

To resolve private Swift type discriminators, open **Private Discriminator
Settings…** in LookInside, import module `SDMApp`, and select `App/Sources` as
the source folder. LookInside indexes filenames locally without uploading
source files.

## Releasing

Follow `Docs/Releasing.md` for versioning, validation, release branches, Xcode
Cloud archives, notarization, tags, and GitHub Release artifacts. Do not place
store-submission-only assets in this repository.

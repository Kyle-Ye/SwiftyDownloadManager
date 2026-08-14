# Swifty Download Manager

Swifty Download Manager (SDM) is a native download manager for macOS, iOS,
and iPadOS. It supports resumable direct HTTP and HTTPS downloads, detailed
transfer progress, persistent history, and browser handoff from Safari and
Chrome.

## Features

- Pause, resume, cancel, retry, and remove downloads.
- Adaptive multi-connection downloads with per-download bandwidth limits.
- Native background transfers through URLSession.
- Persistent recovery and download history across launches.
- Live transfer details, per-range progress, and activity history.
- Custom download destinations with sandbox-safe access.
- Multi-select history management on macOS, iOS, and iPadOS.
- Safari integration on every supported platform and Chrome integration on
  macOS.
- No account, advertising, analytics, or telemetry.

SDM is designed for direct file URLs. Downloads that require browser-only
cookies, authenticated sessions, request bodies, or custom request headers are
not currently supported.

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

The app automatically uses one connection when URLSession is selected.

## Download history

Completed, failed, cancelled, and paused tasks remain until you choose
**Remove from History**. Removing history also removes partial data and
diagnostics, but never deletes a finalized file. **Delete Downloaded File** is
a separate confirmed action.

Finalized downloads stay in Downloads or another selected directory. Select
multiple rows on macOS, or tap **Edit** on iOS and iPadOS, to remove several
eligible tasks from history at once.

## Browser extensions

The Safari extension is included with the macOS, iOS, and iPadOS apps. Open
**Settings > Safari Extension**, enable it in Safari, and grant access to the
websites where it should operate. Use **Download with SDM** from a link's
context menu when a download endpoint does not expose a recognizable filename.

On macOS, the companion extension for Google Chrome is available from the
[Chrome Web Store](https://chromewebstore.google.com/detail/jjhjgmnpneldikhkejhoeonjpbbekbpg).
It can hand supported direct download links to the locally installed app.

Holding a modifier key while clicking in Safari bypasses SDM and preserves the
browser's normal link handling.

## Build from source

Install the pinned tools and generate the Xcode workspace:

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
```

Build the app for macOS or the iOS Simulator:

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

Run the complete local validation suite:

```bash
bash Scripts/test.sh
```

## Documentation

- [Browser extension development and packaging](Docs/ChromeExtension.md)
- [SDMCore lifecycle and integration](Docs/SDMCore.md)
- [Release process](Docs/Releasing.md)
- [Third-party licensing](Docs/ThirdPartyLicensing.md)
- [Contributing](CONTRIBUTING.md)

## License

The source code and documentation in this repository are available under the
[Functional Source License, Version 1.1, MIT Future License](LICENSE.md). You
may use, study, modify, and redistribute the software for any permitted
purpose, but may not offer it as a competing commercial product or service.
Each version automatically becomes available under the MIT License two years
after it is made available.

The Swifty Download Manager name, icons, and visual assets are excluded from
the software license as described in [BRANDING.md](BRANDING.md). Official App
Store builds may be distributed under separate end-user terms.

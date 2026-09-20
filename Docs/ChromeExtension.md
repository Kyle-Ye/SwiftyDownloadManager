# Chrome extension

SDM includes a macOS-only Google Chrome integration. Its Manifest V3 adapter is
under `ChromeExtension/Resources`, while browser-independent interception code
lives in `BrowserExtension/Shared` and is also bundled into the Safari Web
Extension. The iOS and iPadOS apps continue to expose only Safari.

The shared layer owns download URL recognition, click and `window.open`
interception, callback URL construction, the confirmation page, and the common
background controller. The small Safari and Chrome adapters provide their
manifest format, toolbar API, message-listener behavior, and native-app fallback.

## How it works

The extension recognizes common direct-download URL extensions, links carrying
the `download` attribute, and eligible `window.open` calls that immediately
follow a user click. It also adds **Download with SDM** to HTTP and HTTPS link
context menus. Recognized requests collect URL-scoped browser cookies, the browser
User-Agent, and an origin-only Referer in the background worker. Ordinary
anchors, `window.open`, context-menu actions, and the direct-navigation
confirmation page all use this path. Cookie access failure returns the download
to the browser instead of silently creating an anonymous SDM task.

Chrome activates the app through `swifty-download-manager://handoff` with a
random UUID and one-use AES-256-GCM key. The background worker sends the encrypted
payload separately to `ws://127.0.0.1:10027` with subprotocol `sdm.handoff.v1`.
Only the activated app has the key to decrypt it and produce the authenticated
receipt. Retries of the same handoff receive the same result without creating
another download. The listener binds only to IPv4 loopback, requires an extension
Origin and the expected subprotocol, bounds message sizes, and expires tickets
after 60 seconds. Keys and payloads never enter page DOM or extension storage.
The Release app needs `com.apple.security.network.server` for this listener.

Safari collects the same request context and uses native messaging to stage an
encrypted, short-lived file in a shared App Group: macOS uses
`VB7MJ8R223.top.kyleye.swifty-download-manager`, and iOS uses
`group.top.kyleye.swifty-download-manager`. Its key and UUID travel separately
through OS app activation; the app consumes and deletes the ciphertext. Expired
files are rejected and pruned on subsequent use. iOS also protects staging files
with complete file protection. On macOS both targets must be signed by team
`VB7MJ8R223`; macOS authorizes the team-prefixed group through that signature
without a provisioning profile. On iOS both targets need profiles authorizing
the registered group. `REGISTER_APP_GROUPS` is enabled for automatic signing. See Apple's
[App Group provisioning guidance](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

Both download engines use the context only in memory. Cookie domain, host-only,
path, Secure and expiration rules apply on redirects; an HTTPS browser download
cannot redirect to HTTP. Browser-profile stores and partition keys are queried
when their APIs are available. No other browser's cookie store is consulted.
HTML returned for a known binary filename is reported as an error, while
intentional HTML downloads remain supported.

Keep SDM running for browser-session downloads. URLSession uses an ephemeral
foreground session for these tasks; continuing a paused browser task with
URLSession starts a fresh GET so an opaque resume blob cannot replay expired
cookies. Public URLSession tasks retain background transfers and opaque resume
support. After restarting SDM, send a browser-session task again from the signed-in
browser. POST bodies and arbitrary Authorization/custom headers remain unsupported.
Users can hold a modifier key while clicking to preserve normal browser behavior.

## Local development

First assemble a self-contained unpacked extension from the adapter and shared
sources:

```bash
Scripts/prepare-chrome-extension.sh
```

Then:

1. Open `chrome://extensions` in Google Chrome.
2. Enable **Developer mode**.
3. Choose **Load unpacked**.
4. Select `Derived/ChromeExtension`.
5. Run the macOS SDM app before testing a download.

`Derived/ChromeExtension` is generated and ignored by Git. Running the prepare
script again safely replaces this default output. Passing an explicit output
path requires that path not to exist, preventing accidental data removal.

The manifest requires Chrome 111 or later because `page.js` runs in the page's
`MAIN` execution world. The package requests `contextMenus`, `webNavigation`, `cookies`, and HTTP/HTTPS
host access. It does not install a Chrome Native Messaging Host or request
`downloads`/`webRequest` permissions. Safari additionally uses `nativeMessaging`.

Run its tests directly:

```bash
node --test ChromeExtension/Tests/ChromeExtensionTests.js
```

## Build the Chrome Web Store ZIP

Use the checked-in packager so the manifest remains at the archive root:

```bash
SDM_VERSION="$(plutil -extract version raw -o - \
  ChromeExtension/Resources/manifest.json)"
Scripts/package-chrome-extension.sh \
  "Artifacts/SwiftyDownloadManager-Chrome-${SDM_VERSION}.zip"
```

The default output is
`Artifacts/SwiftyDownloadManager-Chrome.zip`. An explicit output path can be
passed as the first argument.

The packager assembles the Chrome adapter and canonical shared sources in a
temporary directory, then creates a ZIP containing only runtime resources and
PNG icons. Chrome does not support SVG files for manifest icons, so the package
includes 16, 32, 48, and 128 pixel PNG variants.

Regenerate the small promotional tile after changing the app icon or its source
layout:

```bash
node ../Resources/ChromeWebStore/generate-small-promo.mjs
```

The script uses the website workspace's pinned `sharp` dependency and composites
the canonical app icon without redrawing it.

## Publish to the Chrome Web Store

Chrome supports direct consumer installation on macOS through the Chrome Web
Store. Follow the official
[publishing guide](https://developer.chrome.com/docs/webstore/publish) after
registering a developer account:

1. Build and upload the ZIP as a new draft item.
2. Copy the reviewed listing text, permission justifications, privacy fields,
   and distribution answers from `../Resources/ChromeWebStore/Submission.md`.
3. Upload `../Resources/ChromeWebStore/Assets/small-promo-440x280.png` and
   `../Resources/ChromeWebStore/Assets/screenshot-download-confirmation-1280x800.png`.
   The 128-pixel store icon is already included in the ZIP manifest.
4. Disclose that download URLs, URL-scoped cookies, browser User-Agent, and source
   origins are processed locally and passed to the SDM app to reproduce the
   selected download. Update cookie-permission justifications and privacy
   disclosures before publishing; no data is sent to a developer-operated service.
5. Confirm the public privacy page matches those disclosures, then submit the
   draft for review and publish it after approval.
6. Confirm `ChromeExtensionSupport.webStoreURL` still uses the assigned item
   URL:
   `https://chromewebstore.google.com/detail/jjhjgmnpneldikhkejhoeonjpbbekbpg`.

The Web Store assigns the item ID when the first draft is uploaded. After that,
the public key can be copied into the manifest's `key` field when a stable ID is
needed for unpacked development builds. Do not commit a private packaging key.

The Chrome manifest version must match the App and Safari extension marketing
version in every stable release. `Docs/Releasing.md` and the release workflow
validate this invariant.

Chrome Web Store policy treats locally processed page and download URLs as user
data that must be disclosed even when the developer never receives them. Keep
the store Privacy tab and the public privacy statement synchronized with actual
extension behavior. Re-review both before any permission or interception change.

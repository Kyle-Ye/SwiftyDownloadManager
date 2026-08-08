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
context menus. Recognized requests are handed to the macOS app through its
`swifty-download-manager://` callback URL.

The callback avoids installing a Chrome Native Messaging Host outside the app
sandbox. Chrome requires a native host manifest in a browser-specific location
under `/Library` or the user's Library, plus an exact extension origin. That
installation model is unnecessary for the direct public GET URLs currently
supported by SDM. See Chrome's
[Native Messaging documentation](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
for the additional requirements if the integration later needs bidirectional
or cookie-aware communication.

Authenticated downloads that require browser-only cookies, request bodies, or
custom headers are not transferred yet. Users can hold a modifier key while
clicking to preserve Chrome's normal behavior.

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
`MAIN` execution world. The package requests only `contextMenus`,
`webNavigation`, and HTTP/HTTPS host access. It deliberately does not request
`nativeMessaging` or `downloads`.

Run its tests directly:

```bash
node --test ChromeExtension/Tests/ChromeExtensionTests.js
```

## Build the Chrome Web Store ZIP

Use the checked-in packager so the manifest remains at the archive root:

```bash
Scripts/package-chrome-extension.sh
```

The default output is
`Artifacts/SwiftyDownloadManager-Chrome.zip`. An explicit output path can be
passed as the first argument.

The packager assembles the Chrome adapter and canonical shared sources in a
temporary directory, then creates a ZIP containing only runtime resources and
PNG icons. Chrome does not support SVG files for manifest icons, so the package
includes 16, 32, 48, and 128 pixel PNG variants.

## Publish to the Chrome Web Store

Chrome supports direct consumer installation on macOS through the Chrome Web
Store. Follow the official
[publishing guide](https://developer.chrome.com/docs/webstore/publish) after
registering a developer account:

1. Build and upload the ZIP as a new draft item.
2. Complete the store description, permission justifications, privacy fields,
   icon, promotional image, and at least one screenshot.
3. Disclose that page/download URLs are processed locally and passed to the SDM
   app, and that SDM does not send them to a developer-operated service.
4. Submit the draft for review and publish it after approval.
5. Replace the search URL in `ChromeExtensionSupport.webStoreURL` with the
   final listing URL:
   `https://chromewebstore.google.com/detail/swifty-download-manager/ITEM_ID`.

The Web Store assigns the item ID when the first draft is uploaded. After that,
the public key can be copied into the manifest's `key` field when a stable ID is
needed for unpacked development builds. Do not commit a private packaging key.

The Chrome manifest version must match the App and Safari extension marketing
version in every stable release. `Docs/Releasing.md` and the release workflow
validate this invariant.

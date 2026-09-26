# Chrome extension

SDM includes a macOS-only Google Chrome integration. Its Manifest V3 adapter is
under `ChromeExtension/Resources`, while browser-independent interception code
lives in `BrowserExtension/Shared` and is also bundled into the Safari Web
Extension. The iOS and iPadOS apps continue to expose only Safari.

The shared layer owns download URL recognition, click and `window.open`
interception, callback URL construction, the confirmation page, and the common
background controller. The small Safari and Chrome adapters provide their
manifest format, toolbar API, message-listener behavior, and native-app fallback.

`page.js` runs alone in the page's MAIN world. It receives the canonical candidate
extension list as plain data in the isolated content script's bridge initialization
message; it must not depend on `SDMDownloadSupport` existing in the page world.
Until initialization completes, `window.open` keeps its native behavior. The
isolated script independently validates every bridged download request.

## How it works

By default, the extension leaves ordinary navigation and inline formats such as text, PDF,
images, and media to the browser. Archive and installer filename extensions are
only candidates: a credentialed HEAD request must return a successful attachment
response or a known binary download MIME type before automatic handoff or a
download prompt. HTML previews, explicit inline responses, unknown MIME types,
failed checks, and endpoints without HEAD support continue in the browser.
The HEAD check times out after three seconds and never fetches the response body.
HEAD and GET can differ on some servers; this is a conservative preflight, not a
browser download event listener. Endpoints outside these candidates can still be
sent explicitly using **Download with SDM** in the link context menu.

## File-type settings

The extension owns these preferences because it decides which browser navigation
to intercept. Chrome and Safari share the same options page and rule evaluator.
The native app continues to own download engines and destinations, and does not
need to be running to edit interception preferences. Settings are local to each
browser profile; they are not synchronized through the app or across browsers.
Safari also runs a separate extension instance and storage for each profile, as
described in [WebKit's Safari 17 profile documentation](https://webkit.org/blog/14445/webkit-features-in-safari-17-0/).

Open **SDM download settings…** from the page context menu, **Download settings**
on a confirmation page, or the browser's extension options entry. Clicking the
toolbar icon still opens SDM.

There are two editable lists:

- **Download when offered by the website**: these are candidates for the existing
  conservative response check. A successful HEAD must return
  `Content-Disposition: attachment`, or a recognized binary MIME type without an
  explicit disposition. Explicit inline responses stay in the browser.
- **Download instead of previewing**: empty by default. Adding `mp4` here opts into
  downloading direct MP4 links even with `video/mp4` and `Content-Disposition:
  inline`. A successful HEAD and a nonempty MIME type other than `text/html` or
  `application/xhtml+xml` are still required. This list takes precedence when a
  suffix appears in both lists. It does not capture embedded video or streaming
  requests.

The default candidate list is:

```text
7z apk app arc arj bin bz2 cab dmg doc docx epub exe gz img iso jar key msi
numbers odf ods odt pages pkg ppt pptx rar tar tgz xls xlsx xip xz zip zipx
```

Matching uses the original HTTP(S) URL's final pathname suffix, ignores case,
query parameters and fragments, and does not infer a filename from a query or
response header. For example, `/file.ZIP?name=movie.mp4` matches `zip`,
`/file.tar.gz` matches `gz`, and `/download?name=file.zip` has no matching suffix.
Enter single extensions separated by whitespace, commas or semicolons, with an
optional leading dot. Wildcards, URLs and compound suffixes are rejected.

Remove a suffix from both lists to disable automatic handling for that type.
Emptying both lists disables all suffix-based interception. Same-origin
`download` links and explicit **Download with SDM** actions remain available.
**Restore defaults** immediately saves the default list and clears preview
overrides. Save and restore apply to already injected pages, including their
MAIN-world bridge, and future tabs without reloading the page.

Only the two extension lists are stored under `downloadRules` in
`storage.local`; no URLs or browser session data are stored there. Background
workers load persisted preferences before classifying navigation or an automatic
request, and content scripts keep automatic handling off until loading finishes.
`storage.onChanged` updates both. Failed settings reads leave automatic handling
off, and failed HEAD checks or HTTPS downgrades always continue in the browser.
The browser options and storage APIs follow the
[Chrome options documentation](https://developer.chrome.com/docs/extensions/develop/ui/options-page)
and [storage documentation](https://developer.chrome.com/docs/extensions/reference/api/storage).

## Download entry points

Same-origin links carrying the `download` attribute express explicit download
intent and do not require the preflight. Cross-origin `download` attributes alone
do not qualify. Eligible `window.open` calls following a user click use the same
candidate and response checks. Direct candidate navigation visits a hidden
confirmation page while checking headers; it returns to the original address if
the response does not qualify. A confirmed download offers **Open SDM** and
**Continue in browser**. Continuing grants a one-use navigation bypass and replaces
the confirmation history entry, so the original URL is not immediately recaptured.
Both actions show progress while their request is pending and become available
again when it finishes, including when a file download or external-app launch
leaves the confirmation document open. An unsuccessful **Open SDM** request shows
an error and lets the user retry or explicitly choose **Continue in browser**.

| Entry point | Confirmed download behavior |
| --- | --- |
| Address bar, `location.href`, or another top-level navigation to a candidate filename | Show the confirmation page after HEAD validation |
| Recognized link click or `window.open` following a user click | Hand directly to SDM after validation |
| Same-origin link with `download`, or explicit **Download with SDM** context-menu action | Hand directly to SDM |

The navigation confirmation path ignores subframes, non-candidate filenames,
and the one-use browser-continuation bypass. A HEAD response that cannot confirm
a download returns to normal browsing without showing the prompt.

Recognized requests collect URL-scoped browser cookies, the browser
User-Agent, and an origin-only Referer in the background worker. Ordinary
anchors, `window.open`, context-menu actions, and the direct-navigation
confirmation page all use this path. Cookie access failure rejects the handoff
instead of silently creating an anonymous SDM task. Automatic interception falls
back to the browser; the confirmation page keeps both choices available.

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
encrypted, short-lived file in the shared App Group
`group.top.kyleye.swifty-download-manager` on both iOS and macOS. Its key and
UUID travel separately through OS app activation; the app consumes and deletes the ciphertext. Expired
files are rejected and pruned on subsequent use. iOS also protects staging files
with complete file protection. Both targets must be signed by team `VB7MJ8R223`
and include provisioning profiles authorizing the registered group on each
platform, including Developer ID distributions. `REGISTER_APP_GROUPS` is enabled
for automatic signing. See Apple's
[App Group provisioning guidance](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

Both download engines use the context only in memory. Cookie domain, host-only,
path, Secure and expiration rules apply on redirects; an HTTPS browser download
cannot redirect to HTTP. Browser-profile stores and HTTP frame partition keys are
queried when their APIs are available. The extension confirmation document has no
web frame partition to query; it uses URL-scoped unpartitioned cookies from the
same tab's profile and does not query the extension origin as a cookie partition.
No other browser's cookie store is consulted.
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
`MAIN` execution world. The package requests `contextMenus`, `webNavigation`, `cookies`,
`storage` (for local file-type preferences), and HTTP/HTTPS
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

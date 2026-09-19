# Authenticated Chrome downloads: Apple Xcode and NDM

Investigated on 2026-09-20, against SDM commit `92bf03d`, on branch
`investigate/authenticated-browser-downloads`. The reported task was handed off
by the Chrome extension. This document records findings; download behavior has
not been changed.

## Findings

SDM's Chrome integration transfers a URL without the browser's authentication
context. The extension does not request cookie access, its callback has no
credential payload, and neither download backend accepts browser cookies.
Missing authentication is consistent with the reported Apple redirect and was
reproduced with anonymous requests to the exact URL.

There is also a separate completion problem: Apple's unauthorized page returns
HTTP 200. Both SDM backends accept that HTML response as a completed download.
An isolated fixture reproduced a 90-byte HTML file saved as `Xcode_27.xip`.

NDM's official Chrome extension reads cookies matching the download URL and
sends them to its desktop application over a loopback WebSocket. Its automatic
capture also considers the browser's response headers, allowing the browser to
make the authenticated request before handing off a recognized download.

The investigation verified that extension mechanism, not a complete Xcode
download through NDM with the user's Apple session. It did not establish which
specific Apple cookies are required or whether that session is currently valid.

## Apple response reproduced

Source URL:

```text
https://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip
```

Both an anonymous HEAD and a bounded GET with `Range: bytes=0-0`, using SDM's
libcurl User-Agent, followed this response chain:

```text
download.developer.apple.com/.../Xcode_27.xip
  -> 302 Location: https://developer.apple.com/unauthorized/
  -> 200 Content-Type: text/html; charset=UTF-8
```

The final response advertised no Content-Length, Content-Disposition,
Content-Range, or Accept-Ranges. The GET body began with HTML. Only the first
1,024 bytes were read; no Xcode archive was downloaded. This matches the
screenshot's final URL and zero Range segments.

To inspect the anonymous redirect again without downloading the body:

```bash
curl --silent --show-error --head --location --max-time 30 \
  --user-agent 'SwiftyDownloadManager/0.3 libcurl' \
  'https://download.developer.apple.com/Developer_Tools/Xcode_27/Xcode_27.xip'
```

The behavior above was observed on the investigation date, not assumed from
the filename or from an HTTP 401/403 response.

## Where SDM loses the browser context

| Layer | Current behavior | Relevant source |
| --- | --- | --- |
| Chrome permissions | Has host access, `contextMenus`, and `webNavigation`; no `cookies`, `webRequest`, or `downloads` permission | [Chrome manifest](../ChromeExtension/Resources/manifest.json) |
| Ordinary link click | Rewrites the anchor to the app callback directly; this path does not ask the background worker to assemble a request | [content.js](../BrowserExtension/Shared/content.js), click handler |
| `window.open` and context menu | Forward URL, optional filename, and source page through the shared controller | [page.js](../BrowserExtension/Shared/page.js), [background-controller.js](../BrowserExtension/Shared/background-controller.js) |
| Direct navigation | Uses an extension capture page based on the URL's extension, before validating a download response | [background-controller.js](../BrowserExtension/Shared/background-controller.js), [capture.js](../BrowserExtension/Shared/capture.js) |
| App callback | Parses URL, filename, and source page; there is no authentication field | [BrowserDownloadRequest.swift](../App/Sources/Features/BrowserExtensions/BrowserDownloadRequest.swift) |
| App enqueue | Passes URL, filename, and connection count; parsed `sourcePageURL` is not forwarded as a Referer | [ContentView.swift](../App/Sources/Application/ContentView.swift), `handleExternalURL`; [DownloadService.swift](../App/Sources/Features/Downloads/DownloadService.swift), `enqueue` |
| Core request | Has no cookie, Referer, or browser-header input | [DownloadModels.swift](../Packages/SDMCore/Sources/SDMCore/Models/DownloadModels.swift), `DownloadRequest` |
| libcurl | Creates fresh requests with SDM's User-Agent and follows redirects; no browser cookie engine is populated | [Engine.cpp](../Packages/SDMCore/Sources/SDMEngine/Engine.cpp), `make_transfer` |
| URLSession | Constructs a GET with SDM's User-Agent; no Chrome session is imported | [URLSessionDownloadBackend.swift](../Packages/SDMCore/Sources/SDMCore/Backends/URLSession/URLSessionDownloadBackend.swift), `schedule` |

Consequently, adding `chrome.cookies.getAll` only to the background worker
would leave ordinary anchor clicks unchanged. Adding a `source` query item also
does not make it an HTTP Referer. The current public-GET limitation is already
documented in [ChromeExtension.md](ChromeExtension.md).

## Why the error page becomes a completed file

In the libcurl backend, `make_transfer` enables automatic redirects and
`finish_transfer` accepts successful 2xx responses. `finish_probe` records the
effective URL and starts the body request without rejecting an unexpected HTML
representation. `infer_filename_extension` preserves a filename that already
has an extension, so `.xip` stays `.xip` even when the MIME type is HTML.

The URLSession backend's `didFinish` likewise accepts 2xx before finalization;
it has no authentication-page or expected-content check. Switching engines
therefore does not restore Chrome's cookies or solve this completion issue.

An external Swift executable imported this checkout's actual `SDMCore` and
downloaded from an ephemeral loopback fixture. The fixture served a synthetic
binary only for a synthetic valid cookie; otherwise it redirected to an
unknown-length HTTP 200 HTML page. A cookie-bearing control GET returned the
binary. With the requested filename `Xcode_27.xip`, the unmodified backends
produced:

| Backend | State | Saved filename | Final path | Bytes | Range segments | Body |
| --- | --- | --- | --- | ---: | ---: | --- |
| libcurl | completed | Xcode_27.xip | /unauthorized/ | 90 | 0 | HTML |
| URLSession | completed | Xcode_27.xip | /unauthorized/ | 90 | 0 | HTML |

The fixture observed no Cookie header on any SDM request, including libcurl's
HEAD and subsequent GET. This experiment used generated credentials and
temporary destinations, without reading browser sessions or modifying the
user's existing download.

## NDM implementation inspected

The source was the published
[NeatDownloadManager Chrome extension](https://chromewebstore.google.com/detail/neatdownloadmanager-exten/cpcifbdmkopohnnofedkjghjiclmhdah),
downloaded from [Google's extension update service](https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0.0.0&acceptformat=crx2,crx3&x=id%3Dcpcifbdmkopohnnofedkjghjiclmhdah%26uc),
not an unofficial fork. The update URL can return a newer build in the future;
the version and hash below identify the inspected build.

- Extension ID: `cpcifbdmkopohnnofedkjghjiclmhdah`.
- Retrieved manifest version: `1.9.92`, Manifest V3.
- CRX SHA-256: `d5899599fe47e08e536a234903ac040887bfa2f370ca9a78cfbe60adb5cbbca7`.
- Inspected files: `manifest.json` and `bg.js` from that CRX.

The manifest requests `cookies`, `webRequest`, `downloads`, `webNavigation`,
`contextMenus`, and `storage`, with all-URL host access. In this build's
minified `bg.js`:

| Function | Observed role |
| --- | --- |
| `V.W` | Context-menu handoff reads cookies for the selected URL |
| `V.V` | Processes response headers and redirects, recognizes file responses, and reads cookies for the selected response URL |
| `V.J` | Assembles the returned cookie names and values into a Cookie header |
| `V.I` | Serializes download details, Cookie, page-derived Referer/Origin, and selected other request data for the desktop app |
| `V.L` | Connects to `ws://127.0.0.1:10007/download`, using WebSocket subprotocol `neatextension.v1` |
| `V.X` | Cancels and erases a matching browser download after it has been selected for capture |

The script also captures selected `X-*` headers and has POST-body handling.
When desktop-requested metadata is missing, one path probes with an extension
HEAD request using `credentials: include`. This is not evidence that it clones
every browser header or that its native application supports every kind of
authenticated request. In particular, the inspected cookie calls omit an
explicit cookie store and partition key.

An isolated Node VM executed the published background script with mocked Chrome
APIs, synthetic cookies, and an in-memory WebSocket. Three checks passed:

1. A context-menu download queries cookies for its URL and sends Cookie and
   Referer through the loopback transport.
2. Automatic capture of a binary response includes cookies and a captured
   synthetic `X-*` header.
3. A 302 redirect followed by a 200 HTML page does not trigger automatic file
   handoff. This does not describe an explicit context-menu download of HTML.

These checks establish a concrete difference from SDM without installing NDM
or accessing real credentials. The downloaded third-party code remains outside
the repository and is not incorporated into SDM.

## Design implications

Authenticated browser downloads need a complete path from the extension to
the transfer engine. All capture entry points must converge on privileged
background code that obtains the appropriate URL-scoped browser context.
Chrome's [cookies API](https://developer.chrome.com/docs/extensions/reference/api/cookies)
requires cookie and host permissions and exposes HttpOnly metadata, stores,
and partitioning. Reading `document.cookie` in the source page is not an
equivalent way to obtain the download host's session.

The handoff needs a private payload channel. Putting cookies in the current
callback would place credentials in an anchor's page-visible `href`. NDM
demonstrates that a local WebSocket is one option. For SDM, that would require
an authenticated loopback protocol and a Release sandbox entitlement change:
the Release app currently allows outbound networking only. Chrome
[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
is another option, with a host executable, registration manifest, and permitted
extension origins; its installation requirements must fit SDM's sandboxed
distribution. The existing URL callback can still serve to activate the app.

The core needs transient request context used consistently by probes, body
transfers, segments, retries, and resume. Cookie scope must survive redirects;
an unscoped header is insufficient. libcurl supports an in-memory cookie engine
through [CURLOPT_COOKIELIST](https://curl.se/libcurl/c/CURLOPT_COOKIELIST.html).
URLSession needs corresponding request and redirect handling. Neither backend
should silently resume an authenticated task as an anonymous request when its
context has expired or disappeared.

Persistence needs explicit treatment: `DownloadRequest` is Codable, and
`URLSessionDownloadRecord` embeds it in the JSON store. Simply adding encoded
credential fields would violate the current
[core contract](SDMCore.md) that cookies and request headers are not persisted.
Opaque URLSession background/resume data also needs consideration when defining
that contract for authenticated tasks.

Finally, expected-content validation is separate from cookie transport. A
browser handoff for a binary attachment should report an authentication or
unexpected-content failure when it resolves to a login/error HTML page.
Validation should cover both probe and body responses, including a session
expiring between them. Legitimate HTML downloads must remain supported:
`HTTPCompatibilityTests.testUnknownLengthHTMLCompletesWithMIMEInferredFilename`
already verifies that behavior. Rejecting all HTML or merely adding
`CURLOPT_FAILONERROR` would not solve this HTTP 200 case correctly.

## Validation scope

- Pinned tools were already installed (`mise install`).
- Existing Chrome and Safari JavaScript tests: 13 passed.
- Actual Apple URL: anonymous HEAD and bounded GET reproduced the redirect.
- Actual SDMCore: both backends reproduced the false completion locally.
- Published NDM background script: all three isolated checks passed.
- No production code, extension permissions, or public API changed. The full
  application build and complete repository test suite were not run for this
  documentation-only investigation.

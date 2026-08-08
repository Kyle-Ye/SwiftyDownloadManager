# Third-party licensing

The iOS and macOS libcurl backend uses the fixed
[curl-apple 8.21.0](https://github.com/greatfire/curl-apple/releases/tag/8.21.0)
binary artifact. Its SHA-256 is
`56bee7fbef0051707c5b3b4f129f703092df61005da371b9c8a3bd0450a0ae88`.

The artifact statically combines libcurl 8.21.0 and OpenSSL 3.6.0. It also
contains a Mozilla-derived CA bundle as a framework resource. The app includes
the complete upstream license texts under `App/Resources/Legal`:

- curl license for libcurl;
- MIT license for the curl-apple build/packaging project;
- Apache License 2.0 for OpenSSL;
- Mozilla Public License 2.0 for the bundled CA data's source project.

The bundled `cacert.pem` is byte-for-byte identical to the iOS resource in the
pinned XCFramework (SHA-256
`86a1f3366afac7c6f8ae9f3c779ac221129328c43f0ab2b8817eb2f362a5025c`).
curl documents that this converted Mozilla CA store is under MPL 2.0 and links
its source and historical revisions at <https://curl.se/docs/caextract.html>.

This set permits commercial binary distribution when its notice and
redistribution terms are followed. The repository and app bundle retain all
four license texts. OpenSSL 3.6.0 has no upstream `NOTICE` file; its complete
Apache 2.0 license is included.

## Development-only LookInside server

Debug builds generated with `TUIST_LOOK_INSIDE_ENABLED=true` link the pinned
[`LookInsideServer` 0.2.7](https://github.com/LookInsideApp/LookInside-Release/releases/tag/0.2.7)
binary to support local UI inspection; the integration is disabled by default.
LookInside is licensed under GPL-3.0. The `SDMApp` Release configuration
excludes `LookInsideServer*`; release validation must continue to confirm that
the framework is absent from the app
bundle and executable load commands. It is therefore not part of the app's
distributed third-party notices. Anyone distributing a Debug build must review
and comply with the upstream license separately.

On macOS, `SDMCore` exports Apple system trust anchors into the app's private
storage and configures `CURLOPT_CAINFO` with that file. iOS does not expose its
system root certificates, so the iOS libcurl backend uses the audited
Mozilla-derived CA bundle copied from the pinned artifact. URLSession continues
to use Apple's native trust evaluation on both platforms. Updating the binary
artifact therefore also requires refreshing and reviewing `cacert.pem`.

## Release check

Before shipping a new binary artifact:

1. Pin an immutable release URL and SwiftPM checksum.
2. Audit the tagged build script for component-version or build-flag changes.
3. Refresh every affected license text and this document.
4. Inspect the archived app for copied XCFramework resources.
5. Review Apple export-compliance declarations. Statically linked OpenSSL is a
   separate compliance question from open-source licensing.
6. Preserve or reproducibly rebuild the audited artifact; the checksum pins the
   bytes but does not remove reliance on the third-party GitHub release.

This is an engineering compliance record, not legal advice.

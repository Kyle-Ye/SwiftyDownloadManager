# Release process

SDM releases are built, signed, notarized, stapled, and published by
`.github/workflows/release.yml`. Pushing a semantic-version tag starts the
workflow and publishes one user-facing asset:
`SwiftyDownloadManager.app.zip`.

The full Xcode archive remains ephemeral on the runner and is never uploaded to
GitHub Releases.

## Signing model

`Project.swift` uses configuration-specific signing:

- Debug uses automatic Apple Development signing.
- Release uses manual Developer ID Application signing.
- Hardened Runtime is enabled for both the App and Safari Extension.
- Release builds disable injected base entitlements.

No certificate, private key, password, or notarization credential belongs in
the repository. The workflow imports them into a temporary keychain and removes
the signing material when the job finishes.

## Required GitHub Actions secrets

Configure these repository secrets before pushing the first release tag:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12`, including its private key |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-encoded App Store Connect API key `.p8` |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API issuer UUID |

The Developer ID certificate must belong to team `VB7MJ8R223`. The App Store
Connect API key must have access to the same team and permission to submit to
the Apple notary service.

Encode and upload the files without committing intermediate Base64 files:

```bash
base64 -i /path/to/DeveloperIDApplication.p12 | \
  gh secret set DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64 \
    --repo Kyle-Ye/SwiftyDownloadManager

printf '%s' 'P12_PASSWORD' | \
  gh secret set DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD \
    --repo Kyle-Ye/SwiftyDownloadManager

base64 -i /path/to/AuthKey_KEY_ID.p8 | \
  gh secret set APP_STORE_CONNECT_API_KEY_BASE64 \
    --repo Kyle-Ye/SwiftyDownloadManager

printf '%s' 'KEY_ID' | \
  gh secret set APP_STORE_CONNECT_API_KEY_ID \
    --repo Kyle-Ye/SwiftyDownloadManager

printf '%s' 'ISSUER_UUID' | \
  gh secret set APP_STORE_CONNECT_API_ISSUER_ID \
    --repo Kyle-Ye/SwiftyDownloadManager
```

Confirm that the required names exist. GitHub does not expose their values:

```bash
gh secret list --repo Kyle-Ye/SwiftyDownloadManager
```

## Version model

SDM has four release values:

- App marketing version and build number in `Project.swift`.
- Safari Extension marketing version and build number in `Project.swift`.
- Web Extension manifest version in
  `SafariExtension/Resources/manifest.json`.
- Engine development version in
  `Packages/SDMCore/Sources/SDMEngine/Engine.cpp`, with a matching test value in
  `Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift`.

For a release such as `0.3.0`, update the App, Safari Extension, and manifest to
`0.3.0` before tagging. Keep the Engine value at `0.3.0-dev` through the
release. After the release succeeds, advance the Engine and its test to
`0.4.0-dev` in a separate commit.

## Prepare a release

Start from a clean `main` synchronized with `origin/main`:

```bash
git switch main
git pull --ff-only origin main
git status --short --branch
```

Update both target versions and build numbers in `Project.swift`, then update
the manifest version. Regenerate the workspace and run all tests:

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
bash Scripts/test.sh
xcodebuild test -quiet \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SDMAppTests \
  CODE_SIGNING_ALLOWED=NO
git diff --check
```

Review, commit, and push only the intended release changes:

```bash
git add Project.swift SafariExtension/Resources/manifest.json
git commit -m "chore: prepare 0.3.0 release"
git push origin main
```

## Publish a release

Create and push an annotated tag from the release commit:

```bash
git tag -a 0.3.0 -m "Swifty Download Manager 0.3.0"
git push origin 0.3.0
```

The workflow then:

1. Checks out and validates the exact tag.
2. Generates the Tuist workspace and runs the test suites.
3. Imports the Developer ID certificate into a temporary keychain.
4. Archives a universal `arm64` and `x86_64` Release build.
5. Verifies the App and nested Safari Extension signatures.
6. Submits the App to Apple with `notarytool` and waits for acceptance.
7. Staples and validates the notarization ticket, then runs Gatekeeper
   assessment.
8. Packages only `SwiftyDownloadManager.app.zip`.
9. Creates a GitHub Release with automatically generated changelog notes.

Monitor the run and inspect failures with GitHub CLI:

```bash
gh run list \
  --workflow Release \
  --repo Kyle-Ye/SwiftyDownloadManager
gh run watch RUN_ID \
  --repo Kyle-Ye/SwiftyDownloadManager \
  --exit-status
```

If a tag-triggered run needs retrying, rerun the failed workflow. The manual
`workflow_dispatch` input can also release an existing semantic-version tag.

## Release notes

GitHub generates release notes from merged pull requests using
`.github/release.yml`. Keep them as a user-facing changelog:

- `Features` for `enhancement` or `feature` labels.
- `Fixes` for `bug` or `fix` labels.
- `Other Changes` for uncategorized pull requests.
- `skip-changelog` excludes internal-only pull requests.

Do not add certificate names, Team IDs, notarization implementation details, or
local build paths to release notes.

## Verify the published artifact

Download and verify the exact uploaded App:

```bash
SDM_VERSION=0.3.0
SDM_VERIFY_DIR="$(mktemp -d /private/tmp/sdm-release-verify.XXXXXX)"
gh release download "$SDM_VERSION" \
  --repo Kyle-Ye/SwiftyDownloadManager \
  --pattern SwiftyDownloadManager.app.zip \
  --dir "$SDM_VERIFY_DIR"
ditto -x -k \
  "$SDM_VERIFY_DIR/SwiftyDownloadManager.app.zip" \
  "$SDM_VERIFY_DIR"
SDM_APP_PATH="$SDM_VERIFY_DIR/Swifty Download Manager.app"
codesign --verify --deep --strict --verbose=4 "$SDM_APP_PATH"
xcrun stapler validate "$SDM_APP_PATH"
spctl --assess --type execute --verbose=4 "$SDM_APP_PATH"
```

Confirm that the Release contains exactly one App zip and record its digest:

```bash
gh release view "$SDM_VERSION" \
  --repo Kyle-Ye/SwiftyDownloadManager \
  --json name,tagName,url,isDraft,isPrerelease,assets
shasum -a 256 "$SDM_VERIFY_DIR/SwiftyDownloadManager.app.zip"
```

After verification, advance the Engine development version and its matching
test in a separate commit.

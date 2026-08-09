# Release process

SDM uses two Xcode Cloud workflows. Changes to `main` run the `Main` workflow
for continuous validation. Changes to a `release/MAJOR.MINOR` branch run the
`Release` workflow to test, archive, sign, and notarize the macOS app. After
that workflow succeeds, pushing a semantic-version tag for the same commit
starts the GitHub `Publish Xcode Cloud Release` workflow.

Xcode Cloud owns the release binary. It archives the macOS app, signs the
export with Developer ID, sends it to Apple's notary service, and produces a
`STAPLED_NOTARIZED_ARCHIVE` artifact. GitHub Actions waits for that exact
artifact through the App Store Connect API, verifies it, and publishes one
user-facing asset: `SwiftyDownloadManager.app.zip`.

The Xcode Cloud archive and logs remain available in App Store Connect for
Apple's retention period. GitHub Releases only stores the packaged app.

This workflow currently publishes the universal macOS application. iOS and
iPadOS share the source and Xcode targets but require a separate App Store
archive and distribution workflow.

## Signing model

`Project.swift` uses automatic signing for Debug and Release on every
platform. Xcode Cloud manages the Developer ID signing assets for the macOS
archive and its Notarize post-action. Hardened Runtime and disabled injected
base entitlements still apply to macOS Release builds.

No Developer ID certificate, private key, certificate password, or
notarization credential belongs in the repository, GitHub Actions, or a local
release script.

## Xcode Cloud setup

The initial Xcode Cloud product must be configured from Xcode with the locally
generated `SDM.xcworkspace` and the `Swifty Download Manager` app product. The
repository keeps generated Xcode projects and workspaces out of Git, so
`ci_scripts/ci_post_clone.sh` installs the pinned Tuist version and generates
the workspace after every cloud clone.

Configure two enabled workflows. The development workflow uses these values:

- Name: `Main`.
- Primary repository: `Kyle-Ye/SwiftyDownloadManager`.
- Project or Workspace: `SDM.xcworkspace`.
- Start condition: Branch Changes for the exact `main` branch.
- Build action: `SDMApp`, macOS, Any Mac.
- No post-action.
- Environment: a current supported release of Xcode and macOS.

The release workflow uses these values:

- Name: `Release`.
- Primary repository: `Kyle-Ye/SwiftyDownloadManager`.
- Project or Workspace: `SDM.xcworkspace`.
- Start condition: Branch Changes for branches beginning with `release/`.
- Archive action: `SDMApp`, macOS, Any Mac.
- Post-action: Notarize the macOS archive.
- Environment: a current supported release of Xcode and macOS.
- Restrict Editing: enabled, as required for notarization workflows.

When adding the custom release branch condition, enter `release/` and select
the Xcode option for branches beginning with that value. Do not configure a
literal branch named `release/`.

The Notarize post-action becomes available after the initial Xcode Cloud setup
and first build complete. For that bootstrap build only, run a branch build
without Notarize, then add the post-action before publishing a version tag.

`ci_scripts/ci_pre_xcodebuild.sh` runs the cross-language test suite before the
`Main` build. Before a `Release` archive, it also verifies that the source
version is an exact `MAJOR.MINOR.PATCH`, that its major-minor line matches the
`release/MAJOR.MINOR` branch, that all source versions agree, and that the
Chrome extension packages successfully.

## Required GitHub Actions secrets

GitHub Actions needs read access to Xcode Cloud build metadata and artifacts
through the App Store Connect API:

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-encoded App Store Connect API key `.p8` |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API issuer UUID |

The API key must be able to read the app's Xcode Cloud products, workflows,
builds, actions, and artifacts. GitHub Actions writes the key to its temporary
runner directory, uses short-lived JWTs, and removes the key when the job ends.

Confirm that the required names exist. GitHub does not expose their values:

```bash
gh secret list --repo Kyle-Ye/SwiftyDownloadManager
```

The old GitHub-hosted signing secrets have been removed and must not be
recreated:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`

## Version model

SDM uses one version across the App, Safari Extension, Safari Web Extension,
Chrome Extension, and Engine on both release tags and `main`. For a planned
version such as `0.5.0`, all of these values must be `0.5.0`:

- App marketing version in `Project.swift`.
- Safari Extension marketing version in `Project.swift`.
- Safari Web Extension manifest version in
  `SafariExtension/Resources/manifest.json`.
- Chrome Extension manifest version in
  `ChromeExtension/Resources/manifest.json`.
- Engine version in `Packages/SDMCore/Sources/SDMEngine/Engine.cpp`, with the
  matching expected value in
  `Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift`.

The App and Safari Extension also share a monotonically increasing build
number in `Project.swift`. Version values always use the plain `X.Y.Z` form;
prerelease suffixes are not used.

After a mainline release is verified, advance every source version to the next
planned release and increment the shared build number in a separate commit.
This means development builds from `main` identify themselves as the next
planned release before that release is published.

If `main` has already advanced to the next planned version, prepare a patch
release from the corresponding stable tag or release branch. Do not merge the
newer `main` line into that branch. The patch release commit must set every
source version to the patch version and use an appropriate unused build
number.

## Prepare a release

Set the release values and branch name explicitly:

```bash
SDM_VERSION=0.5.0
SDM_BUILD_NUMBER=6
SDM_RELEASE_BRANCH="release/${SDM_VERSION%.*}"
```

For a planned mainline release, synchronize `main` and create the stable
major-minor branch before making release-only changes:

```bash
git switch main
git pull --ff-only origin main
git status --short --branch
git switch -c "$SDM_RELEASE_BRANCH"
```

For a patch release, use the existing stable branch instead:

```bash
git switch "$SDM_RELEASE_BRANCH"
git pull --ff-only origin "$SDM_RELEASE_BRANCH"
```

Confirm that both target versions and build numbers in `Project.swift`, both
manifest versions, the Engine version, and its matching test equal the release
values:

```bash
test "$(rg -F -c \
  "\"CFBundleShortVersionString\": \"${SDM_VERSION}\"" Project.swift)" -eq 2
test "$(rg -F -c \
  "\"CFBundleVersion\": \"${SDM_BUILD_NUMBER}\"" Project.swift)" -eq 2
test "$(jq -r '.version' SafariExtension/Resources/manifest.json)" = \
  "${SDM_VERSION}"
test "$(jq -r '.version' ChromeExtension/Resources/manifest.json)" = \
  "${SDM_VERSION}"
rg -n -F "return \"${SDM_VERSION}\";" \
  Packages/SDMCore/Sources/SDMEngine/Engine.cpp
rg -n -F "SDMCoreInfo.engineVersion, \"${SDM_VERSION}\"" \
  Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
```

Regenerate the workspace and run all tests locally:

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
bash Scripts/test.sh
Scripts/package-chrome-extension.sh \
  /tmp/SwiftyDownloadManager-Chrome-${SDM_VERSION}.zip
xcodebuild test -quiet \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SDMAppTests \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -quiet \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
git diff --check
```

Review `Docs/ThirdPartyLicensing.md` and confirm every file under
`App/Resources/Legal` is present in the built application. The pinned
XCFramework statically includes OpenSSL, so Apple encryption export-compliance
answers must be reviewed independently of open-source license compliance.

If the source versions already match and no correction is needed, do not
create an empty release-preparation commit. Push the branch itself so Xcode
Cloud builds the exact release commit:

```bash
git push -u origin "$SDM_RELEASE_BRANCH"
```

Wait for the `Release` workflow to complete its Archive and Notarize actions.
Do not create the version tag until Xcode Cloud has produced the stapled,
notarized artifact for the branch's current commit.

## Publish a release

After the release-branch build succeeds, create and push an annotated tag on
that same commit:

```bash
git tag -a "$SDM_VERSION" \
  -m "Swifty Download Manager $SDM_VERSION"
git push origin "$SDM_VERSION"
```

The complete flow is:

1. Pushing `release/MAJOR.MINOR` starts the Xcode Cloud `Release` workflow.
2. The pre-archive script validates the branch line and source versions, then
   runs the test suite.
3. Xcode Cloud archives the universal macOS app with managed Developer ID
   signing after the pre-archive tests pass.
4. The Notarize post-action submits the app, waits for acceptance, and staples
   the ticket.
5. Pushing the semantic-version tag starts GitHub Actions. It verifies that
   the tag belongs to the corresponding `origin/release/MAJOR.MINOR` branch.
6. GitHub Actions matches the Xcode Cloud release-branch build by branch and
   commit, then downloads only its `STAPLED_NOTARIZED_ARCHIVE` and verifies the
   signature, ticket, Gatekeeper result, versions, architectures, licenses,
   and absence of development-only LookInside code.
7. GitHub Actions repackages the verified app and creates or updates the GitHub
   Release with generated changelog notes.

The GitHub workflow's manual dispatch can republish an existing semantic tag
after Xcode Cloud has successfully produced the matching release-branch
artifact.

Monitor Xcode Cloud in Xcode or App Store Connect. Monitor the publishing job
with GitHub CLI:

```bash
gh run list \
  --workflow "Publish Xcode Cloud Release" \
  --repo Kyle-Ye/SwiftyDownloadManager
gh run watch RUN_ID \
  --repo Kyle-Ye/SwiftyDownloadManager \
  --exit-status
```

## Release notes

GitHub generates release notes from merged pull requests using
`.github/release.yml`. Keep them as a user-facing changelog:

- `Features` for `enhancement` or `feature` labels.
- `Fixes` for `bug` or `fix` labels.
- `Other Changes` for uncategorized pull requests.
- `skip-changelog` excludes internal-only pull requests.

Do not add certificate names, Team IDs, notarization implementation details,
App Store Connect artifact URLs, or local build paths to release notes.

## Verify the published artifact

Download and verify the exact uploaded app:

```bash
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
SDM_BINARY_VERSIONS="$(
  strings "$SDM_APP_PATH/Contents/MacOS/SDMApp" | \
    rg -x '[0-9]+\.[0-9]+\.[0-9]+' | \
    sort -u || true
)"
printf '%s\n' "$SDM_BINARY_VERSIONS" | rg -Fx "$SDM_VERSION"
xcrun stapler validate "$SDM_APP_PATH"
spctl --assess --type execute --verbose=4 "$SDM_APP_PATH"
```

Confirm that the Release contains exactly one app zip and record its digest:

```bash
gh release view "$SDM_VERSION" \
  --repo Kyle-Ye/SwiftyDownloadManager \
  --json name,tagName,url,isDraft,isPrerelease,assets
shasum -a 256 "$SDM_VERIFY_DIR/SwiftyDownloadManager.app.zip"
```

After a mainline release is verified, advance both target versions and build
numbers in `Project.swift`, both manifest versions, the Engine version, and its
matching test to `${SDM_NEXT_VERSION}` and `${SDM_NEXT_BUILD_NUMBER}`. Run the
source-version checks and focused Engine version test, then commit the planned
version separately from the release tag.

For a patch release made from a release branch while `main` already carries the
next planned version, skip that step. Return to `main` without merging the
stable patch version back over its newer planned version.

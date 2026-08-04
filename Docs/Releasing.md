# Release process

This document describes the current SDM release process. It produces a
universal macOS application, stores the full Xcode archive locally, and uploads
only `SwiftyDownloadManager.app.zip` to GitHub Releases.

The current artifact is ad-hoc signed for local testing. It is not Developer ID
signed or notarized. Public distribution requires a separate signing,
notarization, and stapling workflow.

## Version model

SDM currently has four release values:

- App marketing version and build number in `Project.swift`.
- Safari Extension marketing version and build number in `Project.swift`.
- Web Extension manifest version in
  `SafariExtension/Resources/manifest.json`.
- Engine development version in
  `Packages/SDMCore/Sources/SDMEngine/Engine.cpp`, with a matching test value in
  `Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift`.

For a release such as `0.3.0`, update the App, Safari Extension, and manifest to
`0.3.0` before tagging. Keep the Engine value at `0.3.0-dev` through the
release. After the release is verified, advance the Engine and its test to
`0.4.0-dev` in a separate commit.

## Prerequisites

- Xcode and its command-line tools.
- `mise`, with the repository's pinned Tuist version installed.
- An authenticated GitHub CLI session with repository write access.
- A clean `main` branch synchronized with `origin/main`.

Set release-specific values explicitly. Do not reuse broad system variables for
release paths.

```bash
SDM_VERSION=0.3.0
SDM_BUILD_NUMBER=3
SDM_NEXT_DEV_VERSION=0.4.0-dev
SDM_ARCHIVE_DATE=2026-08-05
SDM_REPOSITORY=Kyle-Ye/SwiftyDownloadManager
SDM_ARCHIVE_ROOT="${HOME}/Library/Developer/Xcode/Archives/${SDM_ARCHIVE_DATE}"
SDM_ARCHIVE_PATH="${SDM_ARCHIVE_ROOT}/Swifty Download Manager ${SDM_VERSION}.xcarchive"
SDM_APP_PATH="${SDM_ARCHIVE_PATH}/Products/Applications/Swifty Download Manager.app"
SDM_EXTENSION_PATH="${SDM_APP_PATH}/Contents/PlugIns/Swifty Download Manager Extension.appex"
SDM_RELEASE_ZIP="/private/tmp/SwiftyDownloadManager.app.zip"
SDM_VERIFY_DIR="/private/tmp/sdm-app-verify-${SDM_VERSION}"
SDM_RELEASE_NOTES="The attached asset contains the universal macOS application"
SDM_RELEASE_NOTES="${SDM_RELEASE_NOTES} (arm64 and x86_64)."
SDM_RELEASE_NOTES="${SDM_RELEASE_NOTES} Unzip it and move the app to Applications."
SDM_RELEASE_NOTES="${SDM_RELEASE_NOTES} The app is ad-hoc signed for local testing."
```

Use the actual release date and monotonically increasing build number. Run the
remaining commands from the repository root in the same shell session so these
values remain available.

## 1. Prepare `main`

Confirm GitHub authentication, update `main`, and verify that the worktree is
clean.

```bash
gh auth status
git switch main
git pull --ff-only origin main
git status --short --branch
```

Clean up merged feature branches before releasing. For squash-merged branches,
verify the pull request is merged before force-deleting the local branch. Delete
only the exact local and remote branch names that were reviewed.

Confirm that the version is not already tagged or released.

```bash
git tag --list "${SDM_VERSION}"
git ls-remote --tags origin "refs/tags/${SDM_VERSION}"
gh release view "${SDM_VERSION}" --repo "${SDM_REPOSITORY}"
```

The tag and release checks should return no existing release for a new version.

## 2. Update release metadata

Update both targets in `Project.swift`:

- `CFBundleShortVersionString` to `${SDM_VERSION}`.
- `CFBundleVersion` to `${SDM_BUILD_NUMBER}`.

Update `SafariExtension/Resources/manifest.json`:

- `version` to `${SDM_VERSION}`.

Do not advance the Engine development version yet. Check every relevant value
before generating the project.

```bash
rg -n 'CFBundleShortVersionString|CFBundleVersion' Project.swift
jq -r '.version' SafariExtension/Resources/manifest.json
rg -n 'Engine::version|[0-9]+\.[0-9]+\.[0-9]+-dev' \
  Packages/SDMCore/Sources/SDMEngine/Engine.cpp \
  Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
```

## 3. Generate and validate

Regenerate after changing `Project.swift` or the extension manifest.

```bash
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open
```

Run the Fixture and SDMCore suites, followed by the App tests.

```bash
bash Scripts/test.sh
xcodebuild test -quiet \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SDMAppTests \
  CODE_SIGNING_ALLOWED=NO
```

Review the release diff and ensure that generated projects remain ignored.

```bash
git diff --check
git status --short
git diff -- Project.swift SafariExtension/Resources/manifest.json
```

## 4. Commit and push the release version

Commit only the release metadata files.

```bash
git add Project.swift SafariExtension/Resources/manifest.json
git commit -m "chore: prepare ${SDM_VERSION} release"
git push origin main
git status --short --branch
git rev-parse HEAD
```

Record the commit returned by `git rev-parse HEAD`. The tag and archive must be
created from this exact release commit.

## 5. Create and push the tag

Create an annotated tag, push it, and confirm that it resolves to the recorded
release commit.

```bash
git tag -a "${SDM_VERSION}" \
  -m "Swifty Download Manager ${SDM_VERSION}"
git push origin "${SDM_VERSION}"
git rev-parse "${SDM_VERSION}^{}"
```

Do not advance the development version until the archive and GitHub Release are
verified.

## 6. Build the Xcode archive

Keep the full `.xcarchive` locally for debugging and symbolication. Refuse to
overwrite an existing archive path; choose a new explicit path if the check
fails.

```bash
test ! -e "${SDM_ARCHIVE_PATH}"
xcodebuild archive -quiet \
  -workspace SDM.xcworkspace \
  -scheme SDMApp \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${SDM_ARCHIVE_PATH}" \
  CODE_SIGN_IDENTITY=-
```

The current configuration produces an ad-hoc signed Universal application.
Warnings about a locked connected iOS device or a missing AccentColor are
non-blocking for this macOS archive, but other warnings should be investigated.

## 7. Validate the archive

Confirm the App and Safari Extension versions, Web Extension manifest,
architectures, and nested signatures.

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${SDM_APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${SDM_APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${SDM_EXTENSION_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${SDM_EXTENSION_PATH}/Contents/Info.plist"
jq -r '.version' \
  "${SDM_EXTENSION_PATH}/Contents/Resources/manifest.json"
lipo -archs "${SDM_APP_PATH}/Contents/MacOS/SDMApp"
codesign --verify --deep --strict --verbose=2 "${SDM_APP_PATH}"
```

Expected results:

- App and Extension marketing versions match `${SDM_VERSION}`.
- App and Extension build numbers match `${SDM_BUILD_NUMBER}`.
- Manifest version matches `${SDM_VERSION}`.
- App architectures are `x86_64 arm64`.
- Deep code-signature verification succeeds.

## 8. Package only the App

GitHub Releases must contain one user-facing asset named
`SwiftyDownloadManager.app.zip`. Never upload an `.xcarchive.zip`.

Refuse to overwrite old temporary output, then preserve the App bundle and its
extended attributes with `ditto`.

```bash
test ! -e "${SDM_RELEASE_ZIP}"
test ! -e "${SDM_VERIFY_DIR}"
ditto -c -k --sequesterRsrc --keepParent \
  "${SDM_APP_PATH}" \
  "${SDM_RELEASE_ZIP}"
unzip -t "${SDM_RELEASE_ZIP}"
mkdir "${SDM_VERIFY_DIR}"
ditto -x -k "${SDM_RELEASE_ZIP}" "${SDM_VERIFY_DIR}"
codesign --verify --deep --strict --verbose=2 \
  "${SDM_VERIFY_DIR}/Swifty Download Manager.app"
shasum -a 256 "${SDM_RELEASE_ZIP}"
```

Record the SHA-256 digest. The digest reported by GitHub after upload must match
it exactly.

## 9. Create the GitHub Release

Create a non-draft, non-prerelease Release from the verified tag and upload only
the App zip.

```bash
gh release create "${SDM_VERSION}" \
  "${SDM_RELEASE_ZIP}" \
  --repo "${SDM_REPOSITORY}" \
  --title "Swifty Download Manager ${SDM_VERSION}" \
  --verify-tag \
  --latest \
  --generate-notes \
  --notes "${SDM_RELEASE_NOTES}"
```

Verify that the Release contains exactly one asset, that its name is
`SwiftyDownloadManager.app.zip`, and that the remote digest matches the local
digest.

```bash
gh api \
  "repos/${SDM_REPOSITORY}/releases/tags/${SDM_VERSION}" \
  --jq '{
    html_url,
    draft,
    prerelease,
    assets: [.assets[] | {name, size, digest, browser_download_url}]
  }'
shasum -a 256 "${SDM_RELEASE_ZIP}"
```

If an incorrect asset was uploaded, upload and verify the replacement first.
Only then remove the incorrect asset with `gh release delete-asset`.

## 10. Advance the development version

After the GitHub Release and its asset are verified, update both occurrences of
the Engine development version:

- `Packages/SDMCore/Sources/SDMEngine/Engine.cpp`.
- `Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift`.

Set them to `${SDM_NEXT_DEV_VERSION}`, then run the focused version test.

```bash
rg -n '[0-9]+\.[0-9]+\.[0-9]+-dev' \
  Packages/SDMCore/Sources/SDMEngine/Engine.cpp \
  Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
swift test \
  --package-path Packages/SDMCore \
  --filter SDMCoreInfoTests
git diff --check
```

Commit and push the new development version separately from the release tag.

```bash
git add \
  Packages/SDMCore/Sources/SDMEngine/Engine.cpp \
  Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
git commit -m "chore: start ${SDM_NEXT_DEV_VERSION%-dev} development"
git push origin main
```

## 11. Final verification

Confirm that `main` is clean and synchronized, the tag still targets the
release commit, the Release is published, and it has exactly one App zip asset.

```bash
git status --short --branch
git log --oneline --decorate -4
git rev-parse "${SDM_VERSION}^{}"
gh release view "${SDM_VERSION}" \
  --repo "${SDM_REPOSITORY}" \
  --json name,tagName,url,isDraft,isPrerelease,assets
```

Keep the local `.xcarchive` for diagnostics. Temporary packaging and extraction
directories can be removed after all checks complete.

#!/bin/sh

set -eu

if [ "${CI_WORKFLOW:-}" != "Release" ] || \
   [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -z "${CI_TAG:-}" ]; then
  echo "Skipping release validation for the initial non-tag Xcode Cloud build."
  exit 0
fi

release_tag="$CI_TAG"
case "$release_tag" in
  *[!0-9.]* | .* | *. | *..*)
    echo "Release tag must use MAJOR.MINOR.PATCH format: $release_tag" >&2
    exit 1
    ;;
esac

if [ "$(printf '%s' "$release_tag" | awk -F. '{ print NF }')" -ne 3 ]; then
  echo "Release tag must use MAJOR.MINOR.PATCH format: $release_tag" >&2
  exit 1
fi

app_version_count="$(
  grep -F -c \
    "\"CFBundleShortVersionString\": \"$release_tag\"" \
    Project.swift || true
)"
safari_manifest_version="$(
  plutil -extract version raw -o - SafariExtension/Resources/manifest.json
)"
chrome_manifest_version="$(
  plutil -extract version raw -o - ChromeExtension/Resources/manifest.json
)"

if [ "$app_version_count" -ne 2 ] || \
   [ "$safari_manifest_version" != "$release_tag" ] || \
   [ "$chrome_manifest_version" != "$release_tag" ]; then
  echo "Source App, Extension, or browser manifest version does not match tag $release_tag" >&2
  exit 1
fi

engine_source=Packages/SDMCore/Sources/SDMEngine/Engine.cpp
engine_test=Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
grep -F "return \"$release_tag\";" "$engine_source"
grep -F "SDMCoreInfo.engineVersion, \"$release_tag\"" "$engine_test"

bash Scripts/test.sh
Scripts/package-chrome-extension.sh \
  "$TMPDIR/SwiftyDownloadManager-Chrome-$release_tag.zip"

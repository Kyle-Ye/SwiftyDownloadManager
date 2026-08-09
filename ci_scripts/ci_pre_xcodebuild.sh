#!/bin/sh

set -eu

export PATH="$HOME/.local/bin:$PATH"

case "${CI_WORKFLOW:-}:${CI_XCODEBUILD_ACTION:-}" in
  Main:build)
    ;;
  Release:archive)
    ;;
  *)
    exit 0
    ;;
esac

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ "$CI_WORKFLOW" = "Main" ]; then
  mise exec -- bash Scripts/test.sh
  exit 0
fi

release_branch="${CI_BRANCH:-}"
safari_manifest_version="$(
  plutil -extract version raw -o - SafariExtension/Resources/manifest.json
)"
release_version="$safari_manifest_version"

case "$release_version" in
  *[!0-9.]* | .* | *. | *..*)
    echo "Release source version must use MAJOR.MINOR.PATCH format: $release_version" >&2
    exit 1
    ;;
esac

if [ "$(printf '%s' "$release_version" | awk -F. '{ print NF }')" -ne 3 ]; then
  echo "Release source version must use MAJOR.MINOR.PATCH format: $release_version" >&2
  exit 1
fi

release_line="${release_version%.*}"
expected_branch="release/$release_line"
if [ "$release_branch" != "$expected_branch" ]; then
  echo "Release workflow must run from $expected_branch, not ${release_branch:-<unknown>}." >&2
  exit 1
fi

app_version_count="$(
  grep -F -c \
    "\"CFBundleShortVersionString\": \"$release_version\"" \
    Project.swift || true
)"
chrome_manifest_version="$(
  plutil -extract version raw -o - ChromeExtension/Resources/manifest.json
)"

if [ "$app_version_count" -ne 2 ] || \
   [ "$chrome_manifest_version" != "$release_version" ]; then
  echo "Source App, Extension, or browser manifest versions do not match $release_version" >&2
  exit 1
fi

engine_source=Packages/SDMCore/Sources/SDMEngine/Engine.cpp
engine_test=Packages/SDMCore/Tests/SDMCoreTests/SDMCoreInfoTests.swift
grep -F "return \"$release_version\";" "$engine_source"
grep -F "SDMCoreInfo.engineVersion, \"$release_version\"" "$engine_test"

mise exec -- bash Scripts/test.sh
Scripts/package-chrome-extension.sh \
  "$TMPDIR/SwiftyDownloadManager-Chrome-$release_version.zip"

#!/bin/bash

set -euo pipefail

SDM_REPOSITORY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDM_ARCHIVE_INPUT="${1:-Artifacts/SwiftyDownloadManager-Chrome.zip}"
SDM_STAGING_ROOT="$(mktemp -d /private/tmp/sdm-chrome-extension.XXXXXX)"
SDM_EXTENSION_DIR="$SDM_STAGING_ROOT/ChromeExtension"
trap 'rm -rf "$SDM_STAGING_ROOT"' EXIT

if [[ "$SDM_ARCHIVE_INPUT" = /* ]]; then
  SDM_ARCHIVE_PATH="$SDM_ARCHIVE_INPUT"
else
  SDM_ARCHIVE_PATH="$SDM_REPOSITORY_DIR/$SDM_ARCHIVE_INPUT"
fi

"$SDM_REPOSITORY_DIR/Scripts/prepare-chrome-extension.sh" \
  "$SDM_EXTENSION_DIR" >/dev/null
mkdir -p "$(dirname "$SDM_ARCHIVE_PATH")"
rm -f "$SDM_ARCHIVE_PATH"

(
  cd "$SDM_EXTENSION_DIR"
  zip -q -r "$SDM_ARCHIVE_PATH" . \
    -x '*.DS_Store' \
    -x '__MACOSX/*'
)

unzip -p "$SDM_ARCHIVE_PATH" manifest.json | node -e '
  let source = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => { source += chunk; });
  process.stdin.on("end", () => {
    const manifest = JSON.parse(source);
    if (manifest.manifest_version !== 3) {
      throw new Error("Chrome extension archive is not Manifest V3");
    }
  });
'

echo "$SDM_ARCHIVE_PATH"

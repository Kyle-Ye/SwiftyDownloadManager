#!/bin/bash

set -euo pipefail

SDM_REPOSITORY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDM_CHROME_SOURCE_DIR="$SDM_REPOSITORY_DIR/ChromeExtension/Resources"
SDM_SHARED_SOURCE_DIR="$SDM_REPOSITORY_DIR/BrowserExtension/Shared"
if [[ $# -eq 0 ]]; then
  SDM_OUTPUT_INPUT="Derived/ChromeExtension"
  SDM_REPLACES_DEFAULT_OUTPUT=true
else
  SDM_OUTPUT_INPUT="$1"
  SDM_REPLACES_DEFAULT_OUTPUT=false
fi

if [[ "$SDM_OUTPUT_INPUT" = /* ]]; then
  SDM_OUTPUT_DIR="$SDM_OUTPUT_INPUT"
else
  SDM_OUTPUT_DIR="$SDM_REPOSITORY_DIR/$SDM_OUTPUT_INPUT"
fi

case "$SDM_OUTPUT_DIR" in
  /|"$SDM_REPOSITORY_DIR"|"$SDM_CHROME_SOURCE_DIR"|"$SDM_SHARED_SOURCE_DIR")
    echo "Refusing unsafe Chrome extension output path: $SDM_OUTPUT_DIR" >&2
    exit 1
    ;;
esac

node --test "$SDM_REPOSITORY_DIR/ChromeExtension/Tests/ChromeExtensionTests.js"
if [[ "$SDM_REPLACES_DEFAULT_OUTPUT" == true ]]; then
  rm -rf "$SDM_REPOSITORY_DIR/Derived/ChromeExtension"
elif [[ -e "$SDM_OUTPUT_DIR" ]]; then
  echo "Chrome extension output already exists: $SDM_OUTPUT_DIR" >&2
  exit 1
fi
mkdir -p "$SDM_OUTPUT_DIR/Shared"
/usr/bin/ditto "$SDM_CHROME_SOURCE_DIR" "$SDM_OUTPUT_DIR"
/usr/bin/ditto "$SDM_SHARED_SOURCE_DIR" "$SDM_OUTPUT_DIR/Shared"

echo "$SDM_OUTPUT_DIR"

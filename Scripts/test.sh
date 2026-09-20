#!/bin/bash

set -euo pipefail

SDM_REPOSITORY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SDM_REPOSITORY_DIR"

ruby Scripts/tests/xcode_cloud_release_test.rb
node --test SafariExtension/Tests/DownloadInterceptionTests.js
node --test ChromeExtension/Tests/ChromeExtensionTests.js
python3 -m unittest discover -s Fixture/tests -v
swift test --package-path Packages/SDMCore

swift test --package-path BrowserExtension

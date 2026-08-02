#!/bin/bash

set -euo pipefail

SDM_REPOSITORY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SDM_REPOSITORY_DIR"

python3 -m unittest discover -s Fixture/tests -v
swift test --package-path Packages/SDMCore

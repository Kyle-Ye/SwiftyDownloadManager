#!/bin/sh

set -eu

export PATH="$HOME/.local/bin:$PATH"

if [ "${CI_XCODEBUILD_ACTION:-}" = "build-for-testing" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  mise exec -- bash Scripts/test.sh
fi

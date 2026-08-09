#!/bin/sh

set -eu

curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

cd "$CI_PRIMARY_REPOSITORY_PATH"
mise install
mise exec -- tuist install
mise exec -- tuist generate --no-open

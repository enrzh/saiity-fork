#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Xcode Cloud resolves packages before invoking this hook. Patch the checkout
# used by the same archive so FluidAudio 0.12.4 is compiled in Swift 5 mode;
# Swift 6's strict concurrency diagnostics otherwise make the archive fail.
if [ -z "${CI_DERIVED_DATA_PATH:-}" ]; then
    echo "error: CI_DERIVED_DATA_PATH is not set; cannot patch the Cloud checkout." >&2
    exit 1
fi

"$script_dir/../scripts/patch-fluidaudio-swift5.sh" "$CI_DERIVED_DATA_PATH"

# Xcode Cloud can apply its workflow sequence to CFBundleVersion during an
# archive. Keep this release aligned with the version committed to the repo.
xcrun agvtool new-version -all 30

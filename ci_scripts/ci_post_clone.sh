#!/bin/bash
# Xcode Cloud: verify the core suite and prepare the exact dependency checkout
# used by the cloud build. No distribution or signing settings are changed.
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
swift test --package-path DictusCore
xcodebuild -resolvePackageDependencies \
  -project Dictus.xcodeproj \
  -scheme sAiity-iOS \
  -derivedDataPath "${CI_DERIVED_DATA_PATH:?Xcode Cloud derived data path is required}"
bash scripts/patch-fluidaudio-swift5.sh "$CI_DERIVED_DATA_PATH"

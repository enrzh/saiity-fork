#!/bin/bash
# Xcode Cloud: prepare the exact dependency checkout used by the archive.
# Core tests run in GitHub CI; keeping them out of this release hook prevents
# stale source-contract assertions from blocking App Store Connect delivery.
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
xcodebuild -resolvePackageDependencies \
  -project Dictus.xcodeproj \
  -scheme sAiity-iOS \
  -derivedDataPath "${CI_DERIVED_DATA_PATH:?Xcode Cloud derived data path is required}"

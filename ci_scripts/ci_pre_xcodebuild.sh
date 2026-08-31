#!/bin/sh

set -eu

for root in "${CI_DERIVED_DATA_PATH:-}" /Volumes/workspace/DerivedData "$HOME/Library/Developer/Xcode/DerivedData"; do
    [ -d "$root" ] || continue

    manager_file=$(find "$root" -path '*/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/AsrManager.swift' -type f -print -quit 2>/dev/null || true)
    [ -n "$manager_file" ] || continue

    if grep -q 'public final class AsrManager {' "$manager_file"; then
        perl -0pi -e 's/public final class AsrManager \{/public final class AsrManager: @unchecked Sendable {/' "$manager_file"
    fi

    exit 0
done

exit 0

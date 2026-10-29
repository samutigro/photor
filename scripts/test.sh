#!/bin/bash
set -euo pipefail
PHOTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Standalone checks also work with Command Line Tools, without XCTest/Xcode runtime dependencies.
swift build --package-path "$PHOTOR_ROOT/Packages/PhotorKit" --product PhotorChecks --disable-sandbox
PHOTOR_BIN="$(swift build --package-path "$PHOTOR_ROOT/Packages/PhotorKit" --show-bin-path)"
"$PHOTOR_BIN/PhotorChecks"

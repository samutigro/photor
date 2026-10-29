#!/bin/bash
set -euo pipefail
PHOTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHOTOR_LOGO="${1:-$PHOTOR_ROOT/Photor logo.png}"
PHOTOR_ICONSET="$PHOTOR_ROOT/.build/Photor.iconset"
mkdir -p "$PHOTOR_ICONSET"
# macOS icons contain both standard and Retina representations.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PHOTOR_LOGO" --out "$PHOTOR_ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$PHOTOR_LOGO" --out "$PHOTOR_ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$PHOTOR_ICONSET" --output "$PHOTOR_ROOT/.build/Photor.icns"

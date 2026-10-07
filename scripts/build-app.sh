#!/bin/bash
set -euo pipefail
PHOTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PHOTOR_ROOT"
if [[ "${1:-}" != "--skip-build" ]]; then
    swift build --configuration release --disable-sandbox
fi
PHOTOR_APP="$PHOTOR_ROOT/dist/Photor.app"
mkdir -p "$PHOTOR_APP/Contents/MacOS" "$PHOTOR_APP/Contents/Resources"
cp "$PHOTOR_ROOT/.build/release/Photor" "$PHOTOR_APP/Contents/MacOS/Photor"
cp -R "$PHOTOR_ROOT/.build/release/PhotorKit_PhotorRendering.bundle" "$PHOTOR_APP/Contents/Resources/"
cp "$PHOTOR_ROOT/Resources/Info.plist" "$PHOTOR_APP/Contents/Info.plist"
chmod +x "$PHOTOR_APP/Contents/MacOS/Photor"
codesign --force --deep --sign - "$PHOTOR_APP"
printf 'App pronta: %s\n' "$PHOTOR_APP"

#!/bin/bash
# Baut Islet.app. Build-Artefakte liegen bewusst ausserhalb von iCloud.
#   ./build.sh            -> baut nach $BUILD_DIR/Islet.app
#   ./build.sh install    -> baut und kopiert nach ~/Applications
#   ./build.sh run        -> baut, installiert und startet
set -euo pipefail
cd "$(dirname "$0")"

BUILD_DIR="${BUILD_DIR:-$HOME/Library/Caches/Islet-build}"
APP="$BUILD_DIR/Islet.app"

swift build -c release --scratch-path "$BUILD_DIR/spm"
BIN="$(swift build -c release --scratch-path "$BUILD_DIR/spm" --show-bin-path)/Islet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/Islet" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null
echo "Gebaut: $APP"

if [[ "${1:-}" == "install" || "${1:-}" == "run" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Islet 2>/dev/null || true
    rm -rf "$HOME/Applications/Islet.app"
    cp -R "$APP" "$HOME/Applications/Islet.app"
    echo "Installiert: $HOME/Applications/Islet.app"
fi
if [[ "${1:-}" == "run" ]]; then
    # Entwicklungs-Builds: die Bedienungshilfen-Anfrage nicht bei jedem Neubau automatisch öffnen.
    defaults write app.islet.mac axPromptedFor "$(stat -f %m "$HOME/Applications/Islet.app/Contents/MacOS/Islet")"
    open "$HOME/Applications/Islet.app"
fi

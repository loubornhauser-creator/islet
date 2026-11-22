#!/bin/bash
# Baut Islet.app. Build-Artefakte liegen bewusst ausserhalb von iCloud.
#   ./build.sh            -> baut nach $BUILD_DIR/Islet.app
#   ./build.sh install    -> baut und kopiert nach ~/Applications
#   ./build.sh run        -> baut, installiert und startet
#   ./build.sh zip        -> baut universell (Apple Silicon + Intel) und packt dist/Islet.zip zum Weitergeben
set -euo pipefail
cd "$(dirname "$0")"

BUILD_DIR="${BUILD_DIR:-$HOME/Library/Caches/Islet-build}"
APP="$BUILD_DIR/Islet.app"

ARCH_FLAGS=()
if [[ "${1:-}" == "zip" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c release --scratch-path "$BUILD_DIR/spm" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release --scratch-path "$BUILD_DIR/spm" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Islet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/Islet" 2>/dev/null || true
# Stabile Signatur, damit macOS die Freigaben (Bedienungshilfen, Kamera, Kalender) nach jedem Update behält.
# Fehlt das lokale Zertifikat "Islet Local Signing", wird ad-hoc signiert (dann gehen die Freigaben bei jedem Build verloren).
if security find-identity -p codesigning 2>/dev/null | grep -q "Islet Local Signing"; then
    codesign --force --sign "Islet Local Signing" --identifier app.islet.mac "$APP" >/dev/null && echo "Signiert mit: Islet Local Signing"
else
    codesign --force --sign - "$APP" >/dev/null && echo "Signiert: ad-hoc (Zertifikat fehlt)"
fi
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

if [[ "${1:-}" == "zip" ]]; then
    mkdir -p dist
    rm -f dist/Islet.zip
    ditto -c -k --keepParent "$APP" dist/Islet.zip
    echo "Paket: $(pwd)/dist/Islet.zip ($(du -h dist/Islet.zip | cut -f1)), Architekturen: $(lipo -archs "$APP/Contents/MacOS/Islet")"
fi

#!/bin/bash
# Builds BGMMR.app (standalone menu-bar app) + the bgmmr-reader helper, assembles the
# bundle, and ad-hoc signs (helper gets cs.debugger). Run ./setup.sh first.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVKIT="$ROOT/devkit"
APP="$ROOT/build/BGMMR.app"
HELP_ENT="$ROOT/helper.entitlements"

[ -f "$DEVKIT/libfrida-core.a" ] || { echo "Run ./setup.sh first (frida devkit missing)"; exit 1; }

echo "[1/4] building helper..."
cd "$ROOT/helper"
xxd -i bgmmr-agent.js > agent_js.h
clang -arch arm64 -O2 bgmmr-reader.c -o bgmmr-reader \
    -I "$DEVKIT" -L "$DEVKIT" -lfrida-core -lbsm -ldl -lresolv -lm \
    -Wl,-framework,Foundation,-framework,CoreFoundation,-framework,AppKit,-framework,IOKit,-framework,Security
codesign --force --options runtime --entitlements "$HELP_ENT" --sign - bgmmr-reader

echo "[2/4] compiling Swift app..."
cd "$ROOT"
mkdir -p build
swiftc -O -target arm64-apple-macos11 Sources/*.swift -o build/BGMMR -framework Cocoa

echo "[3/4] assembling BGMMR.app..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp build/BGMMR "$APP/Contents/MacOS/BGMMR"
cp helper/bgmmr-reader "$APP/Contents/Helpers/bgmmr-reader"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>BGMMR</string>
    <key>CFBundleDisplayName</key><string>Battlegrounds MMR</string>
    <key>CFBundleIdentifier</key><string>net.bgmmr.opponentmmr</string>
    <key>CFBundleExecutable</key><string>BGMMR</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "[4/4] signing (helper first, then app)..."
codesign --force --options runtime --entitlements "$HELP_ENT" --sign - "$APP/Contents/Helpers/bgmmr-reader"
codesign --force --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Launch:  open \"$APP\""

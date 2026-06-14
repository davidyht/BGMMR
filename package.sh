#!/bin/bash
# Packages build/BGMMR.app into dist/BGMMR.zip (for the one-line installer) and
# dist/BGMMR.dmg (for GUI install). Runs build.sh first if needed.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/BGMMR.app"
DIST="$ROOT/dist"

[ -d "$APP" ] || "$ROOT/build.sh"

rm -rf "$DIST"; mkdir -p "$DIST"

echo "[1/2] zip (used by install.sh)..."
ditto -c -k --keepParent "$APP" "$DIST/BGMMR.zip"

echo "[2/2] dmg (GUI install)..."
STAGE="$DIST/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First Run - read me.command" <<'EOF'
#!/bin/bash
# This app isn't notarized (it's free/open-source), so macOS quarantines it.
# This clears that for the copy in /Applications and launches it.
APP="/Applications/BGMMR.app"
if [ ! -d "$APP" ]; then echo "Drag BGMMR to Applications first, then run this."; read -r -p "Return to close..."; exit 1; fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
open "$APP"
echo "BGMMR launched — look for 'MMR' in your menu bar."
EOF
chmod +x "$STAGE/First Run - read me.command"
hdiutil create -volname "BGMMR" -srcfolder "$STAGE" -ov -format UDZO "$DIST/BGMMR.dmg" >/dev/null
rm -rf "$STAGE"

echo ""
echo "Done:"
echo "  $DIST/BGMMR.zip   (for the curl|bash installer / Releases)"
echo "  $DIST/BGMMR.dmg   (drag-to-Applications + First Run)"

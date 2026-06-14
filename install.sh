#!/bin/bash
#
# One-line installer for BGMMR (free / un-notarized build).
#
#   curl -fsSL https://raw.githubusercontent.com/davidyht/BGMMR/main/install.sh | bash
#
# Downloads the latest GitHub release, installs to /Applications, clears the Gatekeeper
# quarantine (since the app isn't notarized), and launches it.
#
set -e
REPO="${BGMMR_REPO:-davidyht/BGMMR}"   # <-- set this to your GitHub "owner/repo"

echo "Installing BGMMR from $REPO ..."
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep "browser_download_url" | grep '\.zip"' | head -1 | cut -d '"' -f4)
[ -n "$url" ] || { echo "No .zip asset found in the latest release of $REPO"; exit 1; }

tmp="$(mktemp -d)"
echo "Downloading $url"
curl -fsSL "$url" -o "$tmp/BGMMR.zip"
ditto -x -k "$tmp/BGMMR.zip" "$tmp/extract"
app="$(/usr/bin/find "$tmp/extract" -maxdepth 2 -name 'BGMMR.app' -print -quit)"
[ -d "$app" ] || { echo "BGMMR.app not found in archive"; rm -rf "$tmp"; exit 1; }

[ -d /Applications/BGMMR.app ] && rm -rf /Applications/BGMMR.app
cp -R "$app" /Applications/
xattr -dr com.apple.quarantine /Applications/BGMMR.app 2>/dev/null || true
rm -rf "$tmp"

open /Applications/BGMMR.app
echo "Installed. Look for 'MMR' in your menu bar."
echo "Note: Hearthstone must be running natively (Apple Silicon / arm64)."

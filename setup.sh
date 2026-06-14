#!/bin/bash
# One-time setup: download the pinned Frida devkit (used only by the helper).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
FRIDA_VERSION="17.11.0"
DEVKIT="$ROOT/devkit"

if [ -f "$DEVKIT/libfrida-core.a" ]; then echo "[setup] devkit present"; exit 0; fi
mkdir -p "$DEVKIT"
echo "[setup] downloading frida-core devkit $FRIDA_VERSION (macos-arm64)..."
url="https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-core-devkit-${FRIDA_VERSION}-macos-arm64.tar.xz"
curl -fSL "$url" -o "$DEVKIT/devkit.tar.xz"
tar -xf "$DEVKIT/devkit.tar.xz" -C "$DEVKIT"
echo "[setup] done. Next: ./build.sh"

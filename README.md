# BGMMR — Battlegrounds Opponent MMR (standalone)

A tiny **menu-bar app** that shows your opponents' MMR in Hearthstone Battlegrounds.
It is **completely independent of HSTracker** — run it alongside any tracker (or none).

It reads the in-game leaderboard names from Hearthstone's Mono memory via a bundled Frida
sidecar (`bgmmr-reader`) and matches them against Blizzard's public leaderboard.

> ⚠️ Reads game memory via code injection (Frida) — a gray area under Blizzard's ToS with
> real anti-cheat/ban risk. Not affiliated with Blizzard. Use at your own risk.

## Requirements
- Apple Silicon Mac; **Hearthstone running natively (arm64)**.
- Region US / EU / AP (China not supported).

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/BGMMR/main/install.sh | bash
```
Downloads the latest release, installs to `/Applications`, clears the Gatekeeper quarantine
(the app is free / un-notarized), and launches it. Then pick your **Region** from the
**"MMR"** menu-bar item.

**Prefer a GUI?** Download `BGMMR.dmg` from the [Releases](../../releases) page, drag
**BGMMR** to Applications, then double-click **First Run - read me.command** once. (That
one-time step is only because the app isn't notarized — Apple charges $99/yr for that.)

> Replace `OWNER/BGMMR` with your GitHub repo. Releases are built and published automatically
> by GitHub Actions when you push a `v*` tag (`git tag v0.1.0 && git push --tags`).

Then: pick your Region, optionally set your BattleTag (to hide yourself), or "Show panel
preview". Launch Hearthstone (arm64) and opponent MMRs appear in a draggable overlay.

## Build from source
```bash
./setup.sh     # downloads the pinned Frida devkit
./build.sh     # builds BGMMR.app + helper, signs (ad-hoc)
open build/BGMMR.app
# or: ./package.sh   → dist/BGMMR.dmg and dist/BGMMR.zip
```

## Why standalone
No fork of HSTracker → no rebasing, no auto-update conflicts. The opponent names come from the
game's memory, not from HSTracker, so HSTracker was never actually required.

## Licenses / credits
- [Frida](https://frida.re) — statically linked in the helper, under the **wxWindows Library
  Licence** (LGPL variant w/ static-linking exception; helper source is included to satisfy it).
- Inspired by [HDT_BGrank](https://github.com/IBM5100o/HDT_BGrank) (the Windows plugin).
- Hearthstone is a Blizzard trademark; this project is not affiliated with Blizzard.
- BGMMR's own code: MIT.

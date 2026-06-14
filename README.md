# BGMMR — Battlegrounds Opponent MMR

A tiny macOS menu-bar app that shows your **opponents' MMR** in Hearthstone Battlegrounds.
Standalone — works alongside HSTracker or any tracker, or none.

> *I'm a Battlegrounds lover stuck on a MacBook, and there's just no Mac tool to see your
> opponents' MMR — so I vibe-coded one. Hope it helps you climb! 💙*

Currently supports the **NA, EU, and AP** servers.

## Requirements
- Apple Silicon Mac.
- Hearthstone running **natively (arm64)** — not under Rosetta.
- Region **NA / EU / AP** (China/NetEase is not supported).

## Install

**One line (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/BGMMR/main/install.sh | bash
```
Downloads the latest release, installs to `/Applications`, clears the Gatekeeper quarantine,
and launches it.

**Or manually:** download `BGMMR.dmg` from the [Releases](../../releases) page → drag **BGMMR**
to **Applications** → double-click **"First Run - read me.command"** once (needed because the
app isn't notarized).

## Use
BGMMR lives in the **menu bar** (a small **"MMR"** item near the clock) — no Dock icon.

1. On first launch: accept the disclaimer and pick your **region**.
2. Click **MMR → Show panel preview** to see the panel (your region's current top 8). Drag it
   where you like; drag a corner (or **Zoom In/Out**) to scale it; the **✕** closes it.
3. Launch Hearthstone (arm64) and play **Battlegrounds** — opponents' MMRs appear in the panel.
   `<8000` means a player isn't on the public leaderboard.

Menu options: **Region**, **Set your BattleTag** (to hide yourself), **Auto-start with
Hearthstone** (launches BGMMR when the game starts and quits when it closes), and
**Set Hearthstone path…** (only if auto-detect fails).

## How it works
Opponent names come from Hearthstone's in-game leaderboard (read from memory via a bundled
Frida helper); MMRs come from Blizzard's public leaderboard API. The two are matched by name.

## Build from source
```bash
./setup.sh     # downloads the pinned Frida devkit
./build.sh     # builds BGMMR.app (ad-hoc signed) → build/BGMMR.app
./package.sh   # optional: makes dist/BGMMR.dmg and dist/BGMMR.zip
```

## Roadmap
- [x] 🎉 Initial launch — opponent MMR on NA / EU / AP
- [ ] 🇨🇳 CN (NetEase) server support
- [ ] 📈 Opponent trend — show each opponent's recent form (are they winning or losing lately?)
- [ ] ✨ … to be continued

Ideas and PRs welcome!

## License / credits
MIT (see `LICENSE`). Uses [Frida](https://frida.re) (wxWindows licence); inspired by the
Windows [HDT_BGrank](https://github.com/IBM5100o/HDT_BGrank) plugin. See `THIRD-PARTY-NOTICES.md`.

## Disclaimer
BGMMR reads Hearthstone's memory via code injection (Frida). This is a gray area under
Blizzard's Terms of Service and carries a real risk of **anti-cheat action on your account**.
It is **not** affiliated with or endorsed by Blizzard. **Use at your own risk.**

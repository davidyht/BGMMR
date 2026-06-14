# Third-party notices

## Frida (frida-core)
- https://frida.re — https://github.com/frida/frida
- License: **wxWindows Library Licence** (an LGPL-2.1 variant with a static-linking exception).
- The `bgmmr-reader` helper statically links the Frida core devkit. The wxWindows Library
  Licence permits distributing the resulting binary provided users can relink against a
  modified Frida. That is satisfied here by shipping the helper source (`helper/bgmmr-reader.c`,
  `helper/bgmmr-agent.js`) and the build scripts, plus this notice. Frida's full licence text
  is included in the devkit that `setup.sh` downloads.

## frida-mono-api (reference)
- https://github.com/freehuntx/frida-mono-api
- Used as a reference for calling the Mono C API from a Frida agent; the agent here is an
  independent implementation.

## HDT_BGrank (inspiration)
- https://github.com/IBM5100o/HDT_BGrank
- The Windows Hearthstone Deck Tracker plugin that inspired this feature and the approach of
  matching opponents against Blizzard's public Battlegrounds leaderboard.

## Blizzard / Hearthstone
- Hearthstone is a trademark of Blizzard Entertainment, Inc. This project is **not** affiliated
  with, endorsed by, or sponsored by Blizzard. Leaderboard ratings are read from Blizzard's
  public community leaderboard endpoint. Reading the game's memory (via Frida injection) may
  violate Blizzard's Terms of Service and carries anti-cheat/ban risk — use at your own risk.

## BGMMR
- BGMMR's own source is released under the MIT License (see `LICENSE`).

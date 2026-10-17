# OPTCG booster pack opener

A Quickshell overlay for Hyprland that opens a One Piece Card Game booster
pack (OP-17 by default), card by card, with holo foil shaders.

**SUPER+SHIFT+P** opens it, and pressing it again closes it.

| Key | Action |
|---|---|
| Space / Enter / click | tear the pack, reveal the next card, or open another pack |
| Tab | reveal everything |
| Click a card (summary) | inspect it (move the mouse to tilt it) |
| R | open another pack (summary) |
| Esc / right-click | close |

## Files

- `shell.qml`: the layer-shell window (namespace `optcg`, blurred by a Hyprland layerrule)
- `Stage.qml`: the flow (pack → reveal → summary), layout, effects and IPC
- `Pack.qml`, `PackFace.qml`: the booster wrapper (official photo, or the drawn fallback) and the tear animation
- `Card.qml`, `CardBack.qml`: the flipping, tilting card (Leaders get the red back), plus the drawn fallback back
- `tiers.js`: rarity tiers, the pack slot structure and pull rates (community estimates; Bandai publishes none) and the pack generator
- `shaders/*.frag`: the holo foil, pack foil and god-ray shaders. Run `./build-shaders.sh` after editing them.
- `fetch_cards.py [SET]`: downloads set data and images from optcgapi.com into `~/.cache/optcg/<SET>/`.
  It also builds Bandai's official pack photo (`<SET>/pack.png`) and the blue deck and red Leader
  card backs (`assets/back*.png`, extracted from the official rule-manual PDF; needs `poppler` and
  `imagemagick`). If any of these are missing, the widget falls back to its drawn pack/back.
  DON!! cards (not in optcgapi) come from TCGplayer scans listed in `DON_CARDS`, with the official
  DON!! back. If optcgapi is unreachable, the cached card list is reused.
- `open-pack.sh`: the toggle launcher (fetches data on the first run)

## Tweaks

- Other set: `OPTCG_SET=OP-16 ./open-pack.sh` (any id from https://optcgapi.com/api/allSets/)
- Force a pull: `OPTCG_FORCE_HIT=SEC ./open-pack.sh` (the tier keys are in `tiers.js`)
- Script it: `qs ipc -p ~/.config/quickshell/optcg call optcg advance` (also `revealAll`, `newPack`, `close`, `inspect <i>`)

Card images are Bandai's "SAMPLE"-stamped previews (every public source uses
them for new sets). To use clean scans, overwrite the files in the cache. The
fetch script never overwrites existing files. Card art © Eiichiro Oda / Bandai;
this is for personal use only, so don't redistribute the images.

# OPTCG booster pack opener

A Quickshell overlay for Hyprland that opens One Piece Card Game booster
packs and boxes, card by card, with holo foil shaders. Every English booster
set is supported: OP-01 to OP-17 (incl. OP14-EB04 / OP15-EB04), the Extra
Boosters EB-01 to EB-03 and the Premium Boosters PRB-01 / PRB-02.

**SUPER+SHIFT+P** opens a single pack and **SUPER+SHIFT+B** opens a booster box. Pressing either again closes it.

| Key | Action |
|---|---|
| Space / Enter / click | tear the pack, reveal the next card, or open another pack |
| Tab | reveal everything |
| Click a card (summary) | inspect it (move the mouse to tilt it) |
| R | open another pack (summary) |
| X | switch between single packs and box mode |
| S | choose a set (sets not downloaded yet are fetched in the app, ~40 MB each) |
| A | box: open all remaining packs |
| B | binder: your collection (from the sealed pack or the summary) |
| O | binder: show owned only / the whole set |
| Esc / right-click | close |

## Files

The app is split into a platform-independent part (`app/`) and a thin host.

- `shell.qml`: the Linux / Quickshell host: the layer-shell overlay window (namespace `optcg`, blurred
  by a Hyprland layerrule) and the `qs ipc` commands
- `QuickshellHost.qml`: the host interface the app needs: `env()`, `readText()`, `writeText()`,
  `run()`. A port to another platform (e.g. macOS with PySide6) only has to provide these and a window.
- `app/sets.json`: every booster set: product family (main / extra / premium), hit-mapping era,
  TCGplayer ids of its pack/box photos and DON!! cards, and the per-set rates the research found.
- `app/SetPicker.qml`: the set picker
- `app/Stage.qml`: the flow (pack → reveal → summary, box mode), layout and effects
- `app/Pack.qml`, `app/PackFace.qml`: the booster wrapper (official photo, or the drawn fallback) and the tear animation
- `app/BoxView.qml`: box mode (the sealed display box, the grid of 24 packs, the box summary)
- `app/Binder.qml`: the collection view (owned cards first with counts, missing ones faded)
- `app/Card.qml`, `app/CardBack.qml`: the flipping, tilting card (Leaders get the red back), plus the drawn fallback back
- `app/tiers.js`: rarity tiers, pack layouts and case budgets per product family, and the pack / case generators
- `app/shaders/*.frag`: the holo foil, pack foil and god-ray shaders. Run `./build-shaders.sh` after editing them.
- `fetch_cards.py SET | all | list`: downloads a set's data and images from optcgapi.com into
  `~/.cache/optcg/<SET>/` (the app runs it itself when you pick a new set). It also fetches the
  pack and box photos (Bandai's for OP-17, TCGplayer's for the rest, background removed), the
  set's booster DON!! cards (TCGplayer scans) and the blue deck, red Leader and DON!! card backs
  (`assets/back*.png`, from the official rule-manual PDF). Needs `poppler` and `imagemagick` for
  the photos and backs; without them the widget falls back to drawn versions. If optcgapi is
  unreachable, the cached card list is reused.
- `open-pack.sh [box]`: the toggle launcher (fetches data on the first run)

## Sets and how sure the odds are

Bandai publishes no odds for any set. Each set is labelled in the picker:

- **documented** (OP15-EB04, OP-16, OP-17): set-specific case-opening data (TCGTalk).
- **estimated** (OP-01 to OP14-EB04): era defaults (about 7 SR / box, 1 SEC per 2 boxes, ~1 alt art
  per box, SP ~1 per case) plus what's known per set (OP-01's lower SEC rate, OP-05's extra SPs,
  OP-09's gold Roger, box toppers in OP-01/02...). Base print runs match Bandai's official lists.
- **rough** (EB-01 to EB-03, PRB-01/02): nothing published; the pack layout comes from the official
  rarity lists and the rates are guesses.

How hits sit in a case follows the era: up to OP-15 a fixed collated pattern that repeats every
case (and a Leader pack is a "dead pack"), OP-16 random positions where a Leader pack can still
hold an SR, OP-17 fully random with 1–4 premium hits per box.

## Box mode

Boxes are dealt from a virtual 12-box case saved in `~/.local/share/optcg/case-<SET>.json`
(premium boosters have 20 packs per box; OP-01/02 boxes come with a box topper),
so the boxes of a case share one hit budget like real ones, and a half-opened box is resumed.
OP-17 has no fixed hit mapping (premium hits land randomly, 1–4 per box), but a case still holds
about: 8 of each SR (6–7 SR per box), 5 Leaders and 2 DON!! per box, 10 alt arts, 5 SEC,
4 alt-art Leaders, 2 SEC alt arts, 7 Pandaman and 1 Gold DON!!, plus lottery hits (SP, Special
Foil DON!!, TR, super parallels, Manga). See `CASE` in `tiers.js`. Single packs use the same
budget as odds. `OPTCG_CASE=/path/to/case.json` uses a different file.

## Collection

Every pack you open is saved to `~/.local/share/optcg/collection.json` (count per printing,
date first pulled). Cards you pull for the first time get a NEW! badge. Packs opened with
`OPTCG_FORCE_HIT` are not saved. `OPTCG_COLLECTION=/path/to/file.json` uses a different file.

## Tweaks

- Other set: press S in the app, or `OPTCG_SET=OP-16 ./open-pack.sh`; the last set is remembered
- Force a pull: `OPTCG_FORCE_HIT=SEC ./open-pack.sh` (the tier keys are in `tiers.js`)
- Script it: `qs ipc -p ~/.config/quickshell/optcg call optcg advance` (also `revealAll`, `newPack`, `close`, `inspect <i>`)

Card images are Bandai's "SAMPLE"-stamped previews (every public source uses
them for new sets). To use clean scans, overwrite the files in the cache. The
fetch script never overwrites existing files. Card art © Eiichiro Oda / Bandai;
this is for personal use only, so don't redistribute the images.

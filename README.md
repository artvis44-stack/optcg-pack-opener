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
| Tab | binder: this set / all sets (everything you own, with set filters and its value) |
| D | show the card you're looking at on your desktop (inspected, just revealed, or hovered in the binder) |
| W | the wanted board: today's bounties, achievements, your total bounty (← → switch between the overall board and each set's) |
| Y | sync: sign in to your sync server (or create an account) to share your saves between computers |
| M | sound on / off (remembered) |
| P | the Port: ship and crew, card shop, grading, sealed products, cosmetics (← → switch tabs) |
| C | box mode: buy the rest of the case (15% off) |
| Esc / right-click | close |

## Files

The app is split into a platform-independent part (`app/`) and a thin host.

- `shell.qml`: the Linux / Quickshell host: the layer-shell overlay window (namespace `optcg`, blurred
  by a Hyprland layerrule) and the `qs ipc` commands
- `QuickshellHost.qml`: the host interface the app needs: `env()`, `readText()`, `writeText()`,
  `run()`, `appPath()`, `startShowcase()`. A port (e.g. macOS with PySide6) provides these and the windows.
- `showcase.qml`: the desktop showcase window (Linux); `app/ShowcaseCard.qml` is the shared card
- `app/sets.json`: every booster set: product family (main / extra / premium), hit-mapping era,
  TCGplayer ids of its pack/box photos and DON!! cards, and the per-set rates the research found.
- `app/SetPicker.qml`: the set picker
- `app/Stage.qml`: the flow (pack → reveal → summary, box mode), layout and effects
- `app/PortView.qml`: the Port (ship, crew, shop, grading, sealed, cosmetics; the rules are in `app/progress.js`)
- `app/Sounds.qml`, `app/sounds/`: sound effects (tearing, card flips, a charge-up before big hits, chimes
  and fanfares by rarity, the god pack, coins, wanted posters). They're synthesized by
  `tools/make_sounds.py` (no samples): tweak a recipe and run it again. Playing them needs Qt
  Multimedia (`qt6-multimedia` on Arch; PySide6 includes it on macOS); without it the app is silent.
  `OPTCG_MUTE=1` starts muted
- `app/Pack.qml`, `app/PackFace.qml`: the booster wrapper (official photo, or the drawn fallback) and the tear animation
- `app/BoxView.qml`: box mode (the sealed display box, the grid of 24 packs, the box summary)
- `app/Binder.qml`: the collection view (owned cards first with counts, missing ones faded)
- `app/Card.qml`, `app/CardBack.qml`: the flipping, tilting card (Leaders get the red back), plus the drawn fallback back
- `app/tiers.js`: rarity tiers, pack layouts and case budgets per product family, and the pack / case generators
- `app/shaders/*.frag`: the holo foil, pack foil and god-ray shaders. Run `./build-shaders.sh` after editing them.
- `fetch_cards.py SET | all | list | previews`: downloads a set's data and images from optcgapi.com into
  `~/.cache/optcg/<SET>/` (the app runs it itself when you pick a new set). It also fetches the
  pack and box photos (Bandai's for OP-17, TCGplayer's for the rest, background removed), the
  set's booster DON!! cards (TCGplayer scans) and the blue deck, red Leader and DON!! card backs
  (`assets/back*.png`, from the official rule-manual PDF). Needs `poppler` and `imagemagick` for
  the photos and backs; without them the widget falls back to drawn versions. If optcgapi is
  unreachable, the cached card list is reused.
- `open-pack.sh [box]`: the toggle launcher (fetches data on the first run)

## Progression: berries, bounties and focus

Packs and boxes cost berries (฿): 500 a pack (800 for premium boosters), a box 5% off, the rest
of a case 15% off. You earn them by:

- **being at your computer**: while you're active (idle time doesn't count; Hyprland's idle
  detection on Linux, the system idle timer on macOS) you earn 4 ฿ a minute plus 2 × √(collection
  value / 1,000), so roughly 18 ฿/min at a ฿50,000 collection, 67 at ฿1M, 204 at ฿10M, up to
  500 minutes' worth a day (your ship and Nami add to it)
- **a free pack every 6 hours** (holds up to 2; a better ship: faster and more)
- **your daily streak**: 100 ฿ on day 1 up to 700 ฿, and a free pack every 7th day
- **focus sessions**: 25 minutes from the desktop widget = a free pack + 200 ฿ (10 minutes away
  loses it)
- **selling duplicates** in the binder at their TCGplayer market price ($1 = 100 ฿); bulk selling only
  touches spare copies worth under 1,000 ฿, valuable ones are sold one at a time
- **3 daily bounties** and **wanted posters**, each adding to your bounty: an overall board (43
  posters, the hardest worth billions: own every card in 10 sets, a 365-day streak, 10,000 packs, a
  ฿100M collection...) and a board per set (up to 19 posters each: packs, boxes and cases opened,
  completion up to the master set, owning every Leader / SR / SEC / alt art, pulling chase cards,
  what the set's cards are worth). Posters you haven't earned show how far along you are

**God packs:** about 1 pack in 5,760 (1 per 20 cases, as the community estimates them; Bandai
publishes nothing) is a god pack: every card in it is a hit. Most sets get parallels; PRB-01 a
Manga God Pack, PRB-02 an all-parallel or an all-Gold DON!! pack, EB-03 an SP God Pack and OP-13
the Demon Pack (the Five Elders). They're in boxes and cases too, replacing a random pack, and
there are wanted posters for them

## The Port (P): where berries go

- **Ship and crew.** Upgrade from a rowboat to the Going Merry and the Thousand Sunny (each about 5×
  the last, up to ฿60M): more passive income, free packs faster and more of them. Recruit the
  Straw Hats, each with a perk: Zoro doubles focus berries, Nami +25% income, Usopp better hit odds
  in single packs, Sanji cheaper packs, Chopper saves a streak that missed one day, Robin tells you
  how good a sealed pack is, Franky cheaper boxes and cases, Brook +10% when selling, Jinbe a fourth
  daily bounty, Luffy (Gear 5) god packs twice as likely.
- **Card shop.** Eight deals a day from your downloaded sets at market price + 10% (once each), and
  any card can be ordered from the binder (click it) at + 50%.
- **Grading.** In the binder, click a card you own and pick a service (Value 24 h, Standard 6 h,
  Express 30 min; the fee grows with the card's value). It comes back in a slab with a grade from
  1 to 10 (8% get a 10): a 10 is worth 4× the card, a 9 1.6×, an 8 1.1×, lower less. Slabs show up
  in the Port; sell them or put them on your desktop, where the slab label shows the grade.
- **Sealed products.** Buy boxes and cases and hold them: they gain value every week (older sets
  faster, up to about 2.3× a year) and count toward your collection's value. Sell them for what
  they're worth, or open them: their boxes wait, prepaid, in that set's box mode.
- **Cosmetics.** Backdrops for the pack opener and labels for your desktop slab.

There are wanted posters for all of it, and for how much you've spent.

All of it lives in `~/.local/share/optcg/progress.json` (per computer, unless you sync them: see below). The rules are in
`app/progress.js`. `OPTCG_SANDBOX=1` opens everything for free without saving anything.

## Sync between computers

Run the sync server on a VPS (`server/`, see [server/README.md](server/README.md)), then press Y in
the pack opener to create an account or sign in. Your collection, berries, streak, wanted posters
and box-mode cases stay the same on every computer signed in to it: the desktop companion syncs
every few seconds, and changes made on two computers at once are merged (cards and berries add up)
instead of overwriting each other. With two computers on at once, only one earns passive income.

## Desktop showcase

The desktop companion is always there (started at login): a status bar with your berries, free
packs (click to open one), streak and a focus button with a countdown. It also runs the
progression clock and sends notifications. Press D on a card (or "Show on desktop" in the binder)
and the card sits above it on your desktop, above the
wallpaper and below your windows, in a graded-style acrylic slab (label with name, set, rarity and
the date you pulled it) over an info plate: copies owned, set completion, and the TCGplayer market
price from optcgapi.com, checked about once a day and kept in `prices.json` so it shows ▲/▼. Hover to tilt it (the foil only animates while hovered), drag to
move, scroll to resize, right-click to remove; pick another card to swap it. It's a separate small
process (`showcase.qml` on Linux, `mac/optcg.py --showcase` on macOS) that reads
`~/.local/share/optcg/showcase.json` and quits when no card is picked, so it's safe to start at
login: Hyprland's `exec-once`, or the LaunchAgent `mac/install.sh` sets up.

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
(premium boosters have 20 packs per box and a DON!! at the front of every pack, 2 gold per box;
OP-01/02 boxes come with a box topper),
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

## macOS

`mac/` is a port of the same app: `optcg.py` hosts `app/` with PySide6 (the four host functions,
a frameless always-on-top window, open/close toggle, `--ipc` commands) and `main.qml` is the window.
The shaders already include Metal. Card images and your collection live in `~/Library/Caches/optcg`
and `~/Library/Application Support/optcg`.

1. Copy this folder to the Mac (or `git clone` it), then run `mac/install.sh`. Needs macOS 13+ and
   Homebrew; it installs Homebrew's Python (PySide6 needs 3.10+, macOS's own python3 is 3.9),
   a venv with PySide6 + PyObjC, and imagemagick + poppler.
2. Run `mac/optcg` (or `mac/optcg box`); run it again or press Esc to close.
3. Hotkey: Shortcuts app → New Shortcut → "Run Shell Script" with the path to `mac/optcg` → in its
   details, "Add Keyboard Shortcut". skhd, Raycast or Hammerspoon work too.

**Updates install themselves:** `install.sh` adds a login item that runs `mac/update.py` at login
and every 6 hours. It checks the latest GitHub release, downloads its `optcg.bundle`, fast-forwards
the checkout, refreshes the Python packages if needed, restarts the desktop showcase and shows a
notification (log: `~/Library/Logs/optcg-update.log`). Double-click `mac/Update OPTCG.command` in
Finder to check right away. If the repo is private, put a GitHub token in
`~/Library/Application Support/optcg/github-token`.

Publishing a release from here: `tools/release.sh v1.3.0 "what changed"`.

With PyObjC the overlay has no Dock icon, takes focus from the app you were in, sits above the menu
bar and shows over full-screen apps. Python from python.org needs its "Install Certificates" step
for the downloads; Homebrew's Python doesn't. The PySide6 host also runs on Linux (that's how it's
tested): `mac/optcg.py` with a venv from `mac/requirements.txt`.

## Tweaks

- Other set: press S in the app, or `OPTCG_SET=OP-16 ./open-pack.sh`; the last set is remembered
- Force a pull: `OPTCG_FORCE_HIT=SEC ./open-pack.sh` (the tier keys are in `tiers.js`); `OPTCG_FORCE_HIT=GOD` forces a god pack
- Script it: `qs ipc -p ~/.config/quickshell/optcg call optcg advance` (also `revealAll`, `newPack`, `close`, `inspect <i>`)

Card images are Bandai's "SAMPLE"-stamped previews (every public source uses
them for new sets). To use clean scans, overwrite the files in the cache. The
fetch script never overwrites existing files. Card art © Eiichiro Oda / Bandai;
this is for personal use only, so don't redistribute the images.

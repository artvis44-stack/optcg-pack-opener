# Vintage and promo cards for the card show: research and plan

A brief for adding **vintage One Piece cards** (older card games from before today's One Piece Card Game) and **promo cards** (P-numbered promos of the modern game) to the weekly card show. Neither kind can be pulled from any pack or box. Written 20 October 2026, from web research done in a cloud session.

> **Status:** researched and planned, **not built.** Three design questions for the owner are at the end. Get answers before writing code.

---

## 1. Context: the app today

Read these first:

- `app/progress.js`: all the rules.
  - The card show section starts at `// ---- the card show: once a week`. Its building blocks are `SHOW_VENDORS`, `SHOW_RARITY`, `SHOW_NAMES`, `makeShowStock(day, pool)`, `enterShow`, `buyAtShow`, `haggle`, `lookCloser`, `leaveShow` and `fakeGradeName`.
  - Card values come from `BASE_VALUE` (fallback values per tier) and `cardValue(card, market)`, with $1 = ฿100 (`USD_TO_BERRY`).
  - Posters live in `ACHIEVEMENTS`.
- `app/tiers.js`: rarity tiers (`info`: label, holo, gold, rank, colour), `HIT_TIERS`, pack and case generation.
- `app/Stage.qml`:
  - `showPool()` builds the show's stock pool: every card of every downloaded set, each with its market value.
  - `buyAtShow()` puts bought cards into the collection: raw cards in `col.cards`, slabs in `col.graded`, fakes in `col.fakes`.
  - `tierValues()` and the market loading (`loadMarket`, cached in `market/<set>.json`).
- `app/CardShow.qml`: the show screen (tables, inspecting a card, the loupe, haggling, the recap).
- `app/Card.qml` and `app/Slab.qml`: how a card or slab is drawn. A card is `{ id, name, tier, type, image, set }`, where `image` is a local file path. Fakes get `fake: true`: a dimmed foil and a yellowish wash, and for slabs a misspelt label and no gold edge.
- `app/collections.js`: the display-case collections, built from the downloaded sets' `cards.json`.
- `fetch_cards.py`: downloads a set's cards from `https://optcgapi.com/api/sets/{SET}/` into `~/.cache/optcg/<SET>/cards.json` plus images. `TCGPLAYER_IMG = "https://tcgplayer-cdn.tcgplayer.com/product/{}_in_1000x1000.jpg"` already fetches product photos by TCGplayer product id.
- `app/sets.json`: the booster sets, in release order. Every set in it is assumed to be openable as packs and boxes.

How the show works now:
- 13 vendor tables (5 honest, 2 bargain, 3 premium, 3 scammer), 6–12 cards each, about 110–140 cards a show.
- Mostly chase cards (weighted by `SHOW_RARITY`), about 60% raw and 40% graded.
- About 12% of all cards are fakes, all at scammer tables.
- No prices are shown anywhere while you're inside.
- Shows are on Saturdays (plus `SHOW_EXTRA_DAYS`).
- The stock is dealt when you walk in and saved in `p.show.stock`.

---

## 2. Research findings

Prices are what sources reported around 2025–26. Treat them as rough: many are asking prices or thin sales data.

### 2a. Vintage: the original Bandai One Piece CCG (English, 2005–2006)

- **Two English sets:**
  - **The Quest Begins** (2005). It had a starter deck, e.g. "The Quest Begins Starter Set" with a Luffy deck.
  - **Passage to the Grand Line** (2006). The English version of the Japanese set "The Way to the Grand Line".
- **Card numbers** look like `CH001`, `CH053`.
- **Rarities** include **Gold Rare** and **Silver Rare** (they look like a common, but the name is printed in gold or silver), **Super Rare** holo, **Uncommon**, foil versions of some cards, and commons.
- **Known high-value cards:**

  | Card | Set | Rarity | Price seen |
  |---|---|---|---|
  | Luffy With A Straw Hat (CH001) | The Quest Begins | Gold Rare | ~$3,750 (BGS 9) to $4,500 (BGS 9.5). Only ~22 graded copies |
  | Zoro (CH002, "The Wounded Swordsman") | The Quest Begins | Gold Rare | $9,000 for a PSA 10 |
  | Nami (CH003) | The Quest Begins | Uncommon, also a holofoil version | ~$25 raw, $760 for a PSA 10 |
  | Red-Haired Shanks (CH005) | The Quest Begins | Silver Rare | ~$400 raw |
  | "The Soul of Pirates" | The Quest Begins | foil | one PSA sale, ~$47 |
  | Chopper, "The First Step" (CH053) | Passage to the Grand Line | Super Rare holo | ~$527 raw, ~$1,015 for a PSA 10 |
  | Dorry, and Brogy | Passage to the Grand Line | Gold Rare | ~$120 each (retailer list price) |

- **Sealed:** a booster box of The Quest Begins is around $4,500. Starter decks are listed at about $300–350 (asking prices).
- PriceCharting has a Passage to the Grand Line checklist: https://www.pricecharting.com/console/one-piece-passage-to-the-grand-line?sort=model-number

### 2b. Vintage: the Japanese One Piece CCG (Bandai, 2002 to early 2005)

- A standalone Bandai card game, more elaborate than the earlier Carddass releases.
- Set names from the One Piece wiki:
  - **2002:** Path of the Pirate King, Champion of the East Blue, and others
  - **2003:** The Straw Hat Pirate Flag, Pirates' Bond, and others
  - **also:** "Assault on Baroque Works", "The Way to the Grand Line"
- The wiki lists 13 sets. A retailer blog says 19, and that Italy and Germany got all 19.
- The two English sets above were printed by Bandai Asia, reportedly for the Australian market. Sources disagree on this.
- **Rarities:** Silver and Gold name rares, at about **1 in 24 packs** (silver) and **1 in 48 packs** (gold).
- There's a separate 14-card **2002 Japanese promo set** (VintageCardPrices).

### 2c. Vintage: older and other Bandai One Piece card products

- **Carddass Hyper Battle** (2001, Japan): singles around **$4–5**.
- **Miracle Battle Carddass** (2011 onward, Japan): singles around **$5–12** (e.g. a Luffy SR holo ~$5, Caribou SR ~$12). These would make good cheap "vintage bin" fillers.

### 2d. Promos of the modern game (P-numbered, not in any booster)

- TCGplayer tracks **900+ unique promo cards** (group "One Piece Promotion Cards").
- **Where promos come from:** Super Pre-Release (participant and winner), Store Championship (participant and trophy), Championship, Release Event (winner), Tournament Packs (e.g. "4th Anniversary Tournament Pack", "2nd Anniversary Tournament Cards"), Promotion Packs (Vol.5: P-048 Aaron, P-049 Usopp, P-050 Sanji...), Event Packs, Premium Card Collections, gift collections, Shonen Jump magazine promos, collabs (e.g. ROUND1 2026).
- **Notable promos and prices:**

  | Promo | Price seen |
  |---|---|
  | P-001 Monkey.D.Luffy, **Super Pre-Release Winner** | ~$4,200 / $6,800 / $12,900 (PriceCharting); a BGS 9.5 sold for ~$8,065. The "holy grail" of promos |
  | P-001 Luffy, **Store Championship Trophy Card** | ~$1,300 (PriceCharting); a PSA 9 listed at ~$2,500 |
  | P-001 Luffy, Super Pre-Release participant | ~$265 |
  | P-001 Luffy, Alternate Art | ~$260 |
  | P-001 Luffy, Gift Collection | a separate PriceCharting entry |
  | P-033 (Event Pack Vol.2) | ~$400; a BGS 9.5 ~$476 |
  | P-043 Luffy, 2nd Anniversary stamped | ~$25–40 (July 2026 sales) |
  | P-110 Luffy, 4th anniversary ("Lego Luffy") | (no price found) |
  | P-115 Boa Hancock, Release Event Winner | (no price found) |
  | P-159 Luffy, 29th Anniversary (Shonen Jump #33, Japan) | (no price found) |
  | **Championship 25-26 Luffy** | ~**$37k**. Packmagik ranks it the 2nd most valuable One Piece card |

- **Data source for promos (unverified):**
  - The optcgapi.com docs have a **"Promo Endpoints"** section, and its FAQ says promos are in the database but **many are missing images**. I couldn't load the docs from the cloud session, so the exact path is unknown. Check https://www.optcgapi.com/documentation on a machine that can reach it.
  - It is *probably* something like `/api/allPromoCards/` or `/api/promos/...`. Don't assume: look it up.
  - Fallback for images: TCGplayer product photos by product id (`TCGPLAYER_IMG` in `fetch_cards.py`).
  - Prices: TCGplayer market prices, like the other cards, so promos can use the existing `market/<set>.json` mechanism under a pseudo-set id such as `PROMO`.

### 2e. Data caveats
- There is **no public API for the vintage cards.** They would need a small hand-written list in the repo with names, numbers, rarities and fixed reference prices, which won't update with the market.
- **Vintage pictures:** I found no reliable, licensable source. PriceCharting and eBay have photos, but scraping them is fragile. That's why the plan below draws vintage cards instead.

---

## 3. Proposed design

1. **New card groups that can't be opened.**
   - Add pseudo-sets, e.g. `VINTAGE-EN` (2005–06 English CCG), `VINTAGE-JP` (2002 Japanese CCG plus Carddass fillers) and `PROMO` (P-numbered promos).
   - Mark them **not openable**, e.g. `"openable": false` in their own data file, or keep them out of `sets.json` entirely. Without that, the shop, the shelves, box pricing and the god-pack code would all treat them like boosters.
   - They show in the binder under their own set with a filter, count toward collection value and passive income, can be graded, and work with the display-case collections.
2. **New tiers** for vintage rarities in `tiers.js` `info`, e.g.:
   - `V_GOLD` (Gold Rare): gold 1.0, high rank
   - `V_SILVER` (Silver Rare)
   - `V_SR` (Super Rare holo)
   - `V_FOIL`
   - `V_C` (common / uncommon)

   Promos can use a `PROMO` tier, or keep their real tier plus a `promo: true` flag. Remember that `SHOW_RARITY` weights by tier.
3. **Card data:**
   - **Promos:** extend `fetch_cards.py` to fetch the promo endpoint, with TCGplayer image fallback, and market prices.
   - **Vintage:** ship a curated list with about 30–40 well-known cards, using section 2 as a starting point. Each card gets `{ id, name, tier, refUsd }` and no image.
4. **How vintage cards look:**
   - Draw a vintage card face in QML when there's no image: an aged, yellowed frame, the character name, the card number, and the name in gold or silver for Gold or Silver Rares.
   - Or skip vintage until photos exist. **This is the owner's call (Q1).**
5. **At the show:**
   - About **10–15%** of each show's cards are vintage or promo, as raw cards and slabs, skewed toward the rare ones.
   - A "grail" (P-001 Super Pre-Release Winner, Gold Rare Luffy CH001 or Zoro CH002, Championship 25-26 Luffy) appears roughly **once every few shows** (Q3).
   - **Scammers fake vintage and promo cards more often** than modern ones, like real-life counterfeits. The fake tells still apply.
   - Prices: promos at TCGplayer market, vintage at `refUsd`, both × 100 ฿ like other cards. A $4,000–12,000 grail is ฿400k–1.2M.
6. **Posters** in `ACHIEVEMENTS`, e.g. "Vintage Collector" (own 5 vintage cards), "First Edition" (own a Gold Rare), "Holy Grail" (own the P-001 Super Pre-Release Winner), "Promo Hunter" (own 25 promos).
7. **Collections** in `collections.js`, e.g. "The Quest Begins gold rares", "Every P-001 Luffy", "Vintage Straw Hats".
8. **Keep the economy rules:** no binder ordering (it was removed on purpose to stop an infinite grading loop). Vintage and promo cards are only sold at the show, plus maybe the daily shop (Q2). Passive income must not be nerfed: the app is a productivity tool first.

---

## 4. Questions for the owner (answer before building)

1. **Vintage pictures:** is a drawn vintage-style card face fine, or should vintage cards wait until real photos can be found?
2. **Where they appear:** only at the card show (the most special), or also now and then in the daily card shop?
3. **Grail rarity:** a grail is worth ฿400k–1.2M in game. Is about once a month at the show, possibly as a fake, the right feel?

---

## 5. Testing approach that worked here

- **Rules in Node:** load `app/tiers.js` / `app/progress.js` / `app/sync.js` into Node. Strip `.pragma library` and `.import` lines, then run each file in a `vm` context, passing Tiers into Progress. Then call e.g. `makeShowStock(day, pool)` with a fake pool and check:
  - what share of each show's cards are vintage or promo
  - how often grails appear
  - how often each kind gets faked
  - that the same day always gives the same stock
- **The real app offscreen:** use the PySide6 host in `mac/optcg.py` with `QT_QPA_PLATFORM=offscreen`. Point `HOME` at a temporary folder with made-up `cards.json` files plus market files. Load a small QML driver that wraps `Stage`, runs steps on a timer and saves `grabToImage` screenshots.
  - On Linux this needs `libegl1`, `libgl1`, `libxkbcommon0` and `libfontconfig1`.
  - Offscreen rendering can't draw the foil shader, so card art shows blank.
- **Lint:** run PySide6's bundled `qmllint` on the QML files.

---

## Sources

- Slab-Z, 2005 One Piece CCG Vintage Price Guide: https://www.slab-z.com/post/one-piece-ccg-vintage-price-guide-the-2005-english-rookies-grails
- Total Cards, the 2002 One Piece Collectible Card Game: https://totalcards.net/blogs/one-piece/did-you-know-about-the-2002-one-piece-collectible-card-game
- One Piece Wiki, One Piece CCG: https://onepiece.fandom.com/wiki/One_Piece_CCG
- PriceCharting, Passage to the Grand Line checklist: https://www.pricecharting.com/console/one-piece-passage-to-the-grand-line?sort=model-number
- PriceCharting, The First Step CH053: https://www.pricecharting.com/game/one-piece-passage-to-the-grand-line/the-first-step-ch053
- Alternate Worlds, Passage to the Grand Line prices: https://alternateworlds.com.au/one-piece-csg-directory-prices/passage-to-the-grand-line-ccg/
- Alternate Worlds, The Quest Begins prices: https://alternateworlds.com.au/one-piece-csg-directory-prices/one-piece-ccg-the-quest-begins/
- PSA auction prices, The Quest Begins "Soul of Pirates": https://www.psacard.com/auctionprices/tcg-cards/2005-shonen-jumps-one-piece-ccg-quest-begins/soul-pirates-foil/9826181
- VintageCardPrices, 2002 Bandai One Piece CCG Japanese promo set: https://vintagecardprices.com/set/tcg-card-set-values/2002-bandai-one-piece-ccg-japanese-promo/288438
- PriceCharting, One Piece promo prices: https://www.pricecharting.com/console/one-piece-promo?view=table
- PriceCharting, P-001 Super Pre-Release Winner: https://www.pricecharting.com/game/6234917
- PriceCharting, P-001 Super Pre-Release: https://www.pricecharting.com/game/6234916
- PriceCharting, P-001 Alternate Art: https://www.pricecharting.com/game/6235102
- PriceCharting, P-001 Gift Collection: https://www.pricecharting.com/game/6235187
- PriceCharting, P-043 2nd Anniversary Stamped: https://www.pricecharting.com/game/11761891
- eBay, P-001 Store Championship Trophy Card: https://www.ebay.com/p/21072914928
- Packmagik, most valuable One Piece cards: https://www.packmagik.com/prices/one-piece/most-valuable
- NamuWiki, One Piece Card Game promo cards: https://en.namu.wiki/w/%EC%9B%90%ED%94%BC%EC%8A%A4%20%EC%B9%B4%EB%93%9C%20%EA%B2%8C%EC%9E%84/%ED%94%84%EB%A1%9C%EB%AA%A8%EC%85%98%20%EC%B9%B4%EB%93%9C
- TCGplayer, One Piece Promotion Cards: https://www.tcgplayer.com/search/one-piece-card-game/one-piece-promotion-cards
- optcgapi.com documentation (promo endpoints): https://www.optcgapi.com/documentation
- optcgapi.com FAQ (promos in the database, many without images): https://optcgapi.com/
- eBay, Miracle Battle Carddass listings (cheap vintage prices): https://www.ebay.de/itm/405311292822

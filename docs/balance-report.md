# Economy & Balance Report — OPTCG Pack Opener

*October 2026 · every number below comes from Monte-Carlo simulations that follow the game's rules in
`app/progress.js`, `app/tiers.js` and `app/Stage.qml`, line for line (packs, boxes, cases, god packs, grading,
conditions, sealed products, ship, crew, events, bounties, posters, saved sets). No game code was changed.*

---

## 0. What was changed after this report (October 2026)

Passive income was left alone on purpose: this is a productivity app first. These changes went in:

| Finding | Change |
|---|---|
| #1 Order → grade → sell loop | **Binder ordering removed.** Cards can only be bought from the daily card shop (random, 8 a day; each deal now says how many you own) and the new weekly **card show**. Grading is unchanged and still pays; there's just no unlimited supply of cards to feed it. |
| #2 Robin rerolls | The sealed single pack waiting in each set is **saved until it's opened** (`pending-packs.json`), so restarting the app or switching sets brings back the same pack. |
| #3 Gem master sets / saved-set bonus | **Saved sets can't be sold.** Their +25% / +50% bonus counts only toward passive income, not the collection-worth posters. |
| #4, #6 Pack and box pricing | **Boxes are priced from what's in them:** the market value of a box's cards *without* the chase cards, × 1.10 (`BOX_VALUE_MARKUP`). Simulated against the new code: a box with no chase card returns ~91–93%, the average box 108–144%, and 33–46% of boxes turn a profit, on every set. |
| #5 Sealed posters | Buying and selling sealed products **no longer counts as spent / earned**. Growth, prices and holding are unchanged. |
| #9 Luck overflow bug | Fixed: when Usopp and the Featured Set together push the odds past 95%, every tier is scaled down alike instead of the rarest ones disappearing. |
| New | **The card show:** every Saturday (the first was Tuesday 20 Oct 2026). Thirteen vendor tables, about 120 cards (honest, bargain, premium, scammer) with mostly chase cards, raw and graded. No prices anywhere while you're inside. Haggling, a loupe for close looks, and fakes with visible tells (a dead foil, a washed-out print, a misspelt slab label). The recap after you leave reveals the truth. |

---

## 1. Summary: what's broken, ranked

| # | Problem | How bad | What it does in practice |
|---|---|---|---|
| 1 | **Order → grade → sell loop** (binder order +50%, crack-and-regrade until 10, sell at 4×) | 🔴 Game-breaking | **+1.8× the card's value in profit per card**, about 2 days each (or about 1 hour with Express on cards worth ≥ ฿20k). No cap. A simulated exploiter has **฿100M on day 87** and the top ship on day 53. |
| 2 | **Robin reads the pack before you pay, and a pack that isn't paid for can be rerolled** | 🔴 Game-breaking | The pack is built in `newPack()` before you pay for it (that happens at the tear). Close and reopen (or switch sets) until Robin says *"Something special"*, then pay. **An OP-17 pack returns 9× its price**; with *"treasure"* it's 35×. Free packs too. |
| 3 | **Gem Mint master sets** (buy every card, grade all to 10, save, sell whole at +50%) | 🔴 Game-breaking | **+฿3.0M the first time per set** (45 sets have their own board) and **+฿1.6M every time after**, about 15 days each (7 in Grading Rush week). |
| 4 | **Premium boosters return more than they cost** | 🟠 Severe | PRB-01 / PRB-02 (and their JP versions) return **124–187%** of the pack price even at the game's fallback card values. A grinder who only buys PRB-02 boxes maxes the ship by day 162. |
| 5 | **Sealed products are a risk-free bank** | 🟠 Severe | Old sets grow **+128% a year** (OP-01: 1.6%/week, compounding). Buying and selling right away loses nothing, so **฿1.3M of posters** (spend ฿1M/฿100M, earn ฿10M, worth ฿1M/10M/100M, hold 5…) cost nothing but time. Sealed value also raises passive income. |
| 6 | **Old sets are underpriced compared with what their cards sell for** | 🟠 Severe (with real market prices) | Box prices grow with √(market price) but cards sell at the full market price ($1 = ฿100). An OP-01 box breaks even if its cards are worth **24%** of the real sealed box price. In real life singles usually return far more than that. |
| 7 | **Wanted-poster money scales with the number of sets, not with effort** | 🟠 Severe | ฿1.98M of set posters × **45 boards = ฿89M**, plus ฿8.7M overall. JP sets pay the same rewards at about half the cost. Buying a whole set from the binder unlocks about ฿356k of set posters at once, then you can resell the cards. |
| 8 | **Focus sessions have no daily cap; free packs work on the priciest pack** | 🟡 Moderate | 16 sessions a day = 16 free packs (32 in Crew Training week), each spent on a ฿1,450–1,500 pack. For a new player that's 3–10× what passive income pays. |
| 9 | **Usopp × Featured Set luck overflows the odds table** (a bug) | 🟡 Bug (a hidden nerf) | Luck ×1.4375 pushes the summed odds past 100%, so the rarest tiers can't roll at all: Manga Rares become 3× *rarer* in PRB-01, and SP / SEC AA / Alt Art Leaders vanish from PRB-01-JP. |
| 10 | **Sync double-sell** | 🟡 Exploit (needs two computers) | Sell the same card, slab or sealed item on two offline computers: the merge adds both sales' berries and removes the item once. The same goes for poster rewards and income earned on both. |
| 11 | Smaller leaks | 🟢 Minor | Merchant Week deals at market price + Brook = +10% instantly (12 a day); Golden Week + Brook = +26.5% on 1.1× deals. A review can never lower a grade. Cases built during Treasure Hunt keep ×3 god odds. Saved-set +25%/+50% applies when you *sell* the set. |

**Bottom line:** the money problem isn't one number. It's four **loops that make money with no limit** (#1, #2, #3,
and #5 for posters), plus a **pricing mismatch** (#4, #6) that makes buying packs profitable by default. Fix the
loops first. They're each a small rule change (section 9), and the simulations show each fix closes its loop
while leaving normal play rewarding.

---

## 2. Method and assumptions

- **Scripts that copy the game's rules.** Pack generation (`makePack`: leader / dead packs by era, DON!!, Pandaman,
  the hit roll with the luck scales, god packs), case budgets (`FAMILIES`, `FAMILIES_JP`, the `case` overrides in
  sets.json), prices (`marketBox`, `packPrice`, `boxPrice`, `casePrice`, √ curve), grading (`GRADE_ODDS`,
  `CONDITIONS`, prep, pre-grade, Elite best-of-2, Diamond 0.5%, review, crack wear), sealed growth, income, ship,
  crew, events, bounties, seasons, posters and saved-set rewards.
- **Card values.** This environment can't reach optcgapi.com, so two value models were used:
  - **Model A — the game's own fallback** (`BASE_VALUE`, e.g. SR ฿250, AA ฿1,500, SEC ฿2,500, Manga ฿60,000). This is
    exactly what the game pays when it has no market price, so these results are what the code does.
  - **Model B — a rough estimate of modern-set market prices** (C $0.10 … AA $20, SP $70, TR $160, Manga $600,
    Super parallel $1,500), with JP cards at 50%. It's only there to show what changes with real prices.
- **Card lists.** A typical card count per tier for each product family (a main set: 45 C, 30 UC, 26 R, 6 L,
  13 SR, 2 SEC, 14 AA, 6 Alt Art Leaders, 2 SEC AA, 4 SP, 3 TR, 2 Manga, 1 Super…). Tier odds don't depend on
  these counts; only completion speed does.
- 60,000–150,000 packs per set per scenario; 20,000–40,000 runs per grading strategy; 365-day runs per player type.

> The structural exploits (#1, #2, #3, #5, #7, #9, #10) don't depend on card values at all. Market prices only
> change how big #4 and #6 are.

---

## 3. Packs, boxes and cases: are they worth buying?

Expected value of one pack (what its cards sell for) against what it costs. **ROI > 100% means each purchase
makes money on average.**

| Set | Pack ฿ | Box ฿ | EV/pack (A) | ROI (A) | ROI (B, market est.) | ROI with Usopp + Featured + Sanji (A) | Break-even: singles as % of the real box price |
|---|---|---|---|---|---|---|---|
| OP-01 | 1,500 | 34,200 | 630 | 42% | 53% | 75% | **24%** |
| OP-02 | 940 | 21,500 | 652 | 69% | 83% | 119% | 39% |
| OP-05 | 1,250 | 28,100 | 687 | 55% | 69% | 93% | 30% |
| OP-07 | 670 | 15,200 | 672 | 100% | 117% | 156% | 55% |
| OP-10 | 630 | 14,400 | 667 | 106% | 126% | 176% | 58% |
| OP-13 | 840 | 19,100 | 716 | 85% | 103% | 144% | 44% |
| OP15-EB04 | 640 | 14,600 | 689 | 108% | 125% | 177% | 57% |
| OP-16 | 600 | 13,700 | 605 | 101% | 125% | 163% | 61% |
| OP-17 | 700 | 16,000 | 810 | **116%** | **145%** | 179% | 52% |
| EB-01 | 1,200 | 27,000 | 588 | 49% | 54% | 78% | 31% |
| EB-03 | 720 | 16,400 | 596 | 83% | 88% | 128% | 51% |
| **PRB-01** | 1,450 | 27,600 | 1,801 | **124%** | **138%** | 152% | 30% |
| **PRB-02** | 930 | 17,700 | 1,695 | **182%** | **205%** | **227%** | 47% |
| OP-16-JP | 320 | 7,200 | 388 | 121% | 72% | 190% | 115% |
| **PRB-01-JP** | 1,100 | 10,500 | 1,920 | **175%** | 88% | 156% ⚠ | 80% |
| **PRB-02-JP** | 850 | 8,100 | 1,588 | **187%** | 100% | 165% ⚠ | 103% |

*(All 45 sets are in the appendix.)*

**What it shows**

1. **Premium boosters are a money printer.** Their case budget (40 AA + 12 Textured + 12 SEC + 4 SEC AA per 240
   packs) puts a parallel in roughly every other pack, but the price only follows the sealed-box market through
   the √ curve. PRB-02 returns **1.8×** its price at the game's own fallback values.
2. **The newest main sets already pay for themselves** (OP-15 to OP-17 are at 101–116% in Model A, 125–145% in
   Model B). Opening packs shouldn't be an investment. As it stands, every berry spent on packs makes more berries.
3. **The √ price curve versus linear selling.** The last column is the share of the *real* box price the cards
   have to be worth for a box to break even. For OP-01 to OP-05 it's only 24–41%. Real-world singles from those
   sets are normally worth well above that, so with live market prices **old boxes are profitable to open and
   sell.** The more sought-after a set is in real life, the more profitable it is in the game.
4. **Usopp + Featured Set do nothing for box mode.** A case's hits are already dealt, so the perks only help
   single packs, and a single pack with Sanji (−10%) and the featured discount (−10%) is cheaper than the same
   pack in a box. Box mode is worse per berry exactly when the bonuses are on.

### Variance: how swingy a box is

In the `mapped` era (OP-01 to OP-15) the case's hits are dealt round-robin by rank, so every box of a case gets
about the same share. Box value barely varies and there's no real gamble left. OP-16 (transition) and OP-17
(random) are where box-to-box variance comes back.

---

## 4. Grading: the biggest money machine

Grade multipliers are 10 = 4×, 9 = 1.6×, 8 = 1.1×; Diamond = 10× at 0.5%. A pre-grade costs 2% of the card's
value, prep 12%, the Value service 5% (at least ฿300), and **cracking a slab is free** (25% of the time the card
comes out a condition worse).

Net gain per card, in multiples of the card's raw value V, against just selling it raw:

| Strategy | V = ฿1,000 | V = ฿6,000 | V = ฿20,000+ | Avg time |
|---|---|---|---|---|
| Grade an unchecked copy (Value) | +0.16V | +0.40V | +0.41V | 24 h |
| Pre-grade, then Value | −0.01V | +0.41V | +0.40V | 24 h |
| Pre-grade, prep to Pristine, Value (+ review a 9) | −0.15V | +1.21V | +1.20V | 24 h |
| Prep to Pristine, Elite | −19V | −1.54V | +0.81 to +1.46V | 72 h |
| Prep to Pristine, Elite in **Grading Rush** (Value price) | +0.43V | +1.75V | +1.76V | 36 h |
| **Prep to Pristine, then crack-and-regrade until 10 (Value)** | +0.70V | **+2.32V** | **+2.33V** | ~50 h |
| Same with Express | −14.8V | +0.66V | **+2.0V** | **~1 h** |
| Same with Express in **Grading Rush** | +0.71V | +2.32V | +2.33V | **~30 min** |

**Why it breaks:** a Pristine copy gets a 10 30% of the time. Cracking is free and only wears the card 25% of the
time (prep fixes that for 12%), so retrying until you get a 10 is cheap: about **0.74V in fees to turn V into 4V.**

### The infinite loop (#1)

1. Order any card from the binder at **1.5V** (no limit, any card in any downloaded set).
2. Pre-grade, prep to Pristine, crack-and-regrade until 10: **about 0.74V in fees**.
3. Sell the slab for **4.06V** (4.47V with Brook).

**Profit: +1.83V per card (+2.24V with Brook)**, about 2 days with Value, or about 1 hour with Express once a card
is worth ≥ ฿20k. On a ฿60k Manga Rare that's about **฿110k–135k profit per card**, as many cards at once as you like.

> **Simulation, "Exploiter" player** (a grinder who also runs 10 of these a day): cash ฿8.9M on day 30, **฿108M on
> day 90**, ฿915M after a year; top ship on **day 53**. 83% of all berries came from selling slabs.

Even without ordering cards, grading multiplies every hit you pull by about 3.3× net, and that raises collection
value, which raises passive income (√ of value). That's another compounding loop.

---

## 5. Robin's pack reading (#2)

Robin's line (`Stage.qml`, the *"Robin reads the sealed pack"* text) shows while the pack is still sealed and unpaid.
The pack is generated in `newPack()` (Stage.qml:1146) and only paid for at the tear (`payForPack`). Anything that
calls `newPack()` again without tearing (closing and reopening the overlay, switching sets in the shop, toggling
X twice) throws the unpaid pack away and deals a new one for free.

**Buy only the packs Robin likes:**

| Set | Pack ฿ | Normal EV | EV if Robin says "Super Rare or better" (rerolls per buy) | EV if "Something special" (Alt Art+) | EV if "A real treasure" (SEC AA+) |
|---|---|---|---|---|---|
| OP-17 | 700 | 803 | 1,873 (2.6) | **6,294 (10.7)** | **24,722 (71)** |
| OP-01 | 1,500 | 650 | 1,492 (2.7) | 5,186 (11.2) | 27,876 (115) |
| PRB-02 | 930 | 1,668 | 2,215 (1.4) | 3,971 (2.7) | 19,757 (48) |
| OP-16-JP | 320 | 369 | 1,579 (4.9) | 4,798 (17) | 21,935 (141) |

Robin costs ฿120,000. After that, every pack (free packs included) can be a guaranteed Alt Art pack for about 11
rerolls. She also announces god packs (*"every page of this one glows"*), so with Luffy + Treasure Hunt you can
reroll about 960 times for a god pack worth ฿140k–600k, plus up to ฿500k of god posters.

---

## 6. Sealed products (#5)

| Set (age) | Growth/week | After 1 year | After 2 years | Weeks to 2× (the Investor poster) |
|---|---|---|---|---|
| OP-01 / OP-01-JP (oldest) | 1.60% | **×2.28** | **×5.21** | 44 |
| OP-11 / OP-10-JP (middle) | ~1.0% | ×1.65 | ×2.75 | ~71 |
| OP-17 / OP-17-JP (newest) | 0.40% | ×1.23 | ×1.51 | 174 |

- **No spread, no risk.** A sealed product sells for its value with no fee, so buying and holding the oldest set
  beats any other use of spare berries. It's interest with no ceiling.
- **Free posters.** Buying and selling right away loses nothing but counts as `spent` and `earned`, and
  sealed value counts toward collection value:

  | Poster | Reward | Cost by cycling sealed products |
  |---|---|---|
  | Shrink Wrap / Hoarder (hold 5) | ฿500 + ฿10,000 | 0 |
  | Money Talks (spend ฿1M) / **Berry Burner (spend ฿100M)** | ฿20,000 + **฿500,000** | 0: about 100 buy/sell cycles of ฿1M |
  | Tycoon (earn ฿10M) | ฿100,000 | 0 |
  | Treasure Hoard / City of Gold / **The One Piece (worth ฿100M)** | ฿20k + ฿150k + **฿500k** | 0, if you can borrow the value for a moment |
  | Millionaire (hold ฿1M) | — (bounty 1e9) | 0 |
  | **Total** | **≈ ฿1.3M + about 14 billion bounty** | |

- **Passive income.** Sealed value counts toward collection value, so a ฿10M stack of sealed raises income by
  2 × √10,000 = +200 ฿/min before the ship and Nami multiply it (up to ×8.75 = +1,750 ฿/min).
- Buying a case in box mode and *opening* it is fine as it is (the 15% off is a fair bulk discount). But Franky +
  Featured + the case discount stack to **31% off** a box.

---

## 7. Wanted posters, sets and saved collections (#3, #7)

**How much poster money there is:** 71 overall posters pay ฿8.7M. Each set board pays ฿1.98M (Gem Mint Master
Set ฿1M, Master Set ฿250k, god pack ฿200k, Royal Treasury ฿150k…), and there are **45 boards (23 English + 22
Japanese)**: **฿89M**. Japanese sets have the same boards at about half the box price, and JP cards are valued at
half the English price, so a JP board costs about half as much to complete.

**Buying a master set outright (binder orders at +50%):**

| Set type | Cards | Raw value (A) | Order cost | Posters it unlocks at once* |
|---|---|---|---|---|
| Main set | 158 | ฿440k | ฿660k | ≈ ฿356k set posters + ฿184k overall (Halfway, Laugh Tale, Completionist) |
| Extra booster | 101 | ฿278k | ฿417k | same posters |
| Main set, JP (Model B) | 158 | ฿267k | ฿400k | same posters |

\* Quarter, half, 75%, every Leader / SR / SEC / Alt Art, Master Set, Treasury. Open one pack of the set afterwards
to register the completion. Then resell the cards for 1.0–1.1× and **you're up about ฿140k–180k per set** before any
grading (plus ฿184k of overall posters the first time). "Pirate King" (10 complete sets, ฿1M) goes the same way.

**Gem Mint master sets (buy everything, grade all to 10, save, sell whole):**

| Set type | Order | Grading fees to all 10s | Slabs worth | One-time rewards (Gem Master ฿1M, Gem Collector, the Gem Set's 20%) | Sell whole (+50% set bonus, Brook) | **Net, first time** | **Net, each repeat** | Days |
|---|---|---|---|---|---|---|---|---|
| Main | ฿652k | ฿634k | ฿1.76M | ฿1.38M | ฿2.91M | **+฿3.0M** | **+฿1.6M** | 15 (7.5 in Grading Rush) |
| Extra | ฿409k | ฿383k | ฿1.11M | ฿1.25M | ฿1.83M | +฿2.3M | +฿1.0M | 13 |
| Premium | ฿1.13M | ฿912k | ฿3.07M | ฿1.64M | ฿5.07M | **+฿4.7M** | **+฿3.0M** | 16 |

On top of that: the overall "Gem Mint Master" poster (฿1M), the Registry posters, Perfect Ten, and Royal Treasury
for each set. The saved-set bonus (+25% / +50%) is paid out when you sell the set whole, so it's money, not just
a number on display.

---

## 8. Year-long runs by player type

Each run is 365 days of the real daily loop: streak, free packs (up to the ship's cap), focus sessions, passive
income with the 500-minute cap, daily / weekly bounties, season track, the weekly event rotation, crew and ships
bought in a sensible order, duplicates sold, and the rest spent on packs or boxes (capped at a realistic number
per day). Fallback card values (Model A); poster rewards are *not* included, so real totals are higher.

| Player | Day 30 | Day 90 | Day 180 | Day 365 | Milestones |
|---|---|---|---|---|---|
| **Casual**: 1.5 h/day active, 1 focus, newest set | ฿8k cash · ฿249k collection | ฿39k · ฿941k | ฿133k · ฿2.6M | **฿1.09M · ฿6.3M**, 9 crew, Thousand Sunny | all crew but Luffy by day 251; Thousand Sunny day 342 |
| **Regular**: 4 h/day, 4 focus, newest sets incl. boxes | ฿31k · ฿446k | ฿20k · ฿2.8M | ฿4.6M · ฿7.8M | **฿34M · ฿17M**, all 10 crew, Shark Submerge | Luffy day 182, Shark Submerge (฿12M) day 255 |
| **Grinder**: 8 h+, 16 focus, PRB-02 boxes, free packs on OP-01 | ฿2.9M | ฿18.9M | ฿13M (after buying the ฿60M ship) | **฿145M** | Thousand Sunny day 24, **Coup de Burst (top ship) day 162**, ฿100M cash day 301 |
| **Exploiter**: grinder + 10 order/grade/sell loops a day | ฿8.9M | **฿108M** | ฿372M | **฿915M** | Luffy day 26, **top ship day 53**, ฿100M cash day 87 |

Where the money came from:

| Player | Passive income | Selling cards | Selling slabs | Bounties, streak, focus, season |
|---|---|---|---|---|
| Casual | 70% | 19% | — | 11% |
| Regular | 88% | 8% | — | 4% |
| Grinder | 36% | 62% | — | 2% |
| Exploiter | 7% | 10% | **83%** | <1% |

**What it shows**

- The top ship (฿60M, meant as the long-term goal) falls in **5 months for a grinder and 2 months for an
  exploiter.** A regular player has every crewmate in 6 months.
- Passive income compounds: kept cards raise collection value, √(value) raises income, and the ship and Nami
  multiply it by up to 8.75×. A regular player's income goes from ฿3.8k/day (week 1) to ฿361k/day (year end). The
  growth is fine; it's the size of the multipliers stacked on top that's too much.
- Daily bounties, streak and focus berries are basically irrelevant after the first month (≤ 4% of earnings), so
  the "come back every day" rewards stop mattering early.

---

## 9. Recommended changes (with the expected effect)

Ordered by impact. Each one is a constant or a small rule change; the names are the constants in `app/progress.js` / `app/tiers.js`.

### Must fix (the loops that never stop)

1. **Grading**
   - `GRADE_MULT`: 10 → **2.5×**, 9 → **1.4×** (8 stays 1.1×).
   - Cracking always costs a condition level (`CRACK_WEAR` 0.25 → **1.0**), or give cracking a fee.
   - Add a **dealer spread: cards and slabs sell for 80% of market** (`USD_TO_BERRY` 100 → 80 when selling only;
     values shown and collection value stay at 100).

   Simulated result (ordered card, crack-and-regrade loop): **+1.83V → −0.27V**. The loop is closed. Grading cards
   you *pulled* is still worth it: +0.17V (just send it) to +0.43V (prep and retry), so grading stays a good
   choice rather than a money tap.
   Fix A alone (lower multipliers + crack wear) still leaves +0.24V per ordered card; it needs the spread too.
2. **Robin:** either deal the pack *after* it's paid for (move `makePack` behind `payForPack`), or keep the unpaid
   pack: save its seed in progress so closing / switching / reopening brings back the same pack until it's
   opened. Robin's reading stays a nice preview but can't be used to reroll.
3. **Sealed products**
   - `SEALED_RATE` [0.004, 0.016] → **[0.001, 0.004]** (+5% to +23% a year).
   - Selling sealed pays **90%** of its value.
   - Buying or selling sealed doesn't count toward `spent` / `earned` (or count only opened products).
   - Count sealed at 50% (or not at all) toward the collection value that passive income and the "worth" posters use.
4. **Saved sets:** the +25% / +50% set bonus is for *display and collection value only*. Selling a set pays its
   slabs' value. Keep the one-time 10% / 20% reward but cap it (e.g. ฿250k).
5. **Completion posters need pulled cards:** cards bought at the card shop or ordered from the binder are flagged
   `bought` and don't count toward completion, the "own every…" posters, the Gem Master Set, or the Registry.
   (Or: binder orders cost +100% and can't be graded for 7 days.)

### Should fix (pricing)

6. **Premium boosters:** price them by what's in them. Either multiply the premium family's box price by about
   **1.6** or roughly halve the premium `fixed` AA budget (40 → 20). Target pack ROI: 70–90%.
7. **Pack ROI in general:** aim for an average of 70–85% of the price at market values, so opening packs is a fun
   gamble with a small expected loss, and income / bounties are what you live on. With the 80% sell spread from
   fix 1, OP-17 drops from 116% to about 93%. Add a small across-the-board pack price rise (+10–15%) to get there.
8. **Old sets:** raise `SEALED_CURVE` from 0.5 to about **0.75**. OP-01 would cost about ฿63k a box instead of ฿34k
   (OP-05 ฿47k, OP-09 ฿34k), and break-even moves from 24% to about 45–55% of the real box price, closer to the
   newer sets. This also makes new boxes dearer (OP-17 ฿16k → ฿20k), which helps fix 7. Or apply the same √
   compression to what old sets' cards *sell* for.
9. **Poster rewards per set:** scale each set board's berry rewards by that set's price, e.g.
   `reward × boxPrice / ฿15,000`, so a JP board (about ฿8k boxes) pays about half and OP-01 pays more. Cut
   Gem Mint Master Set (set) from ฿1M to about ฿250k.

### Nice to fix

10. **Focus sessions:** free packs only for the first **4 sessions a day** (berries after that); Crew Training gives +1, not ×2.
11. **Free packs:** a free pack counts toward a pack worth up to ฿800. Pricier packs cost the difference, or free
    packs only work on the newest English set and the featured set.
12. **Luck bug:** in `rollHit`, apply luck to the premium tiers and then scale everything back so the odds add
    up to at most 1, or cap `luck × the summed odds` at 0.95. Right now Usopp + Featured *removes* SP / SEC AA /
    Alt Art Leaders from JP premium boxes and makes PRB-01 Manga Rares 3× rarer.
13. **Ship / Nami:** top income multiplier 7× → about **4×** (Coup de Burst +300%), Nami +25% → +15%. The ฿60M ship
    should take a dedicated player about a year, not 5 months.
14. **Sync:** when a merge would take a card, slab or sealed item below zero (both computers sold the same one),
    take back the berries from the extra sale. The same goes for poster rewards both devices paid, and income
    above the day's cap.
15. **Small leaks:** Merchant Week deals at market +5% instead of market (it's +10% instantly with Brook); a review
    has a 10% chance to go *down* a grade; cases are built with normal god odds and Treasure Hunt is applied when
    each pack is opened.

### What the economy looks like after fixes 1–8

Simulated: the grading loop with fixes A + B (section 9, fix 1) goes from +1.83V to −0.27V per ordered card. The
rest of this list follows from the formulas but **wasn't re-simulated**. Re-run the year-long player runs after
changing the numbers to confirm.

- The order/grade, Robin, gem-set and sealed loops all have **negative or zero expected value**.
- Pack ROI: about 75–90% (premium about 85%). Opening packs costs a little on average, and pulling a chase card is a real windfall.
- Money comes mostly from passive income, duplicates, posters and bounties, so the daily loop matters again.
- Expected pace (estimate): a regular player gets the whole crew in most of a year rather than 6 months, and
  the top ship takes more than a year. No player type reaches ฿100M+ within weeks.

---

## 10. Appendix

### A. Every set: pack EV and ROI

| Set | Family | Era | Pack ฿ | Box ฿ | Case ฿ | EV/pack A | EV/pack B | ROI A | ROI B | EV A Usopp+Feat | ROI Usopp+Feat+Sanji (A) | Break-even % of real box |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OP-01 | main | mapped | 1500 | 34200 | 348800 | 630 | 789 | 42% | 53% | 895 | 75% | 24% |
| OP-02 | main | mapped | 940 | 21500 | 219300 | 652 | 784 | 69% | 83% | 905 | 119% | 39% |
| OP-03 | main | mapped | 940 | 21500 | 219300 | 659 | 809 | 70% | 86% | 887 | 117% | 39% |
| OP-04 | main | mapped | 890 | 20300 | 207100 | 665 | 794 | 75% | 89% | 887 | 123% | 41% |
| OP-05 | main | mapped | 1250 | 28100 | 286600 | 687 | 859 | 55% | 69% | 929 | 93% | 30% |
| OP-06 | main | mapped | 780 | 17800 | 181600 | 697 | 794 | 89% | 102% | 907 | 144% | 47% |
| OP-07 | main | mapped | 670 | 15200 | 155000 | 672 | 783 | 100% | 117% | 844 | 156% | 55% |
| EB-01 | extra | random | 1200 | 27000 | 275400 | 588 | 648 | 49% | 54% | 738 | 78% | 31% |
| OP-08 | main | mapped | 640 | 14500 | 147900 | 634 | 801 | 99% | 125% | 879 | 169% | 57% |
| OP-09 | main | mapped | 990 | 22700 | 231500 | 673 | 818 | 68% | 83% | 900 | 111% | 37% |
| OP-10 | main | mapped | 630 | 14400 | 146900 | 667 | 791 | 106% | 126% | 897 | 176% | 58% |
| OP-11 | main | mapped | 950 | 21700 | 221300 | 639 | 784 | 67% | 83% | 877 | 114% | 38% |
| EB-02 | extra | random | 1150 | 26100 | 266200 | 585 | 643 | 51% | 56% | 744 | 78% | 32% |
| OP-12 | main | mapped | 680 | 15500 | 158100 | 673 | 774 | 99% | 114% | 891 | 162% | 53% |
| PRB-01 | premium | random | 1450 | 27600 | 281500 | 1801 | 2006 | 124% | 138% | 1827 | 152% | 30% |
| PRB-02 | premium | random | 930 | 17700 | 180500 | 1695 | 1903 | 182% | 205% | 1727 | 227% | 47% |
| OP-13 | main | mapped | 840 | 19100 | 194800 | 716 | 867 | 85% | 103% | 976 | 144% | 44% |
| OP14-EB04 | main | mapped | 660 | 15000 | 153000 | 689 | 801 | 104% | 121% | 892 | 168% | 56% |
| EB-03 | extra | random | 720 | 16400 | 167300 | 596 | 636 | 83% | 88% | 743 | 128% | 51% |
| OP15-EB04 | main | mapped | 640 | 14600 | 148900 | 689 | 798 | 108% | 125% | 922 | 177% | 57% |
| OP-16 | main | transition | 600 | 13700 | 139700 | 605 | 750 | 101% | 125% | 797 | 163% | 61% |
| OP-17 | main | random | 700 | 16000 | 163200 | 810 | 1012 | 116% | 145% | 1021 | 179% | 52% |
| OP-01-JP | main | random | 670 | 15400 | 157100 | 383 | 218 | 57% | 32% | 524 | 95% | 54% |
| OP-02-JP | main | random | 500 | 11500 | 117300 | 375 | 222 | 75% | 44% | 524 | 128% | 73% |
| OP-03-JP | main | random | 450 | 10200 | 104000 | 368 | 210 | 82% | 47% | 527 | 146% | 82% |
| OP-04-JP | main | random | 480 | 11000 | 112200 | 395 | 214 | 82% | 45% | 502 | 129% | 76% |
| OP-05-JP | main | random | 520 | 11900 | 121400 | 397 | 234 | 76% | 45% | 519 | 124% | 70% |
| OP-06-JP | main | random | 480 | 11000 | 112200 | 355 | 205 | 74% | 43% | 519 | 133% | 76% |
| EB-01-JP | extra | random | 410 | 9400 | 95900 | 273 | 150 | 67% | 37% | 358 | 108% | 89% |
| OP-07-JP | main | random | 360 | 8100 | 82600 | 384 | 212 | 107% | 59% | 517 | 178% | 103% |
| OP-08-JP | main | random | 320 | 7400 | 75500 | 376 | 218 | 117% | 68% | 505 | 194% | 112% |
| PRB-01-JP | premium | random | 1100 | 10500 | 89200 | 1920 | 966 | 175% | 88% | 1408 | 156% | 80% |
| OP-09-JP | main | random | 460 | 10500 | 107100 | 371 | 199 | 81% | 43% | 521 | 141% | 80% |
| OP-10-JP | main | random | 320 | 7400 | 75500 | 373 | 218 | 117% | 68% | 506 | 195% | 112% |
| EB-02-JP | extra | random | 500 | 11500 | 117300 | 267 | 150 | 53% | 30% | 348 | 85% | 73% |
| OP-11-JP | main | random | 500 | 11500 | 117300 | 378 | 221 | 76% | 44% | 549 | 134% | 73% |
| OP-12-JP | main | random | 380 | 8800 | 89800 | 385 | 206 | 101% | 54% | 510 | 165% | 96% |
| PRB-02-JP | premium | random | 850 | 8100 | 68800 | 1588 | 849 | 187% | 100% | 1139 | 165% | 103% |
| OP-13-JP | main | random | 420 | 9700 | 98900 | 405 | 224 | 96% | 53% | 522 | 154% | 87% |
| EB-03-JP | extra | random | 410 | 9400 | 95900 | 257 | 151 | 63% | 37% | 341 | 103% | 89% |
| OP-14-JP | main | random | 340 | 7800 | 79600 | 391 | 224 | 115% | 66% | 537 | 192% | 108% |
| EB-04-JP | extra | random | 320 | 7400 | 75500 | 262 | 149 | 82% | 47% | 342 | 131% | 112% |
| OP-15-JP | main | random | 340 | 7800 | 79600 | 371 | 215 | 109% | 63% | 514 | 183% | 108% |
| OP-16-JP | main | random | 320 | 7200 | 73400 | 388 | 229 | 121% | 72% | 494 | 190% | 115% |
| OP-17-JP | main | random | 360 | 8100 | 82600 | 360 | 214 | 100% | 59% | 503 | 174% | 103% |

*Model A uses the fallback values even for JP cards (the game only halves JP cards that have a market price), so
JP sets look better in A than they would with live prices.*

### B. Ship and crew payback (500 active minutes a day)

| Collection value | Fishing Boat | Going Merry | Flying Model | Thousand Sunny | Shark Submerge | Coup de Burst | Nami |
|---|---|---|---|---|---|---|---|
| ฿50k | 10 d | 40 d | 111 d | 278 d | 857 d | 2,667 d | 10 d |
| ฿1M | 3 d | 10 d | 30 d | 74 d | 238 d | 714 d | 3 d |
| ฿10M | 1 d | 3 d | 10 d | 25 d | 78 d | 235 d | 1 d |

Income per day at the 500-minute cap: ฿2k (new player, Rowboat) → ฿33.5k (฿1M collection) → ฿892k (฿10M, top
ship and Nami) → **฿2.78M/day** (฿100M, top ship and Nami). The early ships and Nami pay back in days. That's
fine. The problem is only that the loops above make the late ships trivial.

### C. God packs

| Odds | 24-pack sets | PRB |
|---|---|---|
| Normal | 1 in 5,760 | 1 in 4,800 |
| Luffy | 1 in 2,880 | 1 in 2,400 |
| Treasure Hunt | 1 in 1,920 | 1 in 1,600 |
| Luffy + Treasure Hunt | **1 in 960** | **1 in 800** |

Average god pack value (fallback values): OP-17 ฿142k, OP-13 Demon Pack ฿224k, EB-03 SP pack ฿79k, PRB-01 Manga
God Pack **฿600k**. God posters: ฿300k + ฿750k overall and ฿200k on *each* of the 45 set boards. With Luffy,
Treasure Hunt and Robin rerolls, those set posters can be farmed.

### D. Where each number comes from

| Finding | Source in the code |
|---|---|
| Binder orders at +50%, unlimited | `ORDER_MARKUP`, Binder.qml "Buy one", `Stage.buyCard` |
| Free cracking, 25% wear | `crackCondition`, `CRACK_WEAR` |
| Grade multipliers | `GRADE_MULT`, `DIAMOND_*` |
| Pack built before payment | `Stage.newPack` (Tiers.makePack) vs `payForPack` at the tear |
| Robin's reading | Stage.qml "Robin reads the sealed pack" |
| Sealed growth, no spread | `SEALED_RATE`, `sealedValue`, `sellSealed` |
| Sealed counts toward spent / earned / value | `spend`, `earn`, `setValue` (+ `sealedTotal`) |
| Saved-set bonus paid on sale | `Stage.savedWorth`, `sellCollectionSet`, `SET_BONUS` / `GEM_SET_BONUS` |
| √ box pricing vs linear selling | `marketBox` (`SEALED_CURVE`) vs `cardValue` (`USD_TO_BERRY`) |
| Luck overflow | `Tiers.rollHit` (srScale / premiumScale × luck, no renormalisation) |
| Unlimited focus | `finishFocus` (no daily counter) |
| Sync double-sell | `sync.js` `mergeCollection` (counts below zero just dropped), progress numbers add up |

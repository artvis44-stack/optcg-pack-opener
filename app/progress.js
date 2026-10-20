.pragma library
.import "tiers.js" as Tiers
// Progression: berries (฿), free packs, the daily streak, passive income,
// focus sessions, daily bounties and wanted-poster achievements; and the Port,
// where berries go: your ship and crew (perks), the card shop, grading,
// sealed products that gain value, and cosmetics.
//
// State lives in progress.json (separate per computer). The pack opener and
// the desktop companion both change it, always as read-modify-write through
// update(), so neither overwrites the other's changes.
//
// Every change that earns something goes through record(), which updates the
// stats, advances the daily bounties and unlocks achievements; it returns what
// was newly completed so the caller can celebrate it.

// ---- the economy -----------------------------------------------------------------

var BOX_DISCOUNT = 0.95;           // a box against its packs bought one by one
var CASE_DISCOUNT = 0.85;          // on the boxes left in the case
var USD_TO_BERRY = 100;            // selling: $1 market value = 100 ฿
var BOX_VALUE_MARKUP = 1.1;        // a box costs this much over what its cards are worth, chase cards left out
var JP_CARD_PRICE = 0.5;           // a Japanese single against the same English one (no public JP price list)
var INCOME_PER_MINUTE = 4;         // while you're at the computer, plus more the more your collection is worth
var INCOME_VALUE_SCALE = 2;        // + 2 × √(collection value / 1,000) ฿ a minute
var INCOME_CAP_MINUTES = 500;      // a day's income is capped at this many minutes' worth
var FREE_PACK_HOURS = 6;
var FREE_PACK_MAX = 2;
var STREAK_REWARD = [100, 200, 300, 400, 500, 600, 700];   // day 1..7, then 700; every 7th day +1 free pack
var FOCUS_MINUTES = 25;
var FOCUS_BERRIES = 200;           // plus a free pack
var FOCUS_IDLE_LIMIT = 10;         // minutes idle before a focus session is lost
var BULK_LIMIT = 1000;             // "sell duplicates" only sells copies worth less than this

// what a card sells for without a market price, by tier (฿)
var BASE_VALUE = {
    C: 5, UC: 10, DON: 20, R: 30, FOIL: 40, L: 60, SR: 250, TOPPER: 500, PANDA: 1500,
    AA: 1500, TEX: 1200, SEC: 2500, L_AA: 4000, DON_GOLD: 5000, DON_SP: 5000, SP: 6000,
    SEC_AA: 8000, TR: 20000, SUPER_L: 30000, SP_GOLD: 30000, SIGNED: 50000, MANGA: 60000,
    SUPER: 100000,
    PROMO: 500, V_C: 3000, V_FOIL: 10000, V_SR: 15000, V_SILVER: 20000, V_GOLD: 60000, V_PROMO: 200000
};

// A box costs what its cards are worth, not counting the chase cards
// (CHASE_TIERS: Treasure Rares, Manga, Super parallels...), plus
// BOX_VALUE_MARKUP: a box without a chase card is close to break-even (a little
// under), one with a chase card is where the money is. Worth: the set's cards
// at market price (Tiers.boxContents for how many of each a box holds).
// A pack is a 24th (or so) of the box, a little dearer one at a time.
// cfg: Tiers.setConfig(the set); p (optional): the player, for crew discounts;
// set (optional): the set id, for the week's featured set; values (optional):
// { tier: what a card of that tier is worth on average, ฿ } for the set's cards
// (Stage.tierValues), BASE_VALUE for what it doesn't give
function marketBox(cfg, values) {
    var present = null;
    if (values && Object.keys(values).length) {
        present = {};
        Object.keys(values).forEach(function (t) { present[t] = true; });
    }
    var contents = Tiers.boxContents(cfg, present), worth = 0;
    Object.keys(contents).forEach(function (t) {
        if (CHASE_TIERS.indexOf(t) >= 0) return;
        var v = values && values[t] > 0 ? values[t] : BASE_VALUE[t] || 5;
        worth += contents[t] * v;
    });
    return Math.max(100, worth * BOX_VALUE_MARKUP);
}

function packPrice(cfg, p, set, values) {
    var base = marketBox(cfg, values) / BOX_DISCOUNT / cfg.packsPerBox;
    var step = base < 1000 ? 10 : 50;
    return Math.max(step, Math.round(base * (p && hasCrew(p, "sanji") ? 0.9 : 1) * featuredDiscount(p, set) / step) * step);
}

function boxPrice(cfg, p, set, values) {
    return Math.max(100, Math.round(marketBox(cfg, values) * (p && hasCrew(p, "franky") ? 0.9 : 1) * featuredDiscount(p, set) / 100) * 100);
}

function casePrice(cfg, boxesLeft, p, set, values) {
    return Math.round(boxPrice(cfg, p, set, values) * boxesLeft * CASE_DISCOUNT / 100) * 100;
}

function featuredDiscount(p, set) {
    return p && set && eventIs(p, "featured") && p.weekly.set === set ? 0.9 : 1;
}

function format(n) {
    return "฿" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatBounty(n) {
    if (n >= 1e9) return "฿" + (n / 1e9).toFixed(n % 1e9 ? 2 : 0) + "B";
    if (n >= 1e6) return "฿" + (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + "M";
    return format(n);
}

// ---- the Port: ship and crew ---------------------------------------------------
// Upgrades cost about 5× the one before; each makes passive income bigger and
// free packs come faster or stack higher. card: the ship's Stage card, for a
// picture: a card id or name, or a list tried in order (art from your
// downloaded sets); the Going Merry is "Merry Go" on the cards. picture: a
// drawing in app/pictures instead, for a boat no card shows.

var SHIPS = [
    { name: "Rowboat",                        price: 0,        income: 0,    freeHours: 6, freeMax: 2, picture: "pictures/rowboat.svg",
      text: "Where every pirate starts." },
    { name: "Fishing Boat",                   price: 20000,    income: 0.2,  freeHours: 6, freeMax: 2, card: ["OP12-080", "Baratie"],
      text: "+20% passive income" },
    { name: "Going Merry",                    price: 100000,   income: 0.5,  freeHours: 6, freeMax: 3, card: ["EB02-041", "Merry Go", "Going Merry", "Mini-Merry"],
      text: "+50% passive income, hold 3 free packs" },
    { name: "Going Merry (Flying Model)",     price: 500000,   income: 1,    freeHours: 5, freeMax: 3, card: ["EB02-060", "Merry Go", "Going Merry", "Mini-Merry"],
      text: "+100% passive income, a free pack every 5 hours" },
    { name: "Thousand Sunny",                 price: 2500000,  income: 2,    freeHours: 5, freeMax: 4, card: "Thousand Sunny",
      text: "+200% passive income, hold 4 free packs" },
    { name: "Thousand Sunny (Shark Submerge)", price: 12000000, income: 3.5, freeHours: 4, freeMax: 4, card: "Thousand Sunny",
      text: "+350% passive income, a free pack every 4 hours" },
    { name: "Thousand Sunny (Coup de Burst)", price: 60000000, income: 6,    freeHours: 3, freeMax: 5, card: "Thousand Sunny",
      text: "+600% passive income, a free pack every 3 hours, hold 5" }
];

// each recruited once, for good. card: their name on the cards, for a
// portrait (art from your downloaded sets)
var CREW = [
    { id: "zoro",    name: "Roronoa Zoro",  card: "Roronoa Zoro",     price: 15000,   perk: "Focus sessions pay double berries" },
    { id: "nami",    name: "Nami",          card: "Nami",             price: 25000,   perk: "+25% passive income" },
    { id: "usopp",   name: "Usopp",         card: "Usopp",            price: 40000,   perk: "Single packs: hits 15% likelier" },
    { id: "sanji",   name: "Sanji",         card: "Sanji",            price: 60000,   perk: "Packs cost 10% less" },
    { id: "chopper", name: "Tony Tony Chopper", card: "Tony Tony.Chopper", price: 80000, perk: "Missing a single day doesn't break your streak" },
    { id: "robin",   name: "Nico Robin",    card: "Nico Robin",       price: 120000,  perk: "Knows the old games: her notes price every vintage card, and at the show she tells you what one is worth" },
    { id: "franky",  name: "Franky",        card: "Franky",           price: 200000,  perk: "Boxes and cases cost 10% less" },
    { id: "brook",   name: "Brook",         card: "Brook",            price: 300000,  perk: "Cards sell for 10% more" },
    { id: "jinbe",   name: "Jinbe",         card: "Jinbe",            price: 500000,  perk: "A fourth daily bounty" },
    { id: "luffy",   name: "Monkey D. Luffy (Gear 5)", card: "Monkey.D.Luffy", price: 5000000, perk: "God packs twice as likely" }
];

// ---- the Port: grading ------------------------------------------------------------
// Send a card off; it comes back in a slab with a grade from 1 to 10 that
// multiplies what it's worth. The grade is rolled when you send it.

// bestOf: graded that many times, the best grade kept (Elite)
var GRADING = [
    { id: "value",    name: "Value",    hours: 24,  base: 300,   pct: 0.05 },
    { id: "standard", name: "Standard", hours: 6,   base: 1000,  pct: 0.1 },
    { id: "express",  name: "Express",  hours: 0.5, base: 5000,  pct: 0.2 },
    { id: "elite",    name: "Elite",    hours: 72,  base: 20000, pct: 0.35, bestOf: 2 }
];
var GRADE_ODDS = [[10, 0.08], [9, 0.34], [8, 0.3], [7, 0.15], [6, 0.07], [5, 0.03], [4, 0.015], [3, 0.008], [2, 0.004], [1, 0.003]];
var GRADE_MULT = { 10: 4, 9: 1.6, 8: 1.1, 7: 0.9, 6: 0.75, 5: 0.6, 4: 0.5, 3: 0.45, 2: 0.4, 1: 0.35 };
// The secret: any grading can come back a DIAMOND LABEL 10, worth 10x the raw card.
// Rolled when it's sent, like the grade; no odds table shows it.
var DIAMOND_CHANCE = 0.005;
var DIAMOND_MULT = 10;
// A raw copy's condition sets its grading odds. Copies start unchecked (graded
// like GRADE_ODDS, which is what the conditions average out to); a pre-grade
// reveals one copy's condition, prep moves one up a level. In the collection a
// card entry keeps counts per condition, entry.cond = { clean: 1, ... }; the
// copies not in there are unchecked. share: how many copies are in that
// condition; review: the chance a review lifts its slab a grade.
var CONDITIONS = [
    { id: "pristine", name: "Pristine", share: 0.10, review: 0.35, color: "#ffd700",
      odds: [[10, 0.30], [9, 0.50], [8, 0.15], [7, 0.05]] },
    { id: "clean",    name: "Clean",    share: 0.30, review: 0.15, color: "#7fd1b9",
      odds: [[10, 0.11], [9, 0.52], [8, 0.27], [7, 0.08], [6, 0.02]] },
    { id: "decent",   name: "Decent",   share: 0.35, review: 0.06, color: "#7fa8ff",
      odds: [[10, 0.04], [9, 0.31], [8, 0.38], [7, 0.18], [6, 0.07], [5, 0.02]] },
    { id: "worn",     name: "Worn",     share: 0.18, review: 0.02, color: "#c8a070",
      odds: [[10, 0.01], [9, 0.10], [8, 0.30], [7, 0.30], [6, 0.16], [5, 0.08], [4, 0.04], [3, 0.01]] },
    { id: "damaged",  name: "Damaged",  share: 0.07, review: 0,    color: "#ff8a7a",
      odds: [[9, 0.02], [8, 0.10], [7, 0.18], [6, 0.25], [5, 0.20], [4, 0.12], [3, 0.07], [2, 0.04], [1, 0.02]] }
];
var CONDITION = {};
CONDITIONS.forEach(function (c, i) { c.rank = i; CONDITION[c.id] = c; });
var PREP_SLIP = 0.05;            // prep goes wrong: a level down instead of up
var CRACK_WEAR = 0.25;           // cracking a slab: the card can come out a level worse
var REVIEW_LEGACY = 0.12;        // slabs of unchecked copies, and ones graded before conditions

function preGradeFee(value) { return Math.round(Math.max(100, 0.02 * value) / 10) * 10; }
function prepFee(value) { return Math.round(Math.max(500, 0.12 * value) / 10) * 10; }
function reviewFee(slabWorth) { return Math.round(Math.max(2000, 0.2 * slabWorth) / 10) * 10; }

// a card entry's copies by condition, with "unchecked" for the rest. Copies
// that left (sold, graded, a sync on another computer) come out of the
// unchecked ones first, then the worst.
function conditions(entry) {
    var out = { unchecked: 0 }, n = entry ? entry.count || 0 : 0, cond = (entry && entry.cond) || {};
    CONDITIONS.forEach(function (c) { out[c.id] = Math.max(0, Math.floor(cond[c.id] || 0)); });
    var checked = CONDITIONS.reduce(function (a, c) { return a + out[c.id]; }, 0);
    for (var i = CONDITIONS.length - 1; i >= 0 && checked > n; i--) {
        var drop = Math.min(out[CONDITIONS[i].id], checked - n);
        out[CONDITIONS[i].id] -= drop;
        checked -= drop;
    }
    out.unchecked = n - checked;
    return out;
}

// write conditions() back onto the entry (only what's not unchecked)
function setConditions(entry, counts) {
    var cond = {};
    CONDITIONS.forEach(function (c) { if (counts[c.id] > 0) cond[c.id] = counts[c.id]; });
    if (Object.keys(cond).length) entry.cond = cond;
    else delete entry.cond;
}

// take one copy of a condition ("unchecked" or an id) off the entry; false if there's none
function takeCopy(entry, condId) {
    var counts = conditions(entry);
    if (!(counts[condId] > 0)) return false;
    counts[condId]--;
    entry.count--;
    setConditions(entry, counts);
    return true;
}

// put a copy of a condition (null: unchecked) on the entry
function addCopy(entry, condId) {
    var counts = conditions(entry);
    entry.count = (entry.count || 0) + 1;
    if (condId && CONDITION[condId]) counts[condId]++;
    setConditions(entry, counts);
}

function rollCondition() {
    var r = Math.random(), acc = 0;
    for (var i = 0; i < CONDITIONS.length; i++) {
        acc += CONDITIONS[i].share;
        if (r < acc) return CONDITIONS[i].id;
    }
    return "decent";
}

// pre-grade: an unchecked copy gets its condition; returns it ("" if none to check)
function preGrade(entry) {
    var counts = conditions(entry);
    if (counts.unchecked <= 0) return "";
    var c = rollCondition();
    counts[c]++;
    setConditions(entry, counts);
    return c;
}

// prep a copy of condition condId: { to, slipped } (null if it can't be)
function prep(entry, condId) {
    var counts = conditions(entry), c = CONDITION[condId];
    if (!c || c.rank === 0 || !(counts[condId] > 0)) return null;
    var slipped = Math.random() < PREP_SLIP;
    var to = slipped ? CONDITIONS[Math.min(CONDITIONS.length - 1, c.rank + 1)].id : CONDITIONS[c.rank - 1].id;
    counts[condId]--;
    counts[to]++;
    setConditions(entry, counts);
    return { to: to, slipped: slipped && to !== condId };
}

// the grade odds of a copy (condition id, or unchecked)
function gradeOdds(condId) {
    return CONDITION[condId] ? CONDITION[condId].odds : GRADE_ODDS;
}

// best of `tries` gradings
function bestOfOdds(odds, tries) {
    if (!(tries > 1)) return odds;
    var below = 0, out = [];
    odds.slice().sort(function (a, b) { return a[0] - b[0]; }).forEach(function (g) {
        var upTo = below + g[1];
        out.push([g[0], Math.pow(upTo, tries) - Math.pow(below, tries)]);
        below = upTo;
    });
    return out.sort(function (a, b) { return b[0] - a[0]; });
}

// the chance of each grade for a copy sent to a service: [[grade, p], ...] best first
function serviceOdds(condId, serviceId) {
    var g = GRADING.filter(function (x) { return x.id === serviceId; })[0] || GRADING[0];
    return bestOfOdds(gradeOdds(condId), g.bestOf || 1);
}

// crack a slab: the condition the raw copy comes back in (null: unchecked).
// Slabs from before conditions: a 10 / 9 / 8 comes back Pristine / Clean / Decent;
// 7 or lower comes back unchecked, a fresh chance, and never with wear.
function crackCondition(slab) {
    if (slab.cond === "unchecked") return null;   // sent without a pre-grade: still unknown
    var c = CONDITION[slab.cond];
    if (!slab.cond) {
        if (slab.grade <= 7) return null;
        c = CONDITION[slab.grade >= 10 ? "pristine" : slab.grade === 9 ? "clean" : "decent"];
    }
    if (!c) return null;
    if (Math.random() < CRACK_WEAR) c = CONDITIONS[Math.min(CONDITIONS.length - 1, c.rank + 1)];
    return c.id;
}

// the chance a review lifts a slab a grade (0 if it can't be reviewed)
function reviewChance(slab) {
    if (!slab || slab.reviewed || slab.grade >= 10) return 0;
    return CONDITION[slab.cond] ? CONDITION[slab.cond].review : REVIEW_LEGACY;
}

var GRADE_NAME = { 10: "GEM MINT", 9: "MINT", 8: "NM-MT", 7: "NEAR MINT", 6: "EX-MT", 5: "EXCELLENT",
                   4: "VG-EX", 3: "VERY GOOD", 2: "GOOD", 1: "POOR" };

// a slab's grade name: GRADE_NAME, or DIAMOND for a Diamond Label
function gradeName(slab) {
    return slab && slab.diamond ? "DIAMOND" : GRADE_NAME[slab && slab.grade] || "";
}

// ---- the Port: the card shop and sealed products ---------------------------------

var DEAL_MARKUP = 1.1;      // today's deals: a little over market value
var DEALS_PER_DAY = 8;
var SEALED_RATE = [0.004, 0.016];   // value growth a week: the newest set .. the oldest

// ---- the Port: cosmetics ---------------------------------------------------------------
// colours: base behind everything, glow in the middle (#AARRGGBB)

// Playmats: real One Piece Card Game playmats (official Limited Editions and
// tournament prize mats), their pictures downloaded by fetch_cards.py
// --playmat from TCGplayer's product photo (tcg: product id) or the official
// product page (page). Shown full screen behind the opener, darkened.
var BACKDROPS = [
    { id: "default",   name: "Night Sea",      price: 0,       base: "#05070d", glow: "#18324a80" },
    { id: "pm-vol1",   name: "Official Playmat · Limited Edition Vol.1", price: 80000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 542494, page: "https://en.onepiece-cardgame.com/products/other/playmat003.php" } },
    { id: "pm-vol2",   name: "Official Playmat · Limited Edition Vol.2 (the Four Emperors)", price: 120000, base: "#05070d", glow: "#00000000",
      playmat: { file: "pictures/playmats/pm-vol2.jpg" } },
    { id: "pm-vol3",   name: "Official Playmat · Limited Edition Vol.3", price: 200000, base: "#05070d", glow: "#00000000",
      playmat: { file: "pictures/playmats/pm-vol3.jpg" } },
    { id: "pm-vol4",   name: "Official Playmat · Limited Edition Vol.4 (Roronoa Zoro)", price: 300000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 657220 } },
    { id: "pm-vol5",   name: "Official Playmat · Limited Edition Vol.5", price: 450000, base: "#05070d", glow: "#00000000",
      playmat: { file: "pictures/playmats/pm-vol5.jpg" } },
    { id: "pm-flame",  name: "Flame-Flame Fruit Coliseum Edition", price: 1500000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 717036 } },
    { id: "pm-reg24-2", name: "2024 Regional · 2nd Place", price: 8000000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 539211 } },
    { id: "pm-reg25-2", name: "2025 Regional · 2nd Place", price: 12000000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 630010 } },
    { id: "pm-reg25-1", name: "2025 Regional · Champion", price: 40000000, base: "#05070d", glow: "#00000000",
      playmat: { tcg: 630011 } },
    { id: "grandline", name: "Grand Line",     price: 25000,   base: "#03101c", glow: "#302a7fc0" },
    { id: "wano",      name: "Wano",           price: 60000,   base: "#13050a", glow: "#2cc03030" },
    { id: "egghead",   name: "Egghead",        price: 150000,  base: "#0a0616", glow: "#30b050ff" },
    { id: "treasure",  name: "Treasure Vault", price: 500000,  base: "#120d02", glow: "#2cffc63a" },
    { id: "laughtale", name: "Laugh Tale",     price: 2500000, base: "#0e0404", glow: "#34ff7a3a" }
];
// the label on the desktop showcase's slab
var SLABS = [
    { id: "classic", name: "Classic",     price: 0,       top: "#fbf8f1", bottom: "#e9e3d6", text: "#14171f", sub: "#4c5260" },
    { id: "black",   name: "Black Label", price: 50000,   top: "#24262e", bottom: "#0e0f13", text: "#f2f2f2", sub: "#c9a85a" },
    { id: "gold",    name: "Gold Label",  price: 250000,  top: "#ffeab0", bottom: "#d4a640", text: "#2a1a00", sub: "#6b4a10" },
    { id: "holo",    name: "Holo Label",  price: 1000000, top: "#c8f0ff", bottom: "#f4c8ff", text: "#141a2e", sub: "#4a4f7a" }
];
// a Diamond Label slab wears this whatever label you chose; it can't be bought
var DIAMOND_LABEL = { id: "diamond", name: "Diamond Label", top: "#f4fdff", bottom: "#bfe9ff", text: "#0b2a44", sub: "#2f6f9a" };

// ---- the card show: once a week ---------------------------------------------------
// Every Saturday (and SHOW_EXTRA_DAYS) a card show is in town: a hall of vendor stalls
// (CardShow.qml: a floor plan you walk around, then each stall's table), one visit a
// show. Once you're in, the app shows no prices (no binder, vault, port or wanted board
// until you leave): you have to know the market. Nico Robin (crew) knows the vintage
// market: her notes, and her word on what a vintage listing is worth if it's genuine. Vendors are honest, bargain tables,
// premium dealers, vintage specialists or scammers; which is which you only know for
// sure after you leave.
//
// Spotting fakes: a listing can be checked a few ways (SHOW_CHECKS): a raw card under
// the loupe and the light, its back, its stock, its corners and edges; a slab's label,
// its cert (looked up), its case, the card inside; a sealed product's crimp or shrink
// wrap, its print, its weight. Each check uses one of the visit's SHOW_CHECK_BUDGET. A
// fake is crude, decent or good (SHOW_FAKE_GRADES): it gives itself away in that many of
// its checks and looks fine in the rest (and a good one looks almost right on the table,
// Card.qml's fakeLook). Real listings have innocent quirks now and then (SHOW_QUIRK) that
// can look suspicious. Corners and edges show a raw card's real condition: scammers'
// "pack fresh" cards never are. You can ask the vendor about a listing once: honest
// dealers mostly give a straight answer, scammers mostly don't (and sometimes lie
// convincingly), and a scammer gets pushy if you inspect too much at their stall.
// Haggling: one offer per card. What's in the hall is dealt when you walk in and saved
// (p.show.stock), so it doesn't change.
//
// Promos and vintage cards (the 2005-06 CCG) are only sold here: two sets of their
// own (SHOW_SETS) that no pack holds. About SHOW_SPECIAL_SHARE of the other tables'
// cards are those, and some shows (SHOW_GRAIL_CHANCE) have a grail, one worth
// SHOW_GRAIL_USD or more, at a premium dealer's (or a vintage specialist's) table or a
// scammer's. Scammers fake those more often than modern cards, as with real
// counterfeits. Vintage specialists, and some scammers (SHOW_VINTAGE_SCAMMER), sell
// nothing else: a few vintage singles and slabs, and often a sealed 2005-06 pack or box
// (SHOW_SEALED). Bought, a sealed product waits in the Port's sealed products (gaining
// value like the others) and opens a pack at a time. A scammer's is resealed: searched,
// its rare and foil swapped out (Tiers.makeVintagePack).

var SHOW_WEEKDAY = 6;                       // Saturday
var SHOW_EXTRA_DAYS = ["2026-10-20"];       // the first show, on a Tuesday
var SHOW_CHECK_BUDGET = 20;                 // checks a visit (one look at one thing about one listing)
var SHOW_STEAL = 0.75;                      // under this share of market: a steal (the Sharp Eye poster)
var SHOW_HAGGLE = [0.05, 0.1, 0.2];         // the offers you can make: this much off
// kind -> how many tables, listings [min, max], asking price [min, max] × market,
// share of slabs, share of fakes, haggle: the chance each offer is taken; vintage: sells
// only vintage cards and sealed product
var SHOW_VENDORS = {
    honest:  { tables: 5, listings: [20, 30], price: [0.95, 1.15], slabs: 0.4,  fakes: 0,   haggle: [0.8, 0.5, 0.15] },
    bargain: { tables: 2, listings: [15, 25], price: [0.55, 0.85], slabs: 0.15, fakes: 0,   haggle: [0.85, 0.55, 0.25] },
    premium: { tables: 3, listings: [12, 18], price: [1.15, 1.5],  slabs: 0.75, fakes: 0,   haggle: [0.6, 0.3, 0.08] },
    vintage: { tables: 2, listings: [10, 15], price: [1.0, 1.3],   slabs: 0.35, fakes: 0,   haggle: [0.7, 0.4, 0.1], vintage: "ccg" },
    carddass:{ tables: 1, listings: [10, 15], price: [0.95, 1.25], slabs: 0.25, fakes: 0,   haggle: [0.75, 0.45, 0.12], vintage: "hb" },
    scammer: { tables: 3, listings: [18, 26], price: [0.6, 0.9],   slabs: 0.5,  fakes: 0.5, haggle: [0.95, 0.9, 0.75] }
};
var SHOW_VINTAGE_SCAMMER = 0.35;            // a scammer's table is a vintage one this often (either game)
var SHOW_VINTAGE_LISTINGS = [10, 15];       // ...with this many listings
var SHOW_VINTAGE_MIN = 500;                 // a vintage table's singles start cheaper (฿): binders of commons too
// [name, what the table says]; scammers' blurbs have their own tells
var SHOW_NAMES = {
    honest:  [["Grand Line Cards", "Fair prices, everything checked."], ["Baratie Collectibles", "Family shop since the first set."],
              ["Water 7 Trading", "Graded and raw, all guaranteed."], ["Sabaody Singles", "Prices match the market, give or take."],
              ["Alabasta TCG", "We grade what we sell."], ["Fish-Man Island Games", "Ask about anything in the case."],
              ["Loguetown Hobbies", "Collectors serving collectors."], ["Skypiea Slabs & Singles", "Every card checked twice."],
              ["Zou Trading Post", "Fair and square, every time."]],
    bargain: [["Estate sale table", "Selling a late collector's binder. Not sure what it's worth."],
              ["Kid clearing out a binder", "Need money for a bike!"], ["Garage sale box", "Old cards, make me an offer."],
              ["Moving-house sale", "Everything must go before Friday."]],
    premium: [["Mariejois Vault", "Only the best slabs. Prices to match."], ["Celestial Grails", "Investment-grade cards."],
              ["Laugh Tale Luxe", "Gem mints, nothing less."], ["Elbaf Grails", "Only the rarest. Serious buyers."]],
    vintage: [["Gol D. Roger's Relics", "The 2005-06 English game. Singles, slabs, sealed."], ["Shonen Jump Vault", "Original 2005 product, stored right."],
              ["Old Era Cards", "Vintage One Piece only. Ask me anything."], ["Ohara Archives", "Twenty years collecting the first English game."]],
    scammer: [["Dressrosa Deals", "Cash only, no returns. All gem mint, trust me."], ["Jaya Card Kingz", "Best prices at the show!! Pack fresh guaranteed!!"],
              ["Thriller Bark Treasures", "Too good to last. No refunds."], ["Big Mom's Bargains", "Everything mint. Buy two, I'll throw in a sleeve."],
              ["Buggy's Blowout", "Prices slashed!! Genuine 100%!! Cash only!!"]],
    carddass: [["Carddass Corner", "Japanese vintage: Hyper Battle, 1999-2002."], ["Akihabara Retro", "Straight from Japan. Carddass, every stage."],
               ["Showa-Heisei Cards", "Old Japanese cards, sorted by stage."]],
    vintageScammer: [["Retro Treasure Chest", "RARE vintage!! 1st print!! Sealed!!"], ["Grand Line Antiques", "Vintage at modern prices. No returns."],
                     ["Golden Age Grails", "Every card a grail. Cash only, today only."]]
};
// how likely a chase card of each tier is to be on a table
var SHOW_RARITY = { SR: 3, AA: 10, TEX: 5, SEC: 10, SEC_AA: 10, L_AA: 12, SP: 18, DON_GOLD: 2, TR: 12, MANGA: 10,
                    SUPER: 4, SUPER_L: 3, SP_GOLD: 3, SIGNED: 1 };
// the show-only sets: their cards come from app/vintage.json (VINTAGE) and optcgapi's promo list (PROMO)
var SHOW_SETS = {
    VINTAGE: { name: "One Piece CCG (2005-06)", show: true },
    PROMO:   { name: "Promotion Cards", show: true },
    HYPERBATTLE: { name: "Carddass Hyper Battle (1999-2002)", show: true }
};
var SHOW_SPECIAL_SHARE = 0.12;              // of the other tables' listings: promos and vintage cards
var SHOW_SPECIAL_RARITY = { PROMO: 8, V_C: 4, V_FOIL: 3, V_SR: 3, V_SILVER: 2, V_GOLD: 1, V_PROMO: 1,
                            V_HB: 4, V_HB_HOLO: 3, V_HB_GOLD: 1.5, V_HB_SECRET: 0.5, V_HB_PROMO: 1 };
var SHOW_SPECIAL_MIN = 2000;                // promos and vintage cards worth less than this (฿) stay home
var SHOW_GRAIL_USD = 1000;                  // a card worth this much or more is a grail
var SHOW_GRAIL_CHANCE = 0.25;               // a show with a grail: about one a month
var SHOW_SPECIAL_FAKES = 0.8;               // a scammer's promo, vintage card or sealed product is fake this often
// sealed vintage packs / boxes: the chance a vintage table has one, and that some other table does
var SHOW_SEALED = { vintage: { pack: 0.35, box: 0.08 }, other: { pack: 0.06, box: 0.01 } };
// Hyper Battle's sealed products (app/hyperbattle.json "sealed"): the chance a Carddass table has
// one of each kind (a vending pack, a Grand Box, a Jump Festa pack), and that another table has a vending pack
var SHOW_SEALED_HB = { carddass: { vpack: 0.7, grandbox: 0.15, jfpack: 0.05 }, other: { vpack: 0.04 } };
var SHOW_SEALED_TABLES = [["premium", 0.55], ["honest", 0.25], ["scammer", 0.2]];   // which other table

// ---- checking a listing ----
// a fake: [grade, share, how many of its checks give it away, how off it looks on the table (0..1)]
var SHOW_FAKE_GRADES = [["crude", 0.3, 3, 1], ["decent", 0.45, 2, 0.5], ["good", 0.25, 1, 0.15]];
var SHOW_QUIRK = 0.3;                       // a real listing has an innocent quirk in one check this often
// what you can check, by what the listing is: { id, label, real, tell, quirk } (lines; "%g": the grade);
// noTell: never where a fake gives itself away (a resealed pack's wrapper is the real one)
var SHOW_CHECKS = {
    raw: [
        { id: "loupe", label: "Loupe",
          real: ["Under the loupe the print is a clean rosette of tiny dots, and the small text is razor sharp.",
                 "The copyright line is crisp enough to read every letter.",
                 "Fine lines in the art stay fine under magnification: no smearing at all."],
          tell: ["Under the loupe there's no dot pattern at all: flat, smeary inkjet colour.",
                 "The small text is fuzzy, like a photocopy of a photocopy.",
                 "The copyright line has blurred into a grey smudge."],
          quirk: ["One colour layer is a hair out of register: a faint fringe along the outlines. Print runs did that.",
                  "There's a tiny stray dot of ink in the art: a speck on the press."] },
        { id: "light", label: "Under the light",
          real: ["Tilted under the hall lights it catches the light just as it should.",
                 "The surface has that even, satin sheen.",
                 "Where there's foil it shifts as you tilt it, the colours rolling across."],
          tell: ["It's far too glossy: it shines like a sticker.",
                 "The shine is printed on: it doesn't move at all when you tilt it.",
                 "The surface is dull and papery, with no sheen."],
          quirk: ["A faint scuff runs across the surface where it's rubbed against something.",
                  "The surface has a slight haze, like it's been handled a lot."] },
        { id: "back", label: "The back",
          real: ["The back's colours match the real ones, shade for shade.",
                 "The back's print is sharp and its pattern the right size."],
          tell: ["The back is a shade too dark, and the logo's a little blurry.",
                 "Next to a card of yours, the back's colour is clearly off.",
                 "The back's pattern is slightly too big, as if it was scanned and printed."],
          quirk: ["The back's off-centre: the border's thicker at the bottom. Plenty of real ones were cut like that.",
                  "A thin print line runs across the back. A factory flaw."] },
        { id: "stock", label: "Feel the stock",
          real: ["Right weight, and it flexes back with that snap when you bend it gently.",
                 "Against a card from your binder the thickness feels identical."],
          tell: ["The stock is thin and floppy: it bends like paper.",
                 "It's stiff and slick, more like plastic than card.",
                 "Held up to the light it glows right through: there's no core layer."],
          quirk: ["It has a slight curve, the way cards warp in humid storage.",
                  "It's a touch stiffer than you expected. Some print runs were."] },
        { id: "edges", label: "Corners & edges",
          real: [""], tell: ["The edges are cut rough, not the clean die-cut of a factory card."], quirk: [""] }
    ],
    slab: [
        { id: "label", label: "The label",
          real: ["The label's font and spacing look right, and the hologram's there.",
                 "Grade, name and cert number are printed clean and spelt right."],
          tell: ["The grade reads \"GEM MNIT\". Close, not quite.",
                 "The label font is wrong, and there's no hologram.",
                 "The grade on the label sits a little crooked, like it was printed at home."],
          quirk: ["The label's faded a little, like it sat in a sunny window.",
                  "A tiny bubble under the label sticker. Happens at the factory."] },
        { id: "cert", label: "Look up the cert",
          real: ["You look the cert up on your phone: registered as this card, graded %g.",
                 "The cert checks out: this card, grade %g."],
          tell: ["You look the cert up: no record of that number.",
                 "The cert's registered to a different card entirely. The label's been copied."],
          quirk: ["The hall's signal is awful and the lookup takes ages, but it checks out: this card, grade %g."] },
        { id: "case", label: "The case",
          real: ["Clean case, crisp seams, nothing's been pried.",
                 "The case is clear and the seams are factory-sealed."],
          tell: ["Glue marks along the seam: it's been opened and closed again.",
                 "The case is lighter and cloudier than a real one.",
                 "The seams are uneven, and one corner's been forced."],
          quirk: ["A few light scratches on the case from being handled.",
                  "A scuff on the back of the case. Cosmetic."] },
        { id: "inside", label: "The card inside",
          real: ["Through the case, the print looks crisp and the colours right.",
                 "What you can see of the card through the plastic looks right."],
          tell: ["Even through the plastic the print looks soft and washed out.",
                 "The card sits loose in the case, and it's thinner than it should be."],
          quirk: ["The card's sitting slightly crooked in the case. They shift sometimes."] }
    ],
    pack: [
        { id: "crimp", label: "The crimp",
          real: ["The crimp at both ends is factory-tight and even.",
                 "Clean factory crimps, top and bottom."],
          tell: ["The top crimp is uneven and shiny with glue: it's been opened and resealed.",
                 "There's a crease where the top was pried open and pressed shut."],
          quirk: ["One corner of the crimp is a little crushed, from storage."] },
        { id: "wrap", label: "The wrapper", noTell: true,
          real: ["The wrapper's print is sharp, its colours right for 2005-06.",
                 "The wrapper art and logos are exactly right."],
          quirk: ["The wrapper's faded a little on one side, like it sat in a shop window."] },
        { id: "weight", label: "Weigh it",
          real: ["On your pocket scale it weighs what a fresh pack should.",
                 "The weight's spot on for ten cards and the wrapper."],
          tell: ["It's light on your pocket scale: about one card short of a fresh pack.",
                 "Lighter than a pack of ten should be. The foil's gone, maybe."],
          quirk: ["It's a fraction heavier than you'd expect. Wrappers vary a little."] }
    ],
    box: [
        { id: "shrink", label: "The shrink wrap",
          real: ["Factory shrink wrap, tight, with the right seams.",
                 "The shrink wrap's tight and the seams are the factory's."],
          tell: ["The shrink wrap's loose, with a hand-made seam along the bottom.",
                 "Under the shrink there's a slit in the box's tape: it's been opened."],
          quirk: ["The shrink wrap's torn at one corner. The box under it is still sealed."] },
        { id: "print", label: "The box", noTell: true,
          real: ["The box's print and logos are exactly right for 2005-06.",
                 "Proper Bandai box, the right art, the right size."],
          quirk: ["The box is dented at one corner from shipping."] },
        { id: "weight", label: "Weigh it",
          real: ["It weighs what twelve packs should.",
                 "The weight's right for a full box."],
          tell: ["It's light: about a pack's worth short.",
                 "It weighs less than a full box should. Something's been taken out."],
          quirk: ["It's a little heavier than you'd expect. The cardboard's thick."] }
    ]
};
// corners and edges: a raw card's real condition (sold as is: unchecked)
var SHOW_EDGES = {
    pristine: "Sharp corners, clean edges, no whitening: pack fresh.",
    clean: "Sharp corners; a speck of whitening on one edge.",
    decent: "Light whitening along the edges, the corners a little soft.",
    worn: "Rounded corners and edge wear you can't miss.",
    damaged: "A crease runs across it, and the corners are chewed.",
    "": "Some wear, about what you'd expect from a binder."
};
// asking the vendor about a listing: the chance of a straight answer, by kind; else vague, or for a scammer a line
var SHOW_STRAIGHT = { honest: 0.85, premium: 0.9, bargain: 0.45, vintage: 0.9, carddass: 0.9, scammer: 0.3 };
var SHOW_TALK = {
    honest:  ["\"Came out of a collection I bought last month. I checked every card myself.\"",
              "\"Pulled it myself, actually. Been in a top loader ever since.\"",
              "\"A regular traded it in. I know him, he's careful with his cards.\""],
    premium: ["\"Graded straight from our own submissions. Here's the receipt if you want it.\"",
              "\"From a private collection. We authenticate everything before it goes in the case.\""],
    bargain: ["\"It was in my dad's binder. No idea where he got it.\"",
              "\"Honestly? Found it in a box in the attic.\""],
    vintage: ["\"Opened that box myself back in 2006. Kept everything in a binder away from the light.\"",
              "\"Bought it from the original owner. He played the game when it came out.\"",
              "\"I've collected this game for twenty years. I can tell you the print run.\""],
    carddass: ["\"Brought these back from Japan myself. Vending machine pulls, kept in a binder since 2000.\"",
               "\"A collector in Osaka sold me his stages. He kept every holo in a sleeve.\"",
               "\"Bought the lot from an old toy shop that still had the Carddass machine.\""],
    vague:   ["\"Not sure, I bought a big lot. Looks fine to me.\"",
              "\"Couldn't tell you. It was in with a bunch of others.\""],
    scam:    ["\"Trust me, it's legit. Look at it, it's beautiful.\"",
              "\"Straight from Japan, totally real. I don't do fakes.\"",
              "\"You're the third person looking at it today. Decide quick.\"",
              "\"No questions, no problems. Cash only.\""],
    pushy:   ["\"You going to buy something, or just stare at it all day?\"",
              "\"Look, I've got other customers. Buy it or move on.\"",
              "\"Stop handling the merchandise if you're not buying.\""],
    patient: ["\"Take your time, look at anything you like.\"",
              "\"Want a closer look at anything? Go ahead.\""]
};
var SHOW_PUSHY = 3;                         // checks at a scammer's stall before they start pushing

function isShowSet(set) {
    return !!SHOW_SETS[set];
}

function isGrail(x) {
    return x.value >= SHOW_GRAIL_USD * USD_TO_BERRY && Tiers.SHOW_ONLY_TIERS.indexOf(x.card.tier) >= 0;
}

// what a raw card is said to be, by its real condition
var SHOW_CLAIM = { pristine: "Pack fresh", clean: "Near mint", decent: "Lightly played", worn: "Played", damaged: "Damaged" };

// the show's day ("2026-10-24"), or "" when there's none today
function showDay(now) {
    var d = new Date(now), day = dayOf(now);
    return d.getDay() === SHOW_WEEKDAY || SHOW_EXTRA_DAYS.indexOf(day) >= 0 ? day : "";
}

// the next show you can go to: today's if you haven't been, else the next one ("2026-10-24")
function nextShowDay(p, now) {
    for (var i = 0; i < 8; i++) {
        var day = showDay(now + i * 86400 * 1000);
        if (day && !(i === 0 && showVisited(p, day))) return day;
    }
    return "";
}

function showState(p) {
    return p.show || { day: "", entered: 0, left: 0, stock: null, bought: {}, haggled: {}, looks: 0, checked: {}, asked: {} };
}

// you've been to (and left) today's show
function showVisited(p, day) {
    var s = showState(p);
    return s.day === day && !!s.left;
}

// you're at the show now (walked in today, haven't left)
function atShow(p, now) {
    var s = showState(p), day = showDay(now);
    return !!day && s.day === day && !!s.entered && !s.left;
}

// can you walk in: there's a show today and you haven't been
function canEnterShow(p, now) {
    var day = showDay(now);
    return !!day && !showVisited(p, day);
}

function shuffled(list, rnd) {
    list = list.slice();
    for (var i = list.length - 1; i > 0; i--) {
        var j = Math.floor(rnd() * (i + 1)), t = list[i];
        list[i] = list[j];
        list[j] = t;
    }
    return list;
}

function between(rnd, lo, hi) { return lo + (hi - lo) * rnd(); }

function roundPrice(v) {
    var step = v >= 100000 ? 1000 : v >= 10000 ? 100 : v >= 1000 ? 50 : 10;
    return Math.max(step, Math.round(v / step) * step);
}

// The hall: [{ id, kind, vintage, name, blurb, listings: [listing] }], the same for the same
// day and pool. pool: [{ key, card, value }] (every card of your downloaded sets and the
// show-only sets, value: its market price raw). A listing: { id, key, card, grade (0: raw),
// claim, cond, fake, fakeGrade, fakeLook, tells (the checks that give a fake away), value (what it's really worth, never shown while
// you're there), ask, checks: { check id: what you see }, talk (the vendor's answer) }; a
// sealed product's also has sealed: { kind: "pack" | "box", origin, packs } (its card stands
// in for it; a Hyper Battle one's also has line "hb", name and its product's cards). sealed:
// { ccg: { "<set name>": { pack: ฿, box: ฿ } } (app/vintage.json's "sealed", in ฿), hb: [product:
// { name, kind: "vpack" | "grandbox" | "jfpack", set, worth: ฿, cards }] (app/hyperbattle.json's) },
// or nothing (a bare ccg map works too).
function makeShowStock(day, pool, sealed) {
    var rnd = hash("show " + day);
    var pickOf = function (list) { return list[Math.floor(rnd() * list.length)]; };
    // modern chase cards; promos and vintage cards; vintage only (grails apart: one a show at most)
    var modern = {}, special = {}, vintage = { ccg: {}, hb: {} }, grails = [];
    pool.forEach(function (x) {
        var t = x.card.tier;
        if (!(x.value > 0)) return;
        if (SHOW_RARITY[t]) (modern[t] = modern[t] || []).push(x);
        else if (!SHOW_SPECIAL_RARITY[t] || x.value < SHOW_VINTAGE_MIN) return;
        else if (isGrail(x)) grails.push(x);
        else {
            if (x.value >= SHOW_SPECIAL_MIN) (special[t] = special[t] || []).push(x);
            if (Tiers.isVintage(x.card)) {
                var line = vintage[x.card.set === "HYPERBATTLE" ? "hb" : "ccg"];
                (line[t] = line[t] || []).push(x);
            }
        }
    });
    var used = {};
    var picker = function (byTier, weights) {
        var tiers = Object.keys(byTier);
        var weight = tiers.reduce(function (n, t) { return n + weights[t]; }, 0);
        return !tiers.length ? null : function () {
            var r = rnd() * weight, tier = tiers[tiers.length - 1];
            for (var i = 0; i < tiers.length; i++) {
                r -= weights[tiers[i]];
                if (r < 0) { tier = tiers[i]; break; }
            }
            var options = byTier[tier].filter(function (x) { return !used[x.key]; });
            return (options.length ? options : byTier[tier])[Math.floor(rnd() * (options.length || byTier[tier].length))];
        };
    };
    var pickModern = picker(modern, SHOW_RARITY), pickSpecial = picker(special, SHOW_SPECIAL_RARITY);
    var pickVintage = { ccg: picker(vintage.ccg, SHOW_SPECIAL_RARITY), hb: picker(vintage.hb, SHOW_SPECIAL_RARITY) };
    var lines = Object.keys(pickVintage).filter(function (l) { return pickVintage[l]; });
    if (!pickModern && !pickSpecial) return [];
    var kinds = [];
    Object.keys(SHOW_VENDORS).forEach(function (k) { for (var i = 0; i < SHOW_VENDORS[k].tables; i++) kinds.push(k); });
    var names = {};
    Object.keys(SHOW_NAMES).forEach(function (k) { names[k] = shuffled(SHOW_NAMES[k], rnd); });

    // what each check shows: a fake fails `tells` of them (a good fake just one), a real one
    // may have an innocent quirk in one
    var inspect = function (what, fake, grade, cond) {
        var checks = SHOW_CHECKS[what], out = {}, tells = {}, quirk = "", fg = null;
        if (fake) {
            var r = rnd(), acc = 0;
            fg = SHOW_FAKE_GRADES[SHOW_FAKE_GRADES.length - 1];
            for (var i = 0; i < SHOW_FAKE_GRADES.length; i++) {
                acc += SHOW_FAKE_GRADES[i][1];
                if (r < acc) { fg = SHOW_FAKE_GRADES[i]; break; }
            }
            var can = shuffled(checks.filter(function (c) { return !c.noTell; }), rnd);
            can.slice(0, fg[2]).forEach(function (c) { tells[c.id] = true; });
        } else if (rnd() < SHOW_QUIRK) {
            var quirky = checks.filter(function (c) { return c.quirk && c.quirk[0]; });
            quirk = pickOf(quirky).id;
        }
        checks.forEach(function (c) {
            var line = pickOf(tells[c.id] ? c.tell : quirk === c.id ? c.quirk : c.real);
            if (c.id === "edges") line = (SHOW_EDGES[cond] + (tells.edges ? " " + line : "")).trim();
            out[c.id] = line.replace("%g", grade);
        });
        return { checks: out, tells: Object.keys(tells), grade: fg ? fg[0] : "", look: fg ? fg[3] : 0 };
    };

    var talk = function (kind, fake) {
        var straight = rnd() < SHOW_STRAIGHT[kind];
        if (kind === "scammer") return pickOf(straight ? SHOW_TALK.honest : SHOW_TALK.scam);   // sometimes a convincing lie
        return pickOf(straight ? SHOW_TALK[kind] : SHOW_TALK.vague);
    };

    var listing = function (kind, x, id) {
        var cfg = SHOW_VENDORS[kind], showOnly = !SHOW_RARITY[x.card.tier];
        var fake = rnd() < (showOnly && cfg.fakes ? SHOW_SPECIAL_FAKES : cfg.fakes);
        var slab = rnd() < cfg.slabs;
        var grade = 0, cond = "", claim = "";
        if (slab) {
            var g = rnd();
            grade = kind === "premium" ? (g < 0.5 ? 10 : g < 0.9 ? 9 : 8)
                  : kind === "scammer" ? (g < 0.6 ? 10 : 9)
                  : (g < 0.25 ? 10 : g < 0.7 ? 9 : g < 0.92 ? 8 : 7);
        } else if (kind === "scammer") {   // always "pack fresh", never true
            cond = rnd() < 0.6 ? "worn" : "damaged";
            claim = SHOW_CLAIM.pristine;
        } else if (kind === "bargain" && rnd() < 0.5) {
            cond = "";                                       // not checked: sold as is
            claim = "As is (not checked)";
        } else {
            var r = rnd(), acc = 0;
            cond = "decent";
            for (var c = 0; c < CONDITIONS.length; c++) {
                acc += CONDITIONS[c].share;
                if (r < acc) { cond = CONDITIONS[c].id; break; }
            }
            claim = SHOW_CLAIM[cond];
        }
        var worth = grade ? x.value * GRADE_MULT[grade] : x.value;
        var ask = roundPrice(worth * between(rnd, cfg.price[0], cfg.price[1]));
        var seen = inspect(grade ? "slab" : "raw", fake, grade, cond);
        return { id: id, key: x.key, card: x.card, grade: grade, claim: claim, cond: cond, fake: fake,
                 fakeGrade: seen.grade, fakeLook: seen.look, tells: seen.tells, value: fake ? 0 : Math.round(worth), ask: ask,
                 checks: seen.checks, talk: talk(kind, fake) };
    };

    var ccgSealed = sealed && (sealed.ccg || (sealed.hb ? null : sealed)) || {}, hbSealed = sealed && sealed.hb || [];
    // a sealed vintage pack or box on a table
    var sealedListing = function (table, kind, origin) {
        var worth = ccgSealed[origin][kind];
        if (!(worth > 0)) return null;
        var cfg = SHOW_VENDORS[table.kind], fake = !!cfg.fakes && rnd() < SHOW_SPECIAL_FAKES;
        var seen = inspect(kind, fake, 0, "");
        return {
            id: table.id + "-" + kind, key: "sealed:" + origin + ":" + kind,
            card: { id: kind === "box" ? "BOX" : "PACK", name: origin + (kind === "box" ? " Booster Box" : " Booster Pack"),
                    tier: kind === "box" ? "SEALED_BOX" : "SEALED_PACK", set: "VINTAGE", origin: origin, image: "" },
            sealed: { kind: kind, origin: origin, packs: kind === "box" ? Tiers.VINTAGE_PACK.packsPerBox : 1 },
            grade: 0, claim: "Factory sealed", cond: "", fake: fake, fakeGrade: seen.grade, fakeLook: seen.look, tells: seen.tells,
            value: fake ? 0 : worth, ask: roundPrice(worth * between(rnd, cfg.price[0], cfg.price[1])),
            checks: seen.checks, talk: talk(table.kind, fake)
        };
    };

    // a sealed Hyper Battle product (a vending pack, a Grand Box, a Jump Festa pack)
    var hbListing = function (table, product) {
        var cfg = SHOW_VENDORS[table.kind], fake = !!cfg.fakes && rnd() < SHOW_SPECIAL_FAKES;
        var box = product.kind === "grandbox";
        var seen = inspect(box ? "box" : "pack", fake, 0, "");
        return {
            id: table.id + "-" + product.kind + "-" + Math.floor(rnd() * 1e6), key: "sealed:hb:" + product.name,
            card: { id: box ? "BOX" : "PACK", name: product.name, tier: box ? "SEALED_BOX" : "SEALED_PACK", set: "HYPERBATTLE",
                    origin: product.set, line: "hb", image: "" },
            sealed: { kind: product.kind, line: "hb", origin: product.set, name: product.name, packs: 1, cards: product.cards || null },
            grade: 0, claim: box ? "Sealed, never opened" : "Unopened", cond: "", fake: fake, fakeGrade: seen.grade, fakeLook: seen.look,
            tells: seen.tells, value: fake ? 0 : product.worth, ask: roundPrice(product.worth * between(rnd, cfg.price[0], cfg.price[1])),
            checks: seen.checks, talk: talk(table.kind, fake)
        };
    };
    var hbProduct = function (kind) {
        var of = hbSealed.filter(function (x) { return x.kind === kind && x.worth > 0; });
        return of.length ? pickOf(of) : null;
    };

    var hall = shuffled(kinds, rnd).map(function (kind, v) {
        var cfg = SHOW_VENDORS[kind];
        // sells only vintage: a specialist (of one game), or a scammer passing as one
        var old = cfg.vintage && pickVintage[cfg.vintage] ? cfg.vintage
                : kind === "scammer" && lines.length && rnd() < SHOW_VINTAGE_SCAMMER ? pickOf(lines) : "";
        var pool = old && kind === "scammer" ? "vintageScammer" : kind;
        var nm = names[pool].shift() || ["Table " + (v + 1), ""];
        var range = old ? SHOW_VINTAGE_LISTINGS : cfg.listings;
        var n = cfg.vintage && !old ? 0 : range[0] + Math.floor(rnd() * (range[1] - range[0] + 1));
        var listings = [];
        for (var i = 0; i < n; i++) {
            var x = old ? pickVintage[old]()
                  : pickSpecial && (!pickModern || rnd() < SHOW_SPECIAL_SHARE) ? pickSpecial() : pickModern();
            used[x.key] = true;
            listings.push(listing(kind, x, v + "-" + i));
        }
        return { id: String(v), kind: kind, vintage: old, name: nm[0], blurb: nm[1], listings: listings };
    });

    // now and then a grail: on a premium dealer's table (or a vintage specialist's, for a vintage
    // one), or a scammer's (likely a fake)
    if (grails.length && rnd() < SHOW_GRAIL_CHANCE) {
        var g = grails[Math.floor(rnd() * grails.length)];
        var gline = !Tiers.isVintage(g.card) ? "" : g.card.set === "HYPERBATTLE" ? "hb" : "ccg";
        var honestKind = gline && rnd() < 0.5 ? (gline === "hb" ? "carddass" : "vintage") : "premium";
        var kind = rnd() < 0.65 ? honestKind : "scammer";
        var where = hall.filter(function (t) { return t.kind === kind && (!t.vintage || t.vintage === gline); });
        var table = where[Math.floor(rnd() * where.length)];
        if (table) table.listings.unshift(listing(table.kind, g, table.id + "-g"));
    }

    // sealed vintage packs and boxes: often at the vintage tables, very rarely anywhere else
    var origins = Object.keys(ccgSealed);
    if (origins.length) {
        hall.filter(function (t) { return t.vintage === "ccg"; }).forEach(function (t) {
            ["box", "pack"].forEach(function (kind) {
                if (rnd() >= SHOW_SEALED.vintage[kind]) return;
                var it = sealedListing(t, kind, pickOf(origins));
                if (it) t.listings.unshift(it);
            });
        });
        ["box", "pack"].forEach(function (kind) {
            if (rnd() >= SHOW_SEALED.other[kind]) return;
            var r = rnd(), who = SHOW_SEALED_TABLES[0][0];
            for (var i = 0, acc = 0; i < SHOW_SEALED_TABLES.length; i++) {
                acc += SHOW_SEALED_TABLES[i][1];
                if (r < acc) { who = SHOW_SEALED_TABLES[i][0]; break; }
            }
            var tables = hall.filter(function (t) { return t.kind === who && !t.vintage; });
            var t = tables[Math.floor(rnd() * tables.length)];
            var it = t && sealedListing(t, kind, pickOf(origins));
            if (it) t.listings.unshift(it);
        });
    }
    // Hyper Battle: vending packs, Grand Boxes, Jump Festa packs at the Carddass tables; now and
    // then a vending pack somewhere else
    if (hbSealed.length) {
        hall.filter(function (t) { return t.vintage === "hb"; }).forEach(function (t) {
            ["jfpack", "grandbox", "vpack"].forEach(function (kind) {
                var product = rnd() < SHOW_SEALED_HB.carddass[kind] ? hbProduct(kind) : null;
                if (product) t.listings.unshift(hbListing(t, product));
            });
        });
        if (rnd() < SHOW_SEALED_HB.other.vpack) {
            var others = hall.filter(function (t) { return !t.vintage && t.kind !== "bargain"; });
            var t2 = others[Math.floor(rnd() * others.length)], product = hbProduct("vpack");
            if (t2 && product) t2.listings.unshift(hbListing(t2, product));
        }
    }
    return hall;
}

// walk in: the hall is dealt (once a day) and you're there until you leave
function enterShow(p, now, pool, sealed) {
    var day = showDay(now);
    if (!canEnterShow(p, now)) return false;
    var s = showState(p);
    if (s.day !== day || !s.stock) p.show = { day: day, entered: now, left: 0, stock: makeShowStock(day, pool, sealed), bought: {}, haggled: {},
                                          looks: 0, checked: {}, asked: {} };
    else if (!s.entered) p.show.entered = now;
    return true;
}

function showListing(p, id) {
    var s = showState(p);
    for (var v = 0; v < (s.stock || []).length; v++)
        for (var i = 0; i < s.stock[v].listings.length; i++)
            if (s.stock[v].listings[i].id === id) return s.stock[v].listings[i];
    return null;
}

function showVendor(p, listingId) {
    var s = showState(p);
    return (s.stock || []).filter(function (v) { return v.id === listingId.split("-")[0]; })[0] || null;
}

// what a listing costs you now (after a haggle that worked)
function showPrice(p, listing) {
    var h = showState(p).haggled[listing.id];
    return h && h.ok ? roundPrice(listing.ask * (1 - h.pct)) : listing.ask;
}

// make an offer (pct: one of SHOW_HAGGLE); one per listing. Returns true (taken) / false
// (refused, the price stays) / null (can't: already haggled, bought, or not at the show).
// The answer is the same however often you'd ask it, so there's no asking again.
function haggle(p, id, pct, now) {
    var s = showState(p), x = showListing(p, id), v = showVendor(p, id);
    var k = SHOW_HAGGLE.indexOf(pct);
    if (!atShow(p, now) || !x || !v || k < 0 || s.haggled[id] || s.bought[id]) return null;
    var ok = hash("haggle " + s.day + " " + id + " " + pct)() < SHOW_VENDORS[v.kind].haggle[k];
    p.show.haggled[id] = { pct: pct, ok: ok };
    return ok;
}

// What can be checked about a listing: [{ id, label }] (SHOW_CHECKS)
function showChecks(listing) {
    var what = listing.sealed ? listing.sealed.kind : listing.grade ? "slab" : "raw";
    return SHOW_CHECKS[what].map(function (c) { return { id: c.id, label: c.label }; });
}

// what you've seen of a listing so far: { check id: text }
function showSeen(p, id) {
    var x = showListing(p, id), done = (showState(p).checked || {})[id] || {}, out = {};
    if (x) Object.keys(done).forEach(function (c) { out[c] = (x.checks || {})[c] || ""; });
    return out;
}

// check one thing about a listing (one of the visit's SHOW_CHECK_BUDGET; looking again is free):
// what you see, or "" when you're out of checks (or not at the show)
function checkListing(p, id, check, now) {
    var s = showState(p), x = showListing(p, id);
    if (!atShow(p, now) || !x || !x.checks || x.checks[check] === undefined) return "";
    p.show.checked = p.show.checked || {};
    var done = p.show.checked[id] = p.show.checked[id] || {};
    if (done[check]) return x.checks[check];
    if ((s.looks || 0) >= SHOW_CHECK_BUDGET) return "";
    p.show.looks = (s.looks || 0) + 1;
    done[check] = true;
    return x.checks[check];
}

// ask the vendor about a listing (free, once: the answer doesn't change)
function askVendor(p, id, now) {
    var x = showListing(p, id);
    if (!atShow(p, now) || !x) return "";
    p.show.asked = p.show.asked || {};
    p.show.asked[id] = true;
    return x.talk || "";
}

// what the vendor says while you're at their stall: a scammer gets pushy once you've
// checked SHOW_PUSHY things on their table; everyone else is happy to let you look
function vendorMood(p, vendorId) {
    var s = showState(p), v = (s.stock || []).filter(function (t) { return t.id === vendorId; })[0];
    if (!v) return "";
    var n = 0;
    Object.keys(s.checked || {}).forEach(function (id) {
        if (id.split("-")[0] === vendorId) n += Object.keys(s.checked[id]).length;
    });
    if (n < SHOW_PUSHY) return "";
    var lines = v.kind === "scammer" ? SHOW_TALK.pushy : SHOW_TALK.patient;
    return lines[Math.floor(hash("mood " + s.day + " " + vendorId)() * lines.length)];
}

// buy a listing: the berries go, the card comes (the caller puts it in the collection).
// Returns the listing, or null (not here, sold, or you can't afford it).
function buyAtShow(p, id, now) {
    var s = showState(p), x = showListing(p, id);
    if (!atShow(p, now) || !x || s.bought[id]) return null;
    var price = showPrice(p, x);
    if (!spend(p, price, "show")) return null;
    p.show.bought[id] = { price: price, at: now };
    if (x.sealed) {   // to the Port's sealed products (a resealed one's found out when you leave)
        var sid = now.toString(36) + Math.floor(Math.random() * 1e6).toString(36);
        p.sealed[sid] = { set: x.sealed.line === "hb" ? "HYPERBATTLE" : "VINTAGE", setName: x.sealed.origin, kind: x.sealed.kind,
                          boxes: 0, vintage: true, line: x.sealed.line || "ccg", name: x.sealed.name || "", cards: x.sealed.cards || null,
                          packs: x.sealed.packs, packsTotal: x.sealed.packs, resealed: !!x.fake,
                          paid: price, at: now, rate: SEALED_RATE[1] };
    }
    return x;
}

// leave: the visit is over. Returns the recap: { items: [{ listing, vendor, paid }], paid,
// worth, fakes, steals, vendors: [{ name, kind }] } and records the visit (its posters)
function leaveShow(p, now) {
    var s = showState(p);
    if (!s.day || s.left) return null;
    p.show.left = now;
    var items = Object.keys(s.bought).map(function (id) {
        return { listing: showListing(p, id), vendor: showVendor(p, id), paid: s.bought[id].price };
    }).filter(function (it) { return it.listing; });
    var recap = {
        items: items,
        paid: items.reduce(function (n, it) { return n + it.paid; }, 0),
        worth: items.reduce(function (n, it) { return n + it.listing.value; }, 0),
        fakes: items.filter(function (it) { return it.listing.fake; }).length,
        steals: items.filter(function (it) { return !it.listing.fake && it.paid < SHOW_STEAL * it.listing.value; }).length,
        vendors: (s.stock || []).map(function (v) { return { name: v.name, kind: v.kind }; })
    };
    // the genuine promos and vintage cards you brought home (their posters)
    var real = items.filter(function (it) { return !it.listing.fake && !it.listing.sealed; }).map(function (it) { return it.listing; });
    var tally = function (fn) { return real.filter(fn).length; };
    recap.done = record(p, { type: "show", fakes: recap.fakes, steals: recap.steals,
                             vintage: tally(function (x) { return Tiers.isVintage(x.card); }),
                             promos: tally(function (x) { return ["PROMO", "V_PROMO", "V_HB_PROMO"].indexOf(x.card.tier) >= 0; }),
                             rookie: tally(function (x) { return x.card.set === "HYPERBATTLE" && x.card.id === "C01"; }),
                             goldRares: tally(function (x) { return x.card.tier === "V_GOLD"; }),
                             grails: tally(function (x) { return isGrail({ card: x.card, value: x.grade ? x.value / GRADE_MULT[x.grade] : x.value }); }) });
    return recap;
}

// a fake slab's label: close to the real thing, not quite
var FAKE_GRADE_NAME = { 10: "GEM MNIT", 9: "MNIT", 8: "NM-TM", 7: "NAER MINT" };
function fakeGradeName(slab) {
    return FAKE_GRADE_NAME[slab && slab.grade] || (GRADE_NAME[slab && slab.grade] || "") + ".";
}

// ---- the week: a rotating event and weekly bounties ------------------------------
// Weeks start on Monday. The events take turns, one a week.

var EVENTS = [
    { id: "featured", name: "Featured Set",   text: "{set}: hits 25% likelier, its packs, boxes and cases 10% cheaper" },
    { id: "manga",    name: "Manga Madness",  text: "Manga Rares, Super Alt Arts and Treasure Rares twice as likely" },
    { id: "merchant", name: "Merchant Week",  text: "Card shop deals at market price, and 12 of them a day" },
    { id: "grading",  name: "Grading Rush",   text: "Every grading service at the Value price, back in half the time" },
    { id: "treasure", name: "Treasure Hunt",  text: "God packs three times as likely" },
    { id: "golden",   name: "Golden Week",    text: "Selling cards pays 15% more" },
    { id: "training", name: "Crew Training",  text: "Focus sessions give two free packs" },
    { id: "bonanza",  name: "Bounty Bonanza", text: "Daily and weekly bounty rewards doubled" }
];

// ---- seasons: a month each, named after a story arc --------------------------------
// About a dozen goals worth points; points climb a reward track whose top
// rewards (the arc's backdrop, a title) can only be earned that month.

var ARCS = [
    { name: "Alabasta",        base: "#140d04", glow: "#38e0a050" },
    { name: "Skypiea",         base: "#06101c", glow: "#38ffe9a0" },
    { name: "Water 7",         base: "#04101a", glow: "#3840a0e0" },
    { name: "Thriller Bark",   base: "#0a0612", glow: "#38a060ff" },
    { name: "Sabaody",         base: "#0a0a14", glow: "#38ff90d0" },
    { name: "Marineford",      base: "#0e0606", glow: "#38ff5030" },
    { name: "Fish-Man Island", base: "#021216", glow: "#3830e0d0" },
    { name: "Punk Hazard",     base: "#120808", glow: "#3880d0ff" },
    { name: "Dressrosa",       base: "#140610", glow: "#38ff60a0" },
    { name: "Whole Cake",      base: "#140a10", glow: "#38ffb0d0" },
    { name: "Wano",            base: "#13050a", glow: "#38c03030" },
    { name: "Egghead",         base: "#0a0616", glow: "#38b050ff" }
];

// counter: what's counted this season (see record); goal [min, max]; pts: its points
var SEASON_GOALS = [
    { id: "packs",   text: "Open {n} packs",                         goal: [120, 200], pts: 30 },
    { id: "boxes",   text: "Open {n} booster boxes",                 goal: [3, 6],     pts: 30 },
    { id: "srplus",  text: "Pull {n} Super Rares or better",         goal: [25, 40],   pts: 30 },
    { id: "aaplus",  text: "Pull {n} Alt Arts or better",            goal: [8, 14],    pts: 40 },
    { id: "chase",   text: "Pull a chase card (TR, Manga, Super Alt Art...)", goal: [1, 1], pts: 60 },
    { id: "daily",   text: "Complete {n} daily bounties",            goal: [25, 45],   pts: 40 },
    { id: "weekly",  text: "Complete {n} weekly bounties",           goal: [4, 8],     pts: 40 },
    { id: "focus",   text: "Finish {n} focus sessions",              goal: [10, 20],   pts: 30 },
    { id: "streak",  text: "Reach a {n}-day streak",                 goal: [10, 20],   pts: 30 },
    { id: "active",  text: "Be active at your computer {n} hours",   goal: [20, 40],   pts: 30 },
    { id: "graded",  text: "Get {n} cards graded",                   goal: [4, 8],     pts: 30 },
    { id: "gem9",    text: "Get a 9 or a 10 from grading",           goal: [1, 1],     pts: 40 },
    { id: "sold",    text: "Sell {n} cards",                         goal: [40, 80],   pts: 20 },
    { id: "bought",  text: "Buy {n} cards at the card shop",         goal: [3, 6],     pts: 20 },
    { id: "posters", text: "Earn {n} wanted posters",                goal: [5, 10],    pts: 30 },
    { id: "sets",    text: "Open packs from {n} different sets",     goal: [3, 5],     pts: 20 }
];
var SEASON_GOAL_COUNT = 12;
// the reward track: reach the points, get the reward (the last two only this month)
var SEASON_TIERS = [
    { pts: 60,  packs: 2,     text: "2 free packs" },
    { pts: 120, berries: 15000, text: "฿15,000" },
    { pts: 200, packs: 4,     text: "4 free packs" },
    { pts: 280, backdrop: true, text: "the {arc} backdrop (this season only)" },
    { pts: 360, berries: 50000, title: true, text: "฿50,000 and the title \"Hero of {arc}\" (this season only)" }
];

// ---- achievements: wanted posters ---------------------------------------------
// One overall board, plus a board per set (its posters' ids are "<set>:<key>").
// Posters with a count/goal show how far along you are while locked.

function pulled(p, tiers) {
    return tiers.reduce(function (a, t) { return a + (p.stats.pulled[t] || 0); }, 0);
}

var CHASE_TIERS = ["TR", "SP_GOLD", "MANGA", "SIGNED", "SUPER", "SUPER_L"];

// tier groups a set's "own every ..." posters track (Stage works out how much of each you own)
var SET_GROUPS = {
    leaders: ["L"],
    sr: ["SR"],
    sec: ["SEC", "SEC_AA"],
    aa: ["AA", "L_AA", "TEX"]
};

function setsWhere(p, fn) {
    var b = p.stats.bySet || {};
    return Object.keys(b).filter(function (k) { return fn(setStats(p, k)); }).length;
}

function setPosterCount(p) {
    return Object.keys(p.achievements).filter(function (id) { return id.indexOf(":") > 0; }).length;
}

function a(id, title, text, bounty, reward, test, count, goal, fmt) {
    var x = { id: id, title: title, text: text, bounty: bounty, reward: reward, test: test };
    if (count) { x.count = count; x.goal = goal; x.fmt = fmt || ""; x.test = function (p) { return count(p) >= goal; }; }
    return x;
}

var ACHIEVEMENTS = [
    a("pack1",    "Set Sail",              "Open your first pack",                 1e6,   500,   null, function (p) { return p.stats.packs; }, 1),
    a("leader",   "Captain",               "Pull a Leader",                        3e6,   300,   function (p) { return pulled(p, ["L"]) >= 1; }),
    a("sr",       "Super Rookie",          "Pull a Super Rare",                    5e6,   500,   function (p) { return pulled(p, ["SR"]) >= 1; }),
    a("pack10",   "Rookie",                "Open 10 packs",                        8e6,   800,   null, function (p) { return p.stats.packs; }, 10),
    a("box1",     "Box Breaker",           "Open a whole booster box",             1e7,   1500,  null, function (p) { return p.stats.boxes; }, 1),
    a("aa",       "Alternate Reality",     "Pull an Alternate Art",                2e7,   2000,  function (p) { return pulled(p, ["AA", "TEX"]) >= 1; }),
    a("sec",      "Secret Keeper",         "Pull a Secret Rare",                   3e7,   3000,  function (p) { return pulled(p, ["SEC", "SEC_AA"]) >= 1; }),
    a("laa",      "Leader of Legends",     "Pull an Alternate Art Leader",         5e7,   5000,  function (p) { return pulled(p, ["L_AA", "SUPER_L"]) >= 1; }),
    a("panda",    "Where's Pandaman?",     "Find a Pandaman variant",              6.6e7, 3000,  function (p) { return pulled(p, ["PANDA"]) >= 1; }),
    a("sp",       "Special Delivery",      "Pull an SP card",                      8e7,   8000,  function (p) { return pulled(p, ["SP", "SP_GOLD"]) >= 1; }),
    a("golddon",  "Golden DON!!",          "Pull a Gold or Special Foil DON!!",    1e8,   8000,  function (p) { return pulled(p, ["DON_GOLD", "DON_SP"]) >= 1; }),
    a("pack100",  "Supernova",             "Open 100 packs",                       1.2e8, 5000,  null, function (p) { return p.stats.packs; }, 100),
    a("case1",    "Case Closed",           "Open every box in a case",             1.5e8, 20000, null, function (p) { return p.stats.cases; }, 1),
    a("tr",       "Treasure Hunter",       "Pull a Treasure Rare",                 3e8,   20000, function (p) { return pulled(p, ["TR"]) >= 1; }),
    a("manga",    "Manga Panel",           "Pull a Manga Rare",                    5e8,   50000, function (p) { return pulled(p, ["MANGA", "SIGNED"]) >= 1; }),
    a("super",    "Super Parallel",        "Pull a Super Alternate Art",           1e9,   80000, function (p) { return pulled(p, ["SUPER", "SUPER_L"]) >= 1; }),
    a("pack1000", "Emperor",               "Open 1,000 packs",                     1.5e9, 50000, null, function (p) { return p.stats.packs; }, 1000),
    a("sets5",    "World Traveler",        "Open packs from 5 different sets",     2e7,   2000,  null, function (p) { return Object.keys(p.stats.sets).length; }, 5),
    a("half",     "Halfway to Laugh Tale", "Own half of a set",                    4e7,   4000,  function (p) { return p.stats.bestCompletion >= 0.5; }),
    a("most",     "Laugh Tale",            "Own 90% of a set",                     4e8,   30000, function (p) { return p.stats.bestCompletion >= 0.9; }),
    a("sell1",    "Merchant",              "Sell a card",                          2e6,   200,   null, function (p) { return p.stats.sold; }, 1),
    a("rich",     "Big Spender",           "Hold 100,000 ฿ at once",               6e7,   0,     null, function (p) { return p.berries; }, 100000, "money"),
    a("streak7",  "Loyal Crew",            "Keep a 7-day streak",                  3e7,   3000,  null, function (p) { return p.streak.count; }, 7),
    a("streak30", "Nakama for Life",       "Keep a 30-day streak",                 3e8,   20000, null, function (p) { return p.streak.count; }, 30),
    a("focus1",   "Focused",               "Finish a focus session",               4e6,   300,   null, function (p) { return p.stats.focus; }, 1),
    a("focus25",  "Haki Master",           "Finish 25 focus sessions",             2.5e8, 15000, null, function (p) { return p.stats.focus; }, 25),

    // the hard ones
    a("worth1m",  "Treasure Hoard",        "Own a collection worth ฿1,000,000",    3e8,   20000, null, function (p) { return p.stats.value; }, 1e6, "money"),
    a("worth10m", "City of Gold",          "Own a collection worth ฿10,000,000",   2e9,   150000, null, function (p) { return p.stats.value; }, 1e7, "money"),
    a("worth100m","The One Piece",         "Own a collection worth ฿100,000,000",  5e9,   500000, null, function (p) { return p.stats.value; }, 1e8, "money"),
    a("rich1m",   "Millionaire",           "Hold 1,000,000 ฿ at once",             1e9,   0,     null, function (p) { return p.berries; }, 1e6, "money"),
    a("earn10m",  "Tycoon",                "Earn ฿10,000,000 in total",            2e9,   100000, null, function (p) { return p.stats.earned; }, 1e7, "money"),
    a("sets15",   "Grand Fleet",           "Open packs from 15 different sets",    6e8,   30000, null, function (p) { return Object.keys(p.stats.sets).length; }, 15),
    a("case10",   "Shipping Magnate",      "Open 10 whole cases",                  2e9,   100000, null, function (p) { return p.stats.cases; }, 10),
    a("pack10k",  "Unstoppable",           "Open 10,000 packs",                    4e9,   250000, null, function (p) { return p.stats.packs; }, 10000),
    a("manga10",  "Manga Library",         "Pull 10 Manga Rares",                  3e9,   200000, null, function (p) { return pulled(p, ["MANGA", "SIGNED"]); }, 10),
    a("super5",   "Supernova Collector",   "Pull a Super Alternate Art in 5 different sets", 4e9, 300000, null,
      function (p) { return setsWhere(p, function (s) { return (s.pulled.SUPER || 0) + (s.pulled.SUPER_L || 0) > 0; }); }, 5),
    a("master1",  "Completionist",         "Own every card in a set",              2.5e9, 150000, null, function (p) { return setsWhere(p, function (s) { return s.completion >= 1; }); }, 1),
    a("master10", "Pirate King",           "Own every card in 10 sets",            5.5648e9, 1000000, null, function (p) { return setsWhere(p, function (s) { return s.completion >= 1; }); }, 10),
    a("posters100","Most Wanted",          "Earn 100 set wanted posters",          3e9,   200000, null, setPosterCount, 100),
    a("streak100","Unbreakable Will",      "Keep a 100-day streak",                1.5e9, 100000, null, function (p) { return p.streak.count; }, 100),
    a("streak365","A Year at Sea",         "Keep a 365-day streak",                4.6e9, 400000, null, function (p) { return p.streak.count; }, 365),
    a("focus100", "Conqueror's Haki",      "Finish 100 focus sessions",            1.2e9, 80000, null, function (p) { return p.stats.focus; }, 100),
    a("focus500", "Supreme King",          "Finish 500 focus sessions",            3.5e9, 250000, null, function (p) { return p.stats.focus; }, 500),
    a("god1",     "Touched by the Gods",   "Open a god pack",                      3e9,   300000, null, function (p) { return p.stats.godPacks; }, 1),
    a("god3",     "Imu's Favorite",        "Open 3 god packs",                     5e9,   750000, null, function (p) { return p.stats.godPacks; }, 3),

    // the Port: ship, crew, shop, grading, sealed, cosmetics, spending
    a("ship2",    "Going Merry",           "Upgrade your ship to the Going Merry", 5e7,   5000,  null, function (p) { return p.ship.level; }, 2),
    a("ship4",    "Thousand Sunny",        "Upgrade your ship to the Thousand Sunny", 4e8, 30000, null, function (p) { return p.ship.level; }, 4),
    a("ship6",    "Coup de Burst",         "Fully upgrade your ship",              3e9,   250000, null, function (p) { return p.ship.level; }, SHIPS.length - 1),
    a("crew1",    "First Mate",            "Recruit your first crewmate",          1e7,   1000,  null, function (p) { return crewCount(p); }, 1),
    a("crew5",    "A Proper Crew",         "Recruit 5 crewmates",                  1.5e8, 15000, null, function (p) { return crewCount(p); }, 5),
    a("crew10",   "Straw Hat Pirates",     "Recruit the whole crew",               2e9,   200000, null, function (p) { return crewCount(p); }, CREW.length),
    a("bought1",  "Window Shopping",       "Buy a card at the card shop",          3e6,   300,   null, function (p) { return p.stats.bought; }, 1),
    a("bought50", "Regular Customer",      "Buy 50 cards at the card shop",        2e8,   15000, null, function (p) { return p.stats.bought; }, 50),
    a("graded1",  "Slabbed",               "Get a card graded",                    1e7,   1000,  null, function (p) { return p.stats.graded; }, 1),
    a("gem1",     "Gem Mint",              "Get a 10",                             2e8,   20000, null, function (p) { return p.stats.gem10; }, 1),
    a("gem10",    "Perfect Ten",           "Get ten 10s",                          2.5e9, 200000, null, function (p) { return p.stats.gem10; }, 10),
    a("show1",    "Show Floor",            "Visit a card show",                    5e6,   500,   null, function (p) { return p.stats.shows; }, 1),
    a("show10",   "Show Regular",          "Visit 10 card shows",                  3e8,   20000, null, function (p) { return p.stats.shows; }, 10),
    a("sharpeye", "Sharp Eye",             "Buy a card at a show for under 75% of its market price", 1e8, 10000, null, function (p) { return p.stats.showSteals; }, 1),
    a("burned",   "Got Burned",            "Buy a fake at a card show",            1e7,   500,   null, function (p) { return p.stats.fakes; }, 1),
    a("vintage5", "Vintage Collector",     "Bring home 5 genuine vintage cards from card shows", 2e8, 15000, null, function (p) { return p.stats.vintage; }, 5),
    a("goldrare", "First Edition",         "Bring home a genuine 2005-06 Gold Rare", 5e8, 30000, null, function (p) { return p.stats.goldRares; }, 1),
    a("promo25",  "Promo Hunter",          "Bring home 25 genuine promos from card shows", 8e8, 50000, null, function (p) { return p.stats.promos; }, 25),
    a("rookie",   "Rookie",                "Own the 1999 Hyper Battle Luffy (C01), from a card show or a pack", 1.5e9, 120000, null,
      function (p) { return p.stats.rookie; }, 1),
    a("carddass10","Carddass Kid",         "Open 10 Hyper Battle vending packs", 3e8, 20000, null,
      function (p) { return setStats(p, "HYPERBATTLE").packs; }, 10),
    a("grail",    "Holy Grail",            "Bring home a genuine grail (a $1,000+ promo or vintage card)", 3e9, 250000, null,
      function (p) { return p.stats.grails; }, 1),
    a("sealed1",  "Shrink Wrap",           "Buy a sealed product",                 5e6,   500,   null, function (p) { return Object.keys(p.sealed).length + p.stats.sealedOpened; }, 1),
    a("sealed5",  "Hoarder",               "Hold 5 sealed products at once",       1.2e8, 10000, null, function (p) { return Object.keys(p.sealed).length; }, 5),
    a("investor", "Investor",              "Hold a sealed product worth twice what you paid", 1e9, 80000,
      null, function (p) { return bestSealedGain(p, Date.now()); }, 2, "x"),
    a("cosm3",    "Fashion Pirate",        "Own 3 cosmetics",                      6e7,   5000,  null, function (p) { return Object.keys(p.cosmetics.owned).length; }, 3),
    a("cosmAll",  "Dressed to Kill",       "Own every cosmetic",                   2e9,   150000, null, function (p) { return Object.keys(p.cosmetics.owned).length; }, BACKDROPS.length + SLABS.length - 2),
    a("spend1m",  "Money Talks",           "Spend ฿1,000,000 in total",            2e8,   20000, null, function (p) { return p.stats.spent; }, 1e6, "money"),
    a("spend100m","Berry Burner",          "Spend ฿100,000,000 in total",          4e9,   500000, null, function (p) { return p.stats.spent; }, 1e8, "money"),

    // seasons, weekly bounties, the set registry
    a("season1",  "Season Hero",           "Finish a season's reward track",       3e8,   20000, null, function (p) { return p.stats.seasonsDone; }, 1),
    a("season6",  "Six Seasons at Sea",    "Finish 6 seasons' reward tracks",      2e9,   150000, null, function (p) { return p.stats.seasonsDone; }, 6),
    a("season12", "A Year of Legends",     "Finish 12 seasons' reward tracks",     5e9,   500000, null, function (p) { return p.stats.seasonsDone; }, 12),
    a("weekly10", "Weekly Regular",        "Complete 10 weekly bounties",          8e7,   5000,  null, function (p) { return p.stats.weeklyDone; }, 10),
    a("weekly100","Bounty Hunter",         "Complete 100 weekly bounties",         1.5e9, 100000, null, function (p) { return p.stats.weeklyDone; }, 100),
    a("reg1k",    "Registered",            "Reach a set registry score of 1,000",  2e8,   15000, null, function (p) { return registryTotal(p); }, 1000),
    a("reg10k",   "Hall of Fame",          "Reach a set registry score of 10,000", 2.5e9, 200000, null, function (p) { return registryTotal(p); }, 10000),
    a("gemset",   "Gem Mint Master",       "Every card of a set graded 10",        5.5e9, 1000000, null,
      function (p) { return setsWhere(p, function (s) { return s.total > 0 && s.gem >= s.total; }); }, 1)
];

// one set's stats, with defaults for anything not recorded yet
function setStats(p, set) {
    var s = (p.stats.bySet || {})[set] || {};
    return { packs: s.packs || 0, boxes: s.boxes || 0, cases: s.cases || 0, pulled: s.pulled || {}, god: s.god || 0,
             gem: s.gem || 0, graded: s.graded || 0, total: s.total || 0, registry: s.registry || 0,
             completion: s.completion || 0, groups: s.groups || {}, present: s.present || null, value: s.value || 0 };
}

function setPulled(s, tiers) {
    return tiers.reduce(function (n, t) { return n + (s.pulled[t] || 0); }, 0);
}

// the set board's posters, by key; `needs`: only shown when the set has one of these tiers
var SET_POSTERS = [
    { key: "pack1",    title: "Landfall",            text: "Open a pack",                         bounty: 1e6,   reward: 200,    count: function (s) { return s.packs; }, goal: 1 },
    { key: "pack24",   title: "A Box's Worth",       text: "Open 24 packs",                       bounty: 5e6,   reward: 800,    count: function (s) { return s.packs; }, goal: 24 },
    { key: "box1",     title: "Box Breaker",         text: "Open a whole box",                    bounty: 1e7,   reward: 1500,   count: function (s) { return s.boxes; }, goal: 1 },
    { key: "c25",      title: "Recruiter",           text: "Own a quarter of the set",            bounty: 5e6,   reward: 500,    count: function (s) { return s.completion; }, goal: 0.25, fmt: "pct" },
    { key: "c50",      title: "Halfway There",       text: "Own half of the set",                 bounty: 3e7,   reward: 3000,   count: function (s) { return s.completion; }, goal: 0.5, fmt: "pct" },
    { key: "leaders",  title: "Every Captain",       text: "Own every Leader",                    bounty: 2e7,   reward: 2000,   needs: ["L"],   count: function (s) { return s.groups.leaders || 0; }, goal: 1, fmt: "pct" },
    { key: "sr",       title: "Super Crew",          text: "Own every Super Rare",                bounty: 6e7,   reward: 6000,   needs: ["SR"],  count: function (s) { return s.groups.sr || 0; }, goal: 1, fmt: "pct" },
    { key: "pack100",  title: "Regular",             text: "Open 100 packs",                      bounty: 5e7,   reward: 5000,   count: function (s) { return s.packs; }, goal: 100 },
    { key: "c75",      title: "Almost There",        text: "Own 75% of the set",                  bounty: 1.2e8, reward: 10000,  count: function (s) { return s.completion; }, goal: 0.75, fmt: "pct" },
    { key: "case1",    title: "Case Closed",         text: "Open every box in a case",            bounty: 1.5e8, reward: 15000,  count: function (s) { return s.cases; }, goal: 1 },
    { key: "sec",      title: "Keeper of Secrets",   text: "Own every Secret Rare",               bounty: 2e8,   reward: 20000,  needs: ["SEC", "SEC_AA"], count: function (s) { return s.groups.sec || 0; }, goal: 1, fmt: "pct" },
    { key: "worth250k", title: "Treasury",           text: "Own cards from the set worth ฿250,000", bounty: 2e8, reward: 15000,  count: function (s) { return s.value; }, goal: 250000, fmt: "money" },
    { key: "chase1",   title: "Grand Line Treasure", text: "Pull a chase card: Treasure Rare, Gold SP, Manga or Super Alt Art", bounty: 3e8, reward: 25000, needs: CHASE_TIERS,
      count: function (s) { return setPulled(s, CHASE_TIERS); }, goal: 1 },
    { key: "pack500",  title: "Local Legend",        text: "Open 500 packs",                      bounty: 5e8,   reward: 40000,  count: function (s) { return s.packs; }, goal: 500 },
    { key: "aa",       title: "Alternate Universe",  text: "Own every Alternate Art",             bounty: 6e8,   reward: 50000,  needs: ["AA", "L_AA", "TEX"], count: function (s) { return s.groups.aa || 0; }, goal: 1, fmt: "pct" },
    { key: "case3",    title: "Warlord of the Sea",  text: "Open 3 whole cases",                  bounty: 1e9,   reward: 60000,  count: function (s) { return s.cases; }, goal: 3 },
    { key: "chase3",   title: "Treasure Fleet",      text: "Pull 3 chase cards",                  bounty: 1.5e9, reward: 100000, needs: CHASE_TIERS, count: function (s) { return setPulled(s, CHASE_TIERS); }, goal: 3 },
    { key: "worth2m",  title: "Royal Treasury",      text: "Own cards from the set worth ฿2,500,000", bounty: 2e9, reward: 150000, count: function (s) { return s.value; }, goal: 2500000, fmt: "money" },
    { key: "god",      title: "Divine Intervention", text: "Open a god pack",                     bounty: 2.5e9, reward: 200000, count: function (s) { return s.god; }, goal: 1 },
    { key: "gem5",     title: "Gem Collector",       text: "Get 5 different cards of the set graded 10", bounty: 5e8, reward: 30000,
      count: function (s) { return s.gem; }, goal: 5 },
    { key: "gemAll",   title: "Gem Mint Master Set", text: "Every card of the set graded 10", bounty: 6e9, reward: 1000000,
      count: function (s) { return s.total ? s.gem / s.total : 0; }, goal: 1, fmt: "pct" },
    { key: "c100",     title: "Master Set",          text: "Own every card in the set",           bounty: 3e9,   reward: 250000, count: function (s) { return s.completion; }, goal: 1, fmt: "pct" }
];

// a set's wanted posters, shaped like ACHIEVEMENTS (with .set)
function setAchievements(set) {
    return SET_POSTERS.map(function (t) {
        return { id: set + ":" + t.key, set: set, title: t.title, text: t.text, bounty: t.bounty, reward: t.reward,
                 needs: t.needs || null, goal: t.goal, fmt: t.fmt || "",
                 count: function (p) { return t.count(setStats(p, set)); },
                 test: function (p) { return t.count(setStats(p, set)) >= t.goal; } };
    });
}

// the posters a set's board shows: the ones its cards make possible (all of them until we know its cards)
function setBoard(p, set) {
    var present = setStats(p, set).present;
    return setAchievements(set).filter(function (x) {
        return !x.needs || !present || x.needs.some(function (t) { return present.indexOf(t) >= 0; });
    });
}

var ACHIEVEMENT_BY_ID = {};
ACHIEVEMENTS.forEach(function (x) { ACHIEVEMENT_BY_ID[x.id] = x; });
var SET_POSTER_BY_KEY = {};
SET_POSTERS.forEach(function (t) { SET_POSTER_BY_KEY[t.key] = t; });

function bountyOf(id) {
    if (ACHIEVEMENT_BY_ID[id]) return ACHIEVEMENT_BY_ID[id].bounty;
    var t = SET_POSTER_BY_KEY[id.slice(id.indexOf(":") + 1)];
    return t ? t.bounty : 0;
}

// set: "" = everything (the overall bounty, saved sets too), else just that set's posters
function totalBounty(p, set) {
    var posters = Object.keys(p.achievements).reduce(function (sum, id) {
        if (set && id.indexOf(set + ":") !== 0) return sum;
        return sum + bountyOf(id);
    }, 0);
    if (set) return posters;
    var c = p.collections || {};
    return Object.keys(c).reduce(function (sum, id) { return sum + (c[id].bounty || 0); }, posters);
}

// ---- collections: sets of slabs saved in a display case (collections.js) ----------
// A saved set's slabs are locked in its case and it's worth more than they are;
// the first time a collection is saved you get a reward and a bounty, and again
// (the difference) the first time it's saved as a Gem Set (every slab a 10).
var SET_BONUS = 0.25, GEM_SET_BONUS = 0.5;     // worth this much over its slabs
var SET_REWARD = 0.1, GEM_SET_REWARD = 0.2;    // once, a share of what the slabs are worth
var SET_REWARD_MIN = 2000;
var SET_BOUNTY_PER_SLOT = 2e7;                 // on the wanted board; twice that for a Gem Set

function setBonus(gem) { return gem ? GEM_SET_BONUS : SET_BONUS; }

// pay a saved collection's reward if it hasn't had it (or not as a Gem Set yet);
// worth: what its slabs are worth. Returns the wanted poster to show, or null.
function rewardSet(p, id, title, slots, worth, gem) {
    p.collections = p.collections || {};
    var had = p.collections[id];
    if (had && (had.gem || !gem)) return null;
    var bounty = SET_BOUNTY_PER_SLOT * slots * (gem ? 2 : 1);
    var reward = Math.max(SET_REWARD_MIN, Math.round(worth * (gem ? GEM_SET_REWARD : SET_REWARD) / 10) * 10);
    var pay = Math.max(0, reward - (had ? had.reward || 0 : 0));
    if (pay) earn(p, pay, "sets");
    p.collections[id] = { day: dayOf(Date.now()), bounty: bounty, reward: Math.max(reward, had ? had.reward || 0 : 0), gem: !!gem };
    return { kind: "achievement", a: { title: title, text: gem ? "Saved as a Gem Set: every slab a 10" : "Saved in a display case",
                                       bounty: bounty - (had ? had.bounty || 0 : 0), reward: pay } };
}

// a locked poster's progress, as text ("" when it has none)
function posterProgress(x, p) {
    if (!x.count) return "";
    var c = Math.min(x.count(p), x.goal);
    if (x.fmt === "pct") return Math.floor(c * 100) + "% / " + Math.round(x.goal * 100) + "%";
    if (x.fmt === "money") return formatBounty(c) + " / " + formatBounty(x.goal);
    if (x.fmt === "x") return c.toFixed(2) + "× / " + x.goal + "×";
    return format(c).slice(1) + " / " + format(x.goal).slice(1);
}

function posterFraction(x, p) {
    return x.count ? Math.max(0, Math.min(1, x.count(p) / x.goal)) : 0;
}

// ---- state ------------------------------------------------------------------------

function fresh(now) {
    return {
        version: 1,
        berries: 1000,                 // a little starting money
        freePacks: 1,
        freePackClock: now,            // when the next free pack started counting
        streak: { count: 0, day: "" },
        income: { day: "", earned: 0 },
        focus: { startedAt: 0, endsAt: 0, idleMinutes: 0 },
        stats: { packs: 0, boxes: 0, cases: 0, sold: 0, soldValue: 0, earned: 0, focus: 0,
                 sets: {}, pulled: {}, bestCompletion: 0, value: 0, godPacks: 0,
                 bySet: {},                       // set -> { packs, boxes, cases, pulled, completion, groups, present, value }
                 backfilled: 1,                   // 0: the set boards still need back-dating from the collection (see backfill)
                 spent: 0, bought: 0, boughtValue: 0, graded: 0, gem10: 0, sealedOpened: 0,
                 seasonsDone: 0, weeklyDone: 0, shows: 0, showSteals: 0, fakes: 0,
                 vintage: 0, promos: 0, goldRares: 0, grails: 0, rookie: 0 },
        achievements: {},              // id -> date unlocked
        collections: {},               // saved collection id -> { day, bounty, reward, gem } (rewarded once)
        bounties: { day: "", list: [] },
        // the Port
        ship: { level: 0 },
        crew: {},                      // id -> date recruited
        grading: {},                   // order id -> { key, card, service, fee, grade, sentAt, readyAt }
        sealed: {},                    // id -> { set, setName, kind, boxes, paid, rate, at }
        prepaidBoxes: {},              // set -> boxes opened from sealed products, waiting in box mode
        shop: { day: "", bought: {} }, // today's deals bought (card key -> true)
        cosmetics: { owned: {}, backdrop: "default", slab: "classic" },
        ledger: { since: dayOf(now), total: {}, days: {} },  // see ledgerAdd
        show: { day: "", entered: 0, left: 0, stock: null, bought: {}, haggled: {}, looks: 0 },   // the card show (see enterShow)
        weekly: { week: "", event: "", set: "", setName: "", list: [] },   // this week's event and bounties
        season: { id: "", counts: {}, done: {}, tiers: {} },               // this month's season (see seasonGoals)
        seasons: {},                   // past seasons: id -> { points, tiers }
        titles: {}                     // season titles: id -> "Hero of ..."
    };
}

function parse(text, now) {
    var p = fresh(now);
    try {
        var saved = text ? JSON.parse(text) : null;
        if (saved) {
            Object.keys(saved).forEach(function (k) { p[k] = saved[k]; });
            if (p.stats.backfilled === undefined) p.stats.backfilled = 0;   // saved before the set boards
            Object.keys(fresh(now).stats).forEach(function (k) { if (p.stats[k] === undefined) p.stats[k] = fresh(now).stats[k]; });
            // from before per-set stats: carry over the pack counts
            Object.keys(p.stats.sets).forEach(function (k) { if (!p.stats.bySet[k]) p.stats.bySet[k] = { packs: p.stats.sets[k] }; });
        }
    } catch (e) {}
    return p;
}

// read-modify-write: fn(p) changes p; returns { p, result: fn's return value }
function update(host, path, fn) {
    var p = parse(host.readText(path), Date.now());
    var result = fn(p);
    host.writeText(path, JSON.stringify(p));
    return { p: p, result: result };
}

function dayOf(t) {
    var d = new Date(t);
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2);
}

function hash(text) {
    var h = 2166136261;
    for (var i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
    return function () {
        h = (h + 0x6D2B79F5) | 0;
        var t = Math.imul(h ^ (h >>> 15), 1 | h);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// The day's bounties (three; four with Jinbe), the same all day. sets: [{ id, name }] to pick from.
function makeBounties(day, sets, count) {
    var rnd = hash("bounties " + day);
    var set = sets.length ? sets[Math.floor(rnd() * sets.length)] : null;
    var all = [
        { kind: "packs",   goal: 2 + Math.floor(rnd() * 3), reward: 400 },
        { kind: "leader",  goal: 1, reward: 500 },
        { kind: "srplus",  goal: 1 + Math.floor(rnd() * 2), reward: 600 },
        { kind: "sell",    goal: 3 + Math.floor(rnd() * 6), reward: 300 },
        { kind: "focus",   goal: 1, reward: 0, freePack: true },
        { kind: "income",  goal: 500, reward: 300 }
    ];
    if (set) all.push({ kind: "setPacks", set: set.id, setName: set.name, goal: 1 + Math.floor(rnd() * 3), reward: 700 });
    var picked = [];
    while (picked.length < (count || 3) && all.length) picked.push(all.splice(Math.floor(rnd() * all.length), 1)[0]);
    return picked.map(function (b) { b.progress = 0; b.done = false; return b; });
}

function bountyText(b) {
    switch (b.kind) {
    case "packs":    return "Open " + b.goal + " packs";
    case "setPacks": return "Open " + b.goal + " " + b.setName + " pack" + (b.goal > 1 ? "s" : "");
    case "leader":   return "Pull a Leader";
    case "srplus":   return "Pull " + (b.goal > 1 ? b.goal + " cards" : "a card") + " that's Super Rare or better";
    case "sell":     return "Sell " + b.goal + " cards";
    case "focus":    return "Finish a focus session";
    case "income":   return "Earn " + format(b.goal) + " by being active";
    }
    return b.kind;
}

function bountyRewardText(b) {
    return b.freePack ? "a free pack" : format(b.reward);
}

// New day / time passing: free packs, the streak, a fresh set of bounties.
// Returns notable events: [{ kind: "streak", count, reward, freePack } | { kind: "freePack" }]
function accrue(p, now, sets) {
    var events = [];
    var step = freePackHours(p) * 3600 * 1000, max = freePackMax(p);
    if (p.freePacks >= max) {
        p.freePackClock = now;
    } else {
        while (p.freePackClock + step <= now && p.freePacks < max) {
            p.freePacks++;
            p.freePackClock += step;
            events.push({ kind: "freePack" });
        }
        if (p.freePacks >= max) p.freePackClock = now;
    }
    var today = dayOf(now);
    if (p.streak.day !== today) {
        var yesterday = dayOf(now - 86400 * 1000);
        var dayBefore = dayOf(now - 2 * 86400 * 1000);   // Chopper patches up a streak that missed one day
        var keeps = p.streak.day === yesterday || (hasCrew(p, "chopper") && p.streak.day === dayBefore);
        p.streak.count = keeps ? p.streak.count + 1 : 1;
        p.streak.day = today;
        var reward = STREAK_REWARD[Math.min(p.streak.count, STREAK_REWARD.length) - 1];
        var bonusPack = p.streak.count % 7 === 0;
        earn(p, reward, "streak");
        if (bonusPack) p.freePacks++;
        events.push({ kind: "streak", count: p.streak.count, reward: reward, freePack: bonusPack });
    }
    // sets: [{ id, name }] for the day's set bounty, or a function returning them (only called on a new day)
    if (p.bounties.day !== today && sets) p.bounties = { day: today, list: makeBounties(today, typeof sets === "function" ? sets() : sets,
                                                                                hasCrew(p, "jinbe") ? 4 : 3) };
    var week = weekOf(now);
    if (p.weekly.week !== week && sets) {
        var list = typeof sets === "function" ? sets() : sets, rnd = hash("week " + week);
        var featured = list.length ? list[Math.floor(rnd() * list.length)] : { id: "", name: "" };
        p.weekly = { week: week, event: eventFor(week).id, set: featured.id, setName: featured.name,
                     list: makeWeeklyBounties(week, featured) };
    }
    // a card show you never walked out of (the day's over): you've gone home
    var sh = p.show;
    if (sh && sh.day && sh.entered && !sh.left && sh.day !== today) {
        var recap = leaveShow(p, now);
        if (recap) events = events.concat(recap.done);
    }
    var month = monthOf(now);
    if (p.season.id !== month) {
        if (p.season.id) p.seasons[p.season.id] = { points: seasonPoints(p), tiers: Object.keys(p.season.tiers).length };
        p.season = { id: month, counts: {}, done: {}, tiers: {} };
    }
    return events;
}

// time until the next free pack, ms (0 when full)
function nextFreePackIn(p, now) {
    if (p.freePacks >= freePackMax(p)) return 0;
    return Math.max(0, p.freePackClock + freePackHours(p) * 3600 * 1000 - now);
}

// Spend on a pack/box: a free pack first (packs only), then berries.
// what: for the ledger ("packs", "boxes", "cases"). Returns "free", "paid" or "" (can't afford).
function pay(p, price, freePackOk, what) {
    if (freePackOk && p.freePacks > 0) {
        p.freePacks--;
        if (p.freePacks === freePackMax(p) - 1) p.freePackClock = Date.now();   // start counting again
        ledgerAdd(p, "free", what || "packs", 1);
        return "free";
    }
    return spend(p, price, what || "packs") ? "paid" : "";
}

// pay berries for anything (what: a SPENDING key, for the ledger); false if you can't afford it.
// unstated: not counted in stats.spent (the spending posters), only in the ledger
function spend(p, amount, what, unstated) {
    amount = Math.round(amount);
    if (p.berries < amount) return false;
    p.berries -= amount;
    if (!unstated) p.stats.spent += amount;
    ledgerAdd(p, "spend", what || "other", amount);
    return true;
}

// get berries (source: an EARNINGS key, for the ledger); unstated: not counted in stats.earned
function earn(p, amount, source, unstated) {
    amount = Math.round(amount);
    p.berries += amount;
    if (!unstated) p.stats.earned += amount;
    ledgerAdd(p, "earn", source || "other", amount);
}

// ---- the ledger: where berries come from and go, per day and in total -------------
// (the wanted board shows it; it's how the economy gets balanced)

var EARNINGS = [["income", "Passive income"], ["sell", "Selling cards"], ["posters", "Wanted posters"],
                ["setPosters", "Set wanted posters"], ["sets", "Saved sets"], ["bounties", "Daily bounties"], ["streak", "Daily streak"],
                ["focus", "Focus sessions"], ["sealed", "Selling sealed"], ["season", "Season rewards"], ["other", "Other"]];
var SPENDING = [["packs", "Packs"], ["boxes", "Boxes"], ["cases", "Cases"], ["shop", "Card shop"], ["show", "Card shows"], ["grading", "Grading"],
                ["sealed", "Sealed products"], ["ship", "Ship"], ["crew", "Crew"], ["cosmetics", "Cosmetics"], ["other", "Other"]];
var LEDGER_DAYS = 14;   // days kept day by day

function ledgerAdd(p, side, key, amount) {
    if (!amount) return;
    if (!p.ledger) p.ledger = { since: dayOf(Date.now()), total: {}, days: {} };
    var day = dayOf(Date.now()), l = p.ledger;
    [l.total, l.days[day] || (l.days[day] = {})].forEach(function (t) {
        if (!t[side]) t[side] = {};
        t[side][key] = (t[side][key] || 0) + amount;
    });
    var days = Object.keys(l.days).sort();
    while (days.length > LEDGER_DAYS) delete l.days[days.shift()];
}

// { earn: { key: ฿ }, spend: { key: ฿ }, free: { key: count } } over the last `days` days
// (today = 1), or all of it (days 0)
function ledger(p, days, now) {
    var l = p.ledger || { total: {}, days: {} }, out = { earn: {}, spend: {}, free: {} };
    var parts = [l.total];
    if (days) {
        parts = [];
        for (var i = 0; i < days; i++) parts.push(l.days[dayOf(now - i * 86400 * 1000)] || {});
    }
    parts.forEach(function (t) {
        ["earn", "spend", "free"].forEach(function (side) {
            Object.keys(t[side] || {}).forEach(function (k) { out[side][k] = (out[side][k] || 0) + t[side][k]; });
        });
    });
    return out;
}

function ledgerSum(m) {
    return Object.keys(m).reduce(function (n, k) { return n + m[k]; }, 0);
}

// Something happened. ev:
//   { type: "pack", set, tiers: [...], completion: 0..1, god,  a pack was opened (god: a god pack); groups: how much of
//     groups: { leaders: 0..1, ... }, present: [tiers] }       each SET_GROUPS you own, present: the set's tiers
//   { type: "box", set } / { type: "case", set }               a box / a whole case finished
//   { type: "value", total, bySet: { set: ฿ } }                what the collection is worth now
//   { type: "sell", count, value }                             cards sold
//   { type: "focus" }                                          a focus session finished
//   { type: "income", amount }                                 passive income
// Returns what got completed: [{ kind: "achievement", a } | { kind: "bounty", b }]
function bySet(p, set) {
    if (!p.stats.bySet[set]) p.stats.bySet[set] = {};
    var b = p.stats.bySet[set];
    ["packs", "boxes", "cases", "completion", "value", "god"].forEach(function (k) { if (b[k] === undefined) b[k] = 0; });
    if (!b.pulled) b.pulled = {};
    if (!b.groups) b.groups = {};
    return b;
}

function record(p, ev) {
    var s = p.stats, done = [];
    if (ev.type === "pack") {
        var b = bySet(p, ev.set);
        s.packs++;
        s.rookie += ev.rookie || 0;   // the 1999 Hyper Battle Luffy came out of it
        b.packs++;
        s.sets[ev.set] = (s.sets[ev.set] || 0) + 1;
        ev.tiers.forEach(function (t) {
            s.pulled[t] = (s.pulled[t] || 0) + 1;
            b.pulled[t] = (b.pulled[t] || 0) + 1;
        });
        if (ev.completion > s.bestCompletion) s.bestCompletion = ev.completion;
        if (ev.completion > b.completion) b.completion = ev.completion;
        Object.keys(ev.groups || {}).forEach(function (g) { if (ev.groups[g] > (b.groups[g] || 0)) b.groups[g] = ev.groups[g]; });
        if (ev.present) b.present = ev.present;
        if (ev.god) {
            s.godPacks++;
            b.god++;
        }
    } else if (ev.type === "box") {
        s.boxes++;
        if (ev.set) bySet(p, ev.set).boxes++;
    } else if (ev.type === "case") {
        s.cases++;
        if (ev.set) bySet(p, ev.set).cases++;
    } else if (ev.type === "value") {
        s.value = ev.total;
        s.setBonus = ev.bonus || 0;   // saved sets' bonus: passive income only
        Object.keys(s.bySet).forEach(function (k) { s.bySet[k].value = 0; });
        Object.keys(ev.bySet).forEach(function (k) { bySet(p, k).value = ev.bySet[k]; });
    } else if (ev.type === "sell") {
        s.sold += ev.count;
        s.soldValue += ev.value;
    } else if (ev.type === "focus") {
        s.focus++;
    } else if (ev.type === "bought") {
        s.bought += ev.count;
        s.boughtValue += ev.value;
    } else if (ev.type === "graded") {
        s.graded++;
        if (ev.grade === 10) s.gem10++;
    } else if (ev.type === "show") {       // left a card show (fakes and steals only come out then)
        s.shows++;
        s.showSteals += ev.steals || 0;
        s.fakes += ev.fakes || 0;
        s.vintage += ev.vintage || 0;
        s.promos += ev.promos || 0;
        s.goldRares += ev.goldRares || 0;
        s.grails += ev.grails || 0;
        s.rookie += ev.rookie || 0;
    } else if (ev.type === "reviewed") {   // a review lifted a slab: a new 10 counts, it's not another grading
        if (ev.grade === 10) s.gem10++;
    } else if (ev.type === "registry") {
        // ev.bySet: { set: { gem, graded, total, registry } } from the collection's slabs
        Object.keys(s.bySet).forEach(function (k) { s.bySet[k].gem = 0; s.bySet[k].graded = 0; s.bySet[k].registry = 0; });
        Object.keys(ev.bySet).forEach(function (k) { Object.assign(bySet(p, k), ev.bySet[k]); });
    }

    // the season's counters
    var c = p.season.counts, count = function (k, n) { if (n) c[k] = (c[k] || 0) + n; };
    if (ev.type === "pack") {
        count("packs", 1);
        count("srplus", countTiers(ev.tiers, SR_TIERS));
        count("aaplus", countTiers(ev.tiers, AA_TIERS));
        count("chase", countTiers(ev.tiers, CHASE_TIERS));
        if (!c["set:" + ev.set]) count("sets", 1);
        c["set:" + ev.set] = 1;
    }
    if (ev.type === "box") count("boxes", 1);
    if (ev.type === "focus") count("focus", 1);
    if (ev.type === "income") count("activeMinutes", ev.minutes || 0);
    if (ev.type === "graded") { count("graded", 1); if (ev.grade >= 9) count("gem9", 1); }
    if (ev.type === "sell") count("sold", ev.count);
    if (ev.type === "bought") count("bought", ev.count);

    // daily and weekly bounties
    var bonanza = eventIs(p, "bonanza") ? 2 : 1;
    (p.bounties.list || []).forEach(function (b) {
        if (b.done || !bountyStep(b, ev)) return;
        b.done = true;
        if (b.freePack) p.freePacks += bonanza;
        else earn(p, b.reward * bonanza, "bounties");
        count("daily", 1);
        done.push({ kind: "bounty", b: b });
    });
    (p.weekly.list || []).forEach(function (b) {
        if (b.done || !bountyStep(b, ev)) return;
        b.done = true;
        if (b.packs) p.freePacks += b.packs * bonanza;
        if (b.reward) earn(p, b.reward * bonanza, "bounties");
        s.weeklyDone++;
        count("weekly", 1);
        done.push({ kind: "weekly", b: b });
    });
    // weekly bounties that count daily bounties
    var dailyDone = done.filter(function (d) { return d.kind === "bounty"; }).length;
    (p.weekly.list || []).forEach(function (b) {
        if (b.done || b.kind !== "daily" || !dailyDone) return;
        b.progress = Math.min(b.goal, b.progress + dailyDone);
        if (b.progress < b.goal) return;
        b.done = true;
        if (b.packs) p.freePacks += b.packs * bonanza;
        if (b.reward) earn(p, b.reward * bonanza, "bounties");
        s.weeklyDone++;
        count("weekly", 1);
        done.push({ kind: "weekly", b: b });
    });

    // achievements: the set posters first (the overall board counts them)
    var check = function (x) {
        if (p.achievements[x.id] || !x.test(p)) return;
        p.achievements[x.id] = dayOf(Date.now());
        if (x.reward) earn(p, x.reward, x.set ? "setPosters" : "posters");
        count("posters", 1);
        done.push({ kind: "achievement", a: x });
    };
    Object.keys(s.bySet).forEach(function (set) { if (!isShowSet(set)) setAchievements(set).forEach(check); });   // no board for those
    ACHIEVEMENTS.forEach(check);
    return done.concat(seasonCheck(p));
}

// ฿ a minute while you're active: grows with what your collection is worth
function incomePerMinute(p) {
    var worth = (p.stats.value || 0) + (p.stats.setBonus || 0);   // saved sets count their bonus here
    var base = INCOME_PER_MINUTE + INCOME_VALUE_SCALE * Math.sqrt(Math.max(0, worth) / 1000);
    return Math.round(base * incomeBonus(p));
}

// the ship's bonus, and Nami's
function incomeBonus(p) {
    return (1 + ship(p).income) * (hasCrew(p, "nami") ? 1.25 : 1);
}

function incomeDailyCap(p) {
    return incomePerMinute(p) * INCOME_CAP_MINUTES;
}

// passive income for `minutes` active minutes (capped per day). device: this
// computer when syncing; with two computers on at once only one of them earns.
var INCOME_LOCK_MS = 150 * 1000;

function addIncome(p, minutes, now, device) {
    var today = dayOf(now);
    if (p.income.day !== today) p.income = { day: today, earned: 0 };
    if (device && p.income.device && p.income.device !== device && now - (p.income.at || 0) < INCOME_LOCK_MS) return [];
    if (device) {
        p.income.device = device;
        p.income.at = now;
    }
    var amount = Math.min(incomePerMinute(p) * minutes, incomeDailyCap(p) - p.income.earned);
    if (amount <= 0) return [];
    p.income.earned += amount;
    earn(p, amount, "income");
    return record(p, { type: "income", amount: amount, minutes: minutes });
}

// ---- focus sessions ---------------------------------------------------------------

function focusRunning(p, now) {
    return p.focus.endsAt > now;
}

function startFocus(p, now) {
    p.focus = { startedAt: now, endsAt: now + FOCUS_MINUTES * 60 * 1000, idleMinutes: 0 };
}

function stopFocus(p) {
    p.focus = { startedAt: 0, endsAt: 0, idleMinutes: 0 };
}

// a finished session pays out; returns the completions
function focusBerries(p) {
    return hasCrew(p, "zoro") ? FOCUS_BERRIES * 2 : FOCUS_BERRIES;
}

function finishFocus(p) {
    stopFocus(p);
    p.freePacks += eventIs(p, "training") ? 2 : 1;
    earn(p, focusBerries(p), "focus");
    return record(p, { type: "focus" });
}

// ---- what cards are worth ----------------------------------------------------------

// market: { "<card id>|<name>": usd } from optcgapi (see Stage.loadMarket)
function cardValue(card, market) {
    var usd = market ? market[card.id + "|" + card.name] : undefined;
    if (usd !== undefined && usd !== null && usd > 0) return Math.max(1, Math.round(usd * USD_TO_BERRY));
    return BASE_VALUE[card.tier] || 5;
}

// What the collection is worth: { total, bySet: { set: ฿ } }, from collection.json
// (or the given collection's cards) and the market prices cached in
// market/<set>.json (base values without them).
// graded: the collection's graded slabs (read with the cards when cards isn't given).
// saved: the collection's saved sets ({ id: { slabs: [slab id], gem } }): their bonus is
// out.bonus, which only counts toward passive income (not the value posters)
function collectionValue(host, dataDir, cards, graded, saved) {
    var markets = {}, out = { total: 0, bySet: {}, bonus: 0 };
    if (!cards) {
        try {
            var col = JSON.parse(host.readText(dataDir + "/collection.json") || "{}");
            cards = col.cards || {};
            graded = col.graded || {};
            saved = col.sets || {};
        } catch (e) { cards = {}; }
    }
    var market = function (set) {
        if (markets[set] === undefined) {
            markets[set] = null;
            try { markets[set] = (JSON.parse(host.readText(dataDir + "/market/" + set + ".json") || "null") || {}).prices || null; } catch (err) {}
        }
        return markets[set];
    };
    var add = function (set, v) {
        out.total += v;
        out.bySet[set] = (out.bySet[set] || 0) + v;
    };
    Object.keys(cards).forEach(function (k) {
        var set = k.slice(0, k.indexOf(":")), e = cards[k];
        add(set, cardValue(e, market(set)) * (e.count || 1));
    });
    Object.keys(graded || {}).forEach(function (id) {
        var g = graded[id];
        add(g.set, slabValue(g, market(g.set)));
    });
    Object.keys(saved || {}).forEach(function (id) {
        var bonus = setBonus(saved[id].gem);
        (saved[id].slabs || []).forEach(function (sid) {
            var g = (graded || {})[sid];
            if (g) out.bonus += slabValue(g, market(g.set)) * bonus;
        });
    });
    return out;
}

// record a fresh collectionValue() (plus your sealed products); returns the completions
function setValue(p, v) {
    return record(p, { type: "value", total: v.total + sealedTotal(p, Date.now()), bySet: v.bySet, bonus: v.bonus || 0 });
}

// How much of a set you own: { completion, groups: { leaders: 0..1, ... }, present: [tiers] }.
// cards: the set's cards (cards.json), owned: the collection's cards.
function setProgress(set, cards, owned) {
    var seen = {}, present = {}, have = {}, total = {}, n = 0, got = 0, groups = {};
    cards.forEach(function (c) {
        var k = set + ":" + c.image.split("/").pop();
        present[c.tier] = true;
        if (seen[k]) return;
        seen[k] = true;
        n++;
        if (owned[k]) got++;
        Object.keys(SET_GROUPS).forEach(function (g) {
            if (SET_GROUPS[g].indexOf(c.tier) < 0) return;
            total[g] = (total[g] || 0) + 1;
            if (owned[k]) have[g] = (have[g] || 0) + 1;
        });
    });
    Object.keys(total).forEach(function (g) { groups[g] = (have[g] || 0) / total[g]; });
    return { completion: n ? got / n : 0, groups: groups, present: Object.keys(present) };
}

// Once, for progress saved before the set boards existed: rebuild each set's
// stats from the collection (what you own, by tier; how complete the set is;
// boxes in the current case) and award every poster that's already earned.
// Returns [{ kind: "backfill", count, reward, bounty }], or [] if nothing new.
function backfill(p, host, dataDir, cacheRoot) {
    if (p.stats.backfilled) return [];
    p.stats.backfilled = 1;
    var cards = {};
    try { cards = JSON.parse(host.readText(dataDir + "/collection.json") || "{}").cards || {}; } catch (e) {}
    var bySetOwned = {};
    Object.keys(cards).forEach(function (k) {
        var set = k.slice(0, k.indexOf(":")), e = cards[k];
        if (!bySetOwned[set]) bySetOwned[set] = {};
        bySetOwned[set][e.tier] = (bySetOwned[set][e.tier] || 0) + (e.count || 1);
    });
    Object.keys(bySetOwned).forEach(function (set) {
        var b = bySet(p, set);
        Object.keys(bySetOwned[set]).forEach(function (t) { b.pulled[t] = Math.max(b.pulled[t] || 0, bySetOwned[set][t]); });
        var db = null, cs = null;
        try { db = JSON.parse(host.readText(cacheRoot + "/" + set + "/cards.json") || "null"); } catch (e) {}
        if (db && db.cards) {
            var sp = setProgress(set, db.cards, cards);
            b.completion = Math.max(b.completion, sp.completion);
            Object.keys(sp.groups).forEach(function (g) { b.groups[g] = Math.max(b.groups[g] || 0, sp.groups[g]); });
            b.present = sp.present;
            if (b.completion > p.stats.bestCompletion) p.stats.bestCompletion = b.completion;
        }
        try { cs = JSON.parse(host.readText(dataDir + "/case-" + set + ".json") || "null"); } catch (e) {}
        if (cs) b.boxes = Math.min(p.stats.boxes, Math.max(b.boxes, (cs.box || 0) + (cs.boxRecorded ? 1 : 0)));
    });
    var done = setValue(p, collectionValue(host, dataDir, cards)).filter(function (d) { return d.kind === "achievement"; });
    if (!done.length) return [];
    return [{ kind: "backfill", count: done.length,
              reward: done.reduce(function (n, d) { return n + d.a.reward; }, 0),
              bounty: done.reduce(function (n, d) { return n + d.a.bounty; }, 0) }];
}

// ---- the Port: ship and crew ---------------------------------------------------------

function ship(p) {
    return SHIPS[Math.min(SHIPS.length - 1, Math.max(0, (p.ship && p.ship.level) || 0))];
}

function nextShip(p) {
    return SHIPS[((p.ship && p.ship.level) || 0) + 1] || null;
}

function freePackHours(p) {
    return ship(p).freeHours;
}

function freePackMax(p) {
    return ship(p).freeMax;
}

function upgradeShip(p) {
    var next = nextShip(p);
    if (!next || !spend(p, next.price, "ship")) return false;
    p.ship.level++;
    return true;
}

function hasCrew(p, id) {
    return !!(p.crew && p.crew[id]);
}

function crewCount(p) {
    return CREW.filter(function (c) { return hasCrew(p, c.id); }).length;
}

function recruit(p, id) {
    var c = CREW.filter(function (x) { return x.id === id; })[0];
    if (!c || hasCrew(p, id) || !spend(p, c.price, "crew")) return false;
    p.crew[id] = dayOf(Date.now());
    return true;
}

// pack odds the crew changes: { luck (Usopp), godBoost (Luffy) }
// set: the set being opened (the week's featured set gets better odds)
function packOptions(p, set) {
    var luck = (hasCrew(p, "usopp") ? 1.15 : 1) * (set && eventIs(p, "featured") && p.weekly.set === set ? 1.25 : 1);
    var god = (hasCrew(p, "luffy") ? 2 : 1) * (eventIs(p, "treasure") ? 3 : 1);
    var boost = eventIs(p, "manga") ? { MANGA: 2, SUPER: 2, SUPER_L: 2, TR: 2, SIGNED: 2 } : null;
    return { luck: luck, godBoost: god, boost: boost };
}

function sellBonus(p) {
    return (hasCrew(p, "brook") ? 1.1 : 1) * (eventIs(p, "golden") ? 1.15 : 1);
}

// ---- the Port: grading ------------------------------------------------------------------

// p (optional): during Grading Rush every service costs the Value price
function gradingFee(serviceId, value, p) {
    if (p && eventIs(p, "grading")) serviceId = "value";
    var g = GRADING.filter(function (x) { return x.id === serviceId; })[0] || GRADING[0];
    return Math.round(Math.max(g.base, g.pct * value) / 10) * 10;
}

// odds: [[grade, p], ...] (GRADE_ODDS without)
function rollGrade(odds) {
    odds = odds || GRADE_ODDS;
    var r = Math.random(), acc = 0;
    for (var i = 0; i < odds.length; i++) {
        acc += odds[i][1];
        if (r < acc) return odds[i][0];
    }
    return odds[odds.length - 1][0];
}

// a slab: { set, key, id, name, tier, image, grade, ... }
function slabValue(slab, market) {
    return Math.round(cardValue(slab, market) * (slab.diamond ? DIAMOND_MULT : GRADE_MULT[slab.grade] || 1));
}

// send one copy of a card off (the caller takes it out of the collection);
// card: { id, name, tier, set, image, key, cond }, value: what it's worth raw
function sendToGrading(p, card, serviceId, value, now) {
    var g = GRADING.filter(function (x) { return x.id === serviceId; })[0];
    var fee = gradingFee(serviceId, value, p);
    if (!g || !spend(p, fee, "grading")) return null;
    var id = now.toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    var hours = g.hours * (eventIs(p, "grading") ? 0.5 : 1);
    var diamond = Math.random() < DIAMOND_CHANCE;
    p.grading[id] = { card: card, service: g.id, fee: fee, grade: diamond ? 10 : rollGrade(serviceOdds(card.cond, g.id)),
                      sentAt: now, readyAt: now + hours * 3600 * 1000 };
    if (diamond) p.grading[id].diamond = true;
    return id;
}

function readyOrders(p, now) {
    return Object.keys(p.grading).filter(function (id) { return p.grading[id].readyAt <= now; });
}

// take a returned order out (the caller puts the slab in the collection); returns the slab
function collectOrder(p, id) {
    var o = p.grading[id];
    if (!o) return null;
    delete p.grading[id];
    var slab = Object.assign({}, o.card, { grade: o.grade, gradedAt: Date.now(), service: o.service });
    if (o.diamond) slab.diamond = true;
    return slab;
}

// ---- the Port: the card shop ------------------------------------------------------------

// Today's deals, the same all day: pool is [{ key, card }] (cards you could
// find in your downloaded sets); a couple of chase cards, some mid ones, some cheap.
// per: deals of each kind (2; 3 in Merchant Week)
function dailyDeals(day, pool, rank, per) {
    var rnd = hash("deals " + day), out = [], used = {};
    per = per || 2;
    var tiers = [[10, per], [6, per], [4, per], [0, per]];   // [minimum rank, how many]
    tiers.forEach(function (t, i) {
        var max = i ? tiers[i - 1][0] : 99;
        var fits = pool.filter(function (x) { var r = rank(x.card); return r >= t[0] && r < max && !used[x.key]; });
        for (var k = 0; k < t[1] && fits.length; k++) {
            var x = fits.splice(Math.floor(rnd() * fits.length), 1)[0];
            used[x.key] = true;
            out.push(x);
        }
    });
    return out;
}

// Merchant Week: deals at market price, three of each kind instead of two
function dealMarkup(p) {
    return eventIs(p, "merchant") ? 1 : DEAL_MARKUP;
}

function dealsPer(p) {
    return eventIs(p, "merchant") ? 3 : 2;
}

function shopToday(p, now) {
    var today = dayOf(now);
    if (p.shop.day !== today) p.shop = { day: today, bought: {} };
    return p.shop;
}

// ---- the Port: sealed products --------------------------------------------------------------

// a vintage product (from a card show) is worth its unopened packs' share; a resealed one, nothing
function sealedValue(item, now) {
    if (item.resealed) return 0;
    var weeks = Math.max(0, now - item.at) / (7 * 86400 * 1000);
    var left = item.vintage ? item.packs / item.packsTotal : 1;
    return Math.round(item.paid * left * Math.pow(1 + item.rate, weeks));
}

function sealedTotal(p, now) {
    return Object.keys(p.sealed || {}).reduce(function (n, id) { return n + sealedValue(p.sealed[id], now); }, 0);
}

function bestSealedGain(p, now) {
    return Object.keys(p.sealed || {}).reduce(function (best, id) {
        var it = p.sealed[id];
        return Math.max(best, it.paid ? sealedValue(it, now) / it.paid : 0);
    }, 0);
}

// age: 0 (the newest set) .. 1 (the oldest): older sets gain value faster.
// Buying and selling sealed products isn't counted as spent or earned (the
// spending and earning posters), so they can't be farmed by buying and selling.
function buySealed(p, set, setName, kind, boxes, price, age) {
    if (!spend(p, price, "sealed", true)) return null;
    var now = Date.now(), id = now.toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    p.sealed[id] = { set: set, setName: setName, kind: kind, boxes: boxes, paid: price, at: now,
                     rate: SEALED_RATE[0] + (SEALED_RATE[1] - SEALED_RATE[0]) * Math.max(0, Math.min(1, age)) };
    return id;
}

function sellSealed(p, id) {
    var it = p.sealed[id];
    if (!it) return 0;
    var v = sealedValue(it, Date.now());
    delete p.sealed[id];
    earn(p, v, "sealed", true);
    return v;
}

// open it: its boxes wait for you in that set's box mode
function openSealed(p, id) {
    var it = p.sealed[id];
    if (!it) return null;
    delete p.sealed[id];
    p.prepaidBoxes[it.set] = (p.prepaidBoxes[it.set] || 0) + it.boxes;
    p.stats.sealedOpened++;
    return it;
}

// a vintage product: one of its packs comes out (Stage rips it). Returns { origin, resealed, left,
// line, product (the kind), name, cards }
function openVintagePack(p, id) {
    var it = p.sealed[id];
    if (!it || !it.vintage || !(it.packs > 0)) return null;
    if (it.packs === it.packsTotal) p.stats.sealedOpened++;
    it.packs--;
    if (!it.packs) delete p.sealed[id];
    return { origin: it.setName, resealed: !!it.resealed, left: it.packs, line: it.line || "ccg", product: it.kind,
             name: it.name || "", cards: it.cards || null };
}

// ---- the Port: cosmetics -----------------------------------------------------------------------

function cosmetic(list, id) {
    return list.filter(function (x) { return x.id === id; })[0] || list[0];
}

function backdrop(p) {
    var id = p.cosmetics && p.cosmetics.backdrop;
    if (id && id.indexOf("season-") === 0 && ownsCosmetic(p, id)) return seasonBackdrop(id);
    return cosmetic(BACKDROPS, id);
}

function slabStyle(p) {
    return cosmetic(SLABS, p.cosmetics && p.cosmetics.slab);
}

function ownsCosmetic(p, id) {
    return id === "default" || id === "classic" || !!(p.cosmetics && p.cosmetics.owned[id]);
}

// buy (if needed) and wear it; kind: "backdrop" | "slab"
// the playmats to download ahead of time ([[id, tcgplayer id, page]], for
// fetch_cards.py background); the ones that come with the app aren't
function playmatDownloads() {
    return BACKDROPS.filter(function (b) { return b.playmat && !b.playmat.file; })
        .map(function (b) { return [b.id, String(b.playmat.tcg || ""), b.playmat.page || ""]; });
}

function equipCosmetic(p, kind, id) {
    if (kind === "backdrop" && id.indexOf("season-") === 0) {   // earned in a season, never sold
        if (!ownsCosmetic(p, id)) return false;
        p.cosmetics.backdrop = id;
        return true;
    }
    var item = cosmetic(kind === "slab" ? SLABS : BACKDROPS, id);
    if (item.id !== id) return false;
    if (!ownsCosmetic(p, id)) {
        if (!spend(p, item.price, "cosmetics")) return false;
        p.cosmetics.owned[id] = dayOf(Date.now());
    }
    p.cosmetics[kind] = id;
    return true;
}

// The best art of a character (or ship) among cards: the highest rarity whose
// name starts with `name` ("Monkey.D.Luffy" matches "Monkey.D.Luffy (Alternate Art)"),
// or the card with that id. name: a list is tried in order.
// rank: card -> rarity rank. Returns a card or null.
function artFor(cards, name, rank) {
    if (Array.isArray(name)) {
        for (var i = 0; i < name.length; i++) {
            var found = artFor(cards, name[i], rank);
            if (found) return found;
        }
        return null;
    }
    var byId = cards.filter(function (c) { return c.id === name; });
    if (byId.length) return byId[0];
    var norm = function (t) { return t.toLowerCase().replace(/[^a-z0-9]/g, ""); };
    var want = norm(name), best = null;
    cards.forEach(function (c) {
        if (norm(c.name).indexOf(want) !== 0) return;
        // "Nami" mustn't match "Namur": the next character is the end or a variant tag
        var rest = c.name.replace(/\s*\(.*$/, "");
        if (norm(rest) !== want) return;
        if (!best || rank(c) > rank(best)) best = c;
    });
    return best;
}

// ---- the week ---------------------------------------------------------------------------

// the Monday a week starts on, "2026-10-12"
function weekOf(t) {
    var d = new Date(t);
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() - (d.getDay() + 6) % 7);
    return dayOf(d.getTime());
}

function monthOf(t) {
    return dayOf(t).slice(0, 7);
}

// the events take turns, week by week
function eventFor(week) {
    var monday = new Date(week + "T12:00:00");
    return EVENTS[Math.floor(monday.getTime() / (7 * 86400 * 1000)) % EVENTS.length];
}

function currentEvent(p) {
    var e = EVENTS.filter(function (x) { return x.id === p.weekly.event; })[0];
    return e ? Object.assign({}, e, { text: e.text.replace("{set}", p.weekly.setName || p.weekly.set || "This week's set") }) : null;
}

function eventIs(p, id) {
    return !!(p && p.weekly && p.weekly.event === id && p.weekly.week === weekOf(Date.now()));
}

var SR_TIERS = ["SR", "AA", "TEX", "SEC", "L_AA", "SP", "SEC_AA", "SUPER_L", "SP_GOLD", "TR", "MANGA", "SIGNED", "SUPER", "PANDA"];
var AA_TIERS = ["AA", "TEX", "SEC", "L_AA", "SP", "SEC_AA", "SUPER_L", "SP_GOLD", "TR", "MANGA", "SIGNED", "SUPER"];

function countTiers(tiers, which) {
    return tiers.filter(function (t) { return which.indexOf(t) >= 0; }).length;
}

// a bounty's progress from an event; true when that makes it done (daily and weekly bounties)
function bountyStep(b, ev) {
    var add = 0;
    if (ev.type === "pack") {
        if (b.kind === "packs") add = 1;
        if (b.kind === "setPacks" && ev.set === b.set) add = 1;
        if (b.kind === "leader") add = ev.tiers.filter(function (t) { return t === "L" || t === "L_AA" || t === "SUPER_L"; }).length;
        if (b.kind === "srplus") add = countTiers(ev.tiers, SR_TIERS);
        if (b.kind === "aaplus") add = countTiers(ev.tiers, AA_TIERS);
    }
    if (ev.type === "box" && b.kind === "boxes") add = 1;
    if (ev.type === "sell" && b.kind === "sell") add = ev.count;
    if (ev.type === "focus" && b.kind === "focus") add = 1;
    if (ev.type === "income" && b.kind === "income") add = ev.amount;
    if (ev.type === "income" && b.kind === "active") add = ev.minutes || 0;
    if (ev.type === "graded" && b.kind === "graded") add = 1;
    if (!add) return false;
    b.progress = Math.min(b.goal, b.progress + add);
    return b.progress >= b.goal;
}

// this week's three bounties: bigger goals, paid mostly in free packs
function makeWeeklyBounties(week, featured) {
    var rnd = hash("weekly " + week), r = function (lo, hi) { return lo + Math.floor(rnd() * (hi - lo + 1)); };
    var all = [
        { kind: "packs",  goal: r(40, 60), packs: 3 },
        { kind: "boxes",  goal: 2,         reward: 5000 },
        { kind: "srplus", goal: r(12, 20), reward: 4000 },
        { kind: "aaplus", goal: r(3, 5),   packs: 2 },
        { kind: "sell",   goal: 40,        reward: 3000 },
        { kind: "focus",  goal: 5,         packs: 2 },
        { kind: "active", goal: 600,       packs: 2 },
        { kind: "daily",  goal: 10,        packs: 3 },
        { kind: "graded", goal: 3,         reward: 4000 }
    ];
    if (featured && featured.id) all.push({ kind: "setPacks", set: featured.id, setName: featured.name, goal: 15, reward: 5000 });
    var picked = [];
    while (picked.length < 3 && all.length) picked.push(all.splice(Math.floor(rnd() * all.length), 1)[0]);
    return picked.map(function (b) { b.progress = 0; b.done = false; return b; });
}

function weeklyText(b) {
    switch (b.kind) {
    case "packs":    return "Open " + b.goal + " packs";
    case "boxes":    return "Open " + b.goal + " booster boxes";
    case "srplus":   return "Pull " + b.goal + " Super Rares or better";
    case "aaplus":   return "Pull " + b.goal + " Alt Arts or better";
    case "sell":     return "Sell " + b.goal + " cards";
    case "focus":    return "Finish " + b.goal + " focus sessions";
    case "active":   return "Be active at your computer " + Math.round(b.goal / 60) + " hours";
    case "daily":    return "Complete " + b.goal + " daily bounties";
    case "graded":   return "Get " + b.goal + " cards graded";
    case "setPacks": return "Open " + b.goal + " " + b.setName + " packs";
    }
    return b.kind;
}

function weeklyRewardText(b) {
    return b.packs ? b.packs + " free packs" : format(b.reward);
}

// ---- seasons ---------------------------------------------------------------------------------

function arcOf(seasonId) {
    return ARCS[(parseInt(seasonId.slice(5, 7), 10) - 1 + ARCS.length) % ARCS.length];
}

var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function seasonName(seasonId) {
    return "Season of " + arcOf(seasonId).name + "  ·  " + MONTHS[parseInt(seasonId.slice(5, 7), 10) - 1] + " " + seasonId.slice(0, 4);
}

// this season's goals: [{ id, text, goal, pts }], the same for everyone that month
function seasonGoals(seasonId) {
    var rnd = hash("season " + seasonId), pool = SEASON_GOALS.slice(), out = [];
    while (out.length < SEASON_GOAL_COUNT && pool.length) {
        var g = pool.splice(Math.floor(rnd() * pool.length), 1)[0];
        var n = g.goal[0] + Math.floor(rnd() * (g.goal[1] - g.goal[0] + 1));
        out.push({ id: g.id, text: g.text.replace("{n}", n), goal: n, pts: g.pts });
    }
    return out;
}

function seasonCount(p, id) {
    if (id === "streak") return p.streak.count;
    if (id === "active") return Math.floor((p.season.counts.activeMinutes || 0) / 60);
    return p.season.counts[id] || 0;
}

function seasonPoints(p) {
    return seasonGoals(p.season.id).reduce(function (n, g) { return n + (p.season.done[g.id] ? g.pts : 0); }, 0);
}

function seasonTierText(t, seasonId) {
    return t.text.replace("{arc}", arcOf(seasonId).name);
}

// goals reached and rewards earned since last time: [{ kind: "season", goal | tier }]
function seasonCheck(p) {
    if (!p.season.id) return [];
    var out = [];
    seasonGoals(p.season.id).forEach(function (g) {
        if (p.season.done[g.id] || seasonCount(p, g.id) < g.goal) return;
        p.season.done[g.id] = dayOf(Date.now());
        out.push({ kind: "season", goal: g });
    });
    var pts = seasonPoints(p);
    SEASON_TIERS.forEach(function (t, i) {
        if (p.season.tiers[i] || pts < t.pts) return;
        p.season.tiers[i] = dayOf(Date.now());
        if (t.packs) p.freePacks += t.packs;
        if (t.berries) earn(p, t.berries, "season");
        if (t.backdrop) p.cosmetics.owned["season-" + p.season.id] = dayOf(Date.now());
        if (t.title) p.titles[p.season.id] = "Hero of " + arcOf(p.season.id).name;
        if (i === SEASON_TIERS.length - 1) p.stats.seasonsDone++;
        out.push({ kind: "season", tier: i, text: seasonTierText(t, p.season.id) });
    });
    return out;
}

// a season's exclusive backdrop, like the BACKDROPS
function seasonBackdrop(id) {
    var sid = id.slice(7), arc = arcOf(sid);
    return { id: id, name: arc.name + " (" + sid + ")", price: 0, base: arc.base, glow: arc.glow, season: sid };
}

// the latest title earned ("" for none)
function title(p) {
    var ids = Object.keys(p.titles || {}).sort();
    return ids.length ? p.titles[ids[ids.length - 1]] : "";
}

// ---- the set registry ---------------------------------------------------------------------------
// Your best grade of each card of a set, weighted by rarity: a 10 of a Manga
// Rare scores far more than a 10 of a common.

// graded: the collection's slabs; cardsBySet: { set: [cards] }; rank: card -> rarity rank
function registry(graded, cardsBySet, rank) {
    var best = {}, out = {};
    Object.keys(graded || {}).forEach(function (id) {
        var g = graded[id], key = g.key || (g.set + ":" + (g.image || "").split("/").pop());
        if (!best[key] || g.grade > best[key].grade) best[key] = g;
    });
    Object.keys(cardsBySet).forEach(function (set) {
        var seen = {}, total = 0, r = { gem: 0, graded: 0, total: 0, registry: 0 };
        cardsBySet[set].forEach(function (c) {
            var key = set + ":" + c.image.split("/").pop();
            if (seen[key] || c.tier === "DON" || c.tier === "DON_GOLD" || c.tier === "DON_SP") return;
            seen[key] = true;
            total++;
            var b = best[key];
            if (!b) return;
            r.graded++;
            if (b.grade === 10) r.gem++;
            r.registry += b.grade * (1 + rank(c));
        });
        r.total = total;
        if (r.graded) out[set] = r;
    });
    return out;
}

function registryTotal(p) {
    var b = p.stats.bySet || {};
    return Object.keys(b).reduce(function (n, k) { return n + (b[k].registry || 0); }, 0);
}

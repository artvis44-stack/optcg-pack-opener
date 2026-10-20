.pragma library
// Pull tiers, their look, and the pack / case generators.
//
// Bandai publishes no slot maps or odds. The structure and rates are community
// data -- TCGTalk case openings (OP-15, OP-16, OP-17), onepiece.app, retailer
// box guides -- plus Bandai's official per-set print runs. Per-set numbers
// live in sets.json; the defaults below cover what isn't documented per set.
//
// Main booster pack (12 cards):
//   slots 1-7   Common            (a regular Leader replaces one)
//   slots 8-10  Uncommon
//   slot 11     Rare              (or a Pandaman variant, OP-17)
//   slot 12     hit slot          Rare unless it holds an SR or premium hit. A
//                                 Leader here is only ever a parallel.
//   DON!!       replaces a common and sits at the very back, after the hit.
// Extra boosters have no uncommons. Premium boosters are 10-card packs with a
// foil reprint slot, and every pack has a DON!! (at the front) -- 2 per box
// are gold.
//
// Case/box: a case (12 boxes) holds a roughly fixed budget of each hit, so
// hits trade off between its boxes. How hits sit in the case changed:
//   mapped      (up to OP-15) a fixed collated pattern -- the same box/pack
//               positions every case -- and a Leader pack is a "dead pack"
//   transition  (OP-16) random positions; a Leader pack can hold an SR
//   random      (OP-17) random positions, 1-4 premium hits per box

var info = {
    C:       { label: "Common",                 holo: 0.0,  gold: 0.0, rank: 0,  color: "#9aa4b2" },
    UC:      { label: "Uncommon",               holo: 0.0,  gold: 0.0, rank: 1,  color: "#7fd1b9" },
    DON:     { label: "DON!! Card",             holo: 0.25, gold: 0.0, rank: 1,  color: "#e6e6e6" },
    R:       { label: "Rare",                   holo: 0.35, gold: 0.0, rank: 2,  color: "#5fa8ff" },
    FOIL:    { label: "Foil",                   holo: 0.6,  gold: 0.0, rank: 2,  color: "#8fd3ff" },
    L:       { label: "Leader",                 holo: 0.0,  gold: 0.0, rank: 3,  color: "#ff5a5a" },
    SR:      { label: "Super Rare",             holo: 0.75, gold: 0.0, rank: 4,  color: "#c07bff" },
    PANDA:   { label: "Pandaman Art",           holo: 0.6,  gold: 0.3, rank: 5,  color: "#ffe9a8" },
    TOPPER:  { label: "Box Topper",             holo: 0.6,  gold: 0.2, rank: 5,  color: "#ffcf8a" },
    AA:      { label: "Alternate Art",          holo: 1.0,  gold: 0.0, rank: 6,  color: "#ff7bd5" },
    TEX:     { label: "Textured Foil",          holo: 1.0,  gold: 0.3, rank: 6,  color: "#b8f0c0" },
    SEC:     { label: "Secret Rare",            holo: 1.0,  gold: 0.4, rank: 7,  color: "#ffd34d" },
    L_AA:    { label: "Alternate Art Leader",   holo: 1.0,  gold: 0.2, rank: 8,  color: "#ff6b6b" },
    SP:      { label: "Special Card",           holo: 1.0,  gold: 0.6, rank: 9,  color: "#ffb347" },
    DON_GOLD:{ label: "Gold DON!!",             holo: 1.0,  gold: 1.0, rank: 9,  color: "#ffd700" },
    DON_SP:  { label: "Special Foil DON!!",     holo: 1.0,  gold: 0.0, rank: 9,  color: "#9be7ff" },
    SEC_AA:  { label: "Secret Rare Alt Art",    holo: 1.0,  gold: 0.5, rank: 10, color: "#ffd34d" },
    SUPER_L: { label: "Super Leader Parallel",  holo: 1.0,  gold: 0.7, rank: 11, color: "#ffd700" },
    SP_GOLD: { label: "Gold / Silver SP",       holo: 1.0,  gold: 1.0, rank: 12, color: "#ffe08a" },
    TR:      { label: "Treasure Rare",          holo: 1.0,  gold: 1.0, rank: 12, color: "#ffe08a" },
    MANGA:   { label: "Manga Rare",             holo: 1.0,  gold: 0.2, rank: 13, color: "#ffffff" },
    SIGNED:  { label: "Gold-Stamped Signature", holo: 1.0,  gold: 1.0, rank: 13, color: "#ffd700" },
    SUPER:   { label: "Super Alternate Art",    holo: 1.0,  gold: 0.8, rank: 14, color: "#ffd700" }
};

// premium tiers that take the hit slot
var HIT_TIERS = ["AA", "TEX", "SEC", "L_AA", "SEC_AA", "SP", "TR", "SUPER_L", "SP_GOLD", "MANGA", "SIGNED", "SUPER"];

// Per product family: pack layout and case budget (per 12-box case).
// fixed = about this many per case; lottery = Poisson mean per case.
var FAMILIES = {
    main: {
        packsPerBox: 24, boxes: 12,
        slots: ["C", "C", "C", "C", "C", "C", "C", "UC", "UC", "UC", "RARE", "HIT"],
        srPerBox: 7, leadersPerBox: 4, donPerBox: 1, hitsPerBox: null,
        fixed:   { AA: 12, SEC: 6, L_AA: 4, SEC_AA: 1, PANDA: 0, DON_GOLD: 2 },
        lottery: { SP: 1, TR: 0.75, MANGA: 0.3, SUPER: 0.15, SUPER_L: 0.15, SP_GOLD: 0.15, SIGNED: 0.05, DON_SP: 0 }
    },
    extra: {   // EB: 12 cards, no uncommons; no published rates at all
        packsPerBox: 24, boxes: 12,
        slots: ["C", "C", "C", "C", "C", "C", "C", "C", "R", "R", "RARE", "HIT"],
        srPerBox: 6, leadersPerBox: 2, donPerBox: 1, hitsPerBox: null,
        fixed:   { AA: 12, SEC: 4, L_AA: 2, SEC_AA: 1, DON_GOLD: 2 },
        lottery: { SP: 3, MANGA: 0.3, TR: 0.5 }
    },
    premium: { // PRB: 10-card packs, 20 per box, a DON!! in every pack; rates unpublished
        packsPerBox: 20, boxes: 12,
        slots: ["C", "C", "C", "UC", "UC", "UC", "R", "FOIL", "RARE", "HIT"],
        srPerBox: 8, leadersPerBox: 0, donPerBox: 20, goldDonPerBox: 2, donFront: true, hitsPerBox: null,
        fixed:   { AA: 40, TEX: 12, SEC: 12, SEC_AA: 4, L_AA: 1 },
        lottery: { SP: 2, MANGA: 1 }
    }
};

// Japanese boosters (sets.json "lang": "jp"): the same cards (Japanese text),
// a different product. Packs are 6 cards: commons, an uncommon, and one slot
// that's a Rare or better in about half the packs (an Uncommon otherwise).
// A box has ~3-4 SRs, 4 Leaders and only 1-2 hits: the box patterns the JP
// community tallies are "2 parallels" 25%, "1 parallel" 42%, "1 SEC" 33%,
// so every box has one. A case (carton) is 12 boxes; premium boosters are
// 10 packs of 10 a box. No box toppers, no DON!! cards in these packs. All
// community estimates (toreca-begin, note.com tallies, torecamap): Bandai
// publishes none.
var FAMILIES_JP = {
    main: {
        packsPerBox: 24, boxes: 12,
        slots: ["C", "C", "C", "C", "UC", "HIT"],
        srPerBox: 3.5, leadersPerBox: 4, donPerBox: 0, rPerBox: 7.5, hitsPerBox: [1, 2],
        fixed:   { AA: 8, SEC: 4, L_AA: 2, SEC_AA: 1, SP: 1 },
        lottery: { TR: 0.75, MANGA: 0.1, SUPER: 0.1, SUPER_L: 0.1, SP_GOLD: 0.05, PANDA: 0 }
    },
    extra: {
        packsPerBox: 24, boxes: 12,
        slots: ["C", "C", "C", "C", "C", "HIT"],
        srPerBox: 3, leadersPerBox: 2, donPerBox: 0, rPerBox: 9, hitsPerBox: [1, 2],
        fixed:   { AA: 8, SEC: 3, L_AA: 1, SEC_AA: 1, SP: 1 },
        lottery: { MANGA: 0.1, TR: 0.3 }
    },
    premium: {
        packsPerBox: 10, boxes: 10,
        slots: ["C", "C", "C", "UC", "UC", "UC", "R", "FOIL", "RARE", "HIT"],
        srPerBox: 3.5, leadersPerBox: 0, donPerBox: 0, hitsPerBox: [2, 4],
        fixed:   { AA: 20, TEX: 6, SEC: 10, SEC_AA: 3, L_AA: 2 },
        lottery: { SP: 1, MANGA: 0.5 }
    }
};

// The full config for a set: its family's defaults with the set's overrides
// (from sets.json) merged in.
function setConfig(setInfo) {
    var family = (setInfo && setInfo.family) || "main";
    var fam = (setInfo && setInfo.lang === "jp" ? FAMILIES_JP : FAMILIES)[family];
    var cfg = {
        family: family,
        era: (setInfo && setInfo.era) || "random",
        packsPerBox: fam.packsPerBox, boxes: fam.boxes, slots: fam.slots,
        fixed: Object.assign({}, fam.fixed), lottery: Object.assign({}, fam.lottery)
    };
    ["srPerBox", "leadersPerBox", "donPerBox", "goldDonPerBox", "donFront", "hitsPerBox", "rPerBox", "packsPerBox", "boxes", "slots"].forEach(function (k) {
        cfg[k] = setInfo && setInfo[k] !== undefined ? setInfo[k] : fam[k];
    });
    var over = (setInfo && setInfo.case) || {};
    Object.keys(over).forEach(function (t) {
        if (cfg.fixed[t] !== undefined || cfg.lottery[t] === undefined) cfg.fixed[t] = over[t];
        else cfg.lottery[t] = over[t];
    });
    cfg.packsPerCase = cfg.packsPerBox * cfg.boxes;
    cfg.lang = (setInfo && setInfo.lang) || "en";
    cfg.boxUsd = setInfo && setInfo.boxUsd;   // the market price of a real sealed box (for reference)
    cfg.boxJpy = setInfo && setInfo.boxJpy;
    return cfg;
}

function caseAmount(cfg, tier) {
    return cfg.fixed[tier] !== undefined ? cfg.fixed[tier] : (cfg.lottery[tier] || 0);
}

function tierOf(card) {
    return card && info[card.tier] || info.C;   // card is briefly null while delegates tear down
}

// "Kaido (062) (Super Alternate Art)" -> "Kaido (062)"; the tier label says the rest
function displayName(card) {
    return card.name.replace(/\s*\((Alternate Art|Parallel|Manga|SP|SPR|TR|Super .*Alternate Art|Red Super Alternate Art|Pandaman Art|Gold|Silver|Special Foil|Box Topper|Wanted Poster|Full Art|Textured Foil|Jolly Roger Foil|Pirate Foil|Reprint|Gold-Stamped Signature)\)/g, "");
}

// ---- randomness -------------------------------------------------------------

function seededRandom(seedText) {   // mulberry32 over a string hash
    var h = 2166136261;
    for (var i = 0; i < seedText.length; i++) h = Math.imul(h ^ seedText.charCodeAt(i), 16777619);
    return function () {
        h = (h + 0x6D2B79F5) | 0;
        var t = Math.imul(h ^ (h >>> 15), 1 | h);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function pick(list, rnd) {
    return list[Math.floor((rnd || Math.random)() * list.length)];
}

function shuffle(list, rnd) {
    rnd = rnd || Math.random;
    for (var i = list.length - 1; i > 0; i--) {
        var j = Math.floor(rnd() * (i + 1));
        var tmp = list[i]; list[i] = list[j]; list[j] = tmp;
    }
    return list;
}

function poisson(mean) {
    var limit = Math.exp(-mean), k = 0, p = 1;
    do { k++; p *= Math.random(); } while (p > limit);
    return k - 1;
}

function group(cards) {
    var byTier = {};
    cards.forEach(function (c) { (byTier[c.tier] = byTier[c.tier] || []).push(c); });
    return byTier;
}

// ---- packs ------------------------------------------------------------------------

// Builds one pack from the family's slot layout. Each spec slot is a tier
// name (a random card of that tier) or a card object; leader/don may be empty.
function buildPack(byTier, cfg, spec) {
    var out = [], used = {};
    function add(slot) {
        var c = slot;
        if (typeof slot === "string") {
            var tier = byTier[slot] ? slot : "R";
            var pool = byTier[tier].filter(function (x) { return !used[x.image]; });
            c = pick(pool.length ? pool : byTier[tier]);
        }
        used[c.image] = true;
        out.push(c);
    }
    if (spec.don && cfg.donFront) add(spec.don);      // premium boosters: up front
    var slots = cfg.slots.slice();
    var lastC = slots.lastIndexOf("C");
    if (spec.don) slots.splice(lastC--, 1);           // the DON!! takes a common's place...
    if (spec.leader) slots[lastC] = spec.leader;      // ...and a Leader replaces another
    slots.forEach(function (s) {
        add(s === "RARE" ? (spec.rare || "R") : s === "HIT" ? hitOrRare(byTier, cfg, spec.hit) : s);
    });
    if (spec.don && !cfg.donFront) add(spec.don);     // ...at the very back
    return out;
}

// The hit slot without a hit: a Rare. Japanese packs have only rPerBox Rares
// a box there, so the rest of those packs get an Uncommon instead.
function hitOrRare(byTier, cfg, hit) {
    if (hit && hit !== "R") return hit;
    if (cfg.rPerBox === undefined || !byTier.UC) return "R";
    var open = cfg.packsPerBox - cfg.srPerBox - (cfg.hitsPerBox ? (cfg.hitsPerBox[0] + cfg.hitsPerBox[1]) / 2 : 1);
    return Math.random() < cfg.rPerBox / Math.max(1, open) ? "R" : "UC";
}

// srScale / premiumScale: how much likelier a hit is in a pack that may hold
// one (dead Leader packs push the box's hits into the other packs)
// boost: { tier: factor } for single tiers (a weekly event)
// If luck pushes the chances past HIT_CAP together, they're all scaled down
// alike, so every tier keeps its share (otherwise the rarest ones, rolled last,
// would never come up).
var HIT_CAP = 0.95;
function rollHit(byTier, cfg, srScale, premiumScale, boost) {
    var odds = [["SR", byTier.SR ? srScale * cfg.srPerBox / cfg.packsPerBox : 0]];
    HIT_TIERS.forEach(function (t) {
        if (byTier[t]) odds.push([t, premiumScale * ((boost && boost[t]) || 1) * caseAmount(cfg, t) / cfg.packsPerCase]);
    });
    var total = odds.reduce(function (n, o) { return n + o[1]; }, 0);
    var scale = total > HIT_CAP ? HIT_CAP / total : 1;
    var r = Math.random(), acc = 0;
    for (var i = 0; i < odds.length; i++) {
        acc += odds[i][1] * scale;
        if (r < acc) return odds[i][0];
    }
    return "R";
}

// A single pack with the case budget as odds.
// forceHit (testing / cheating): "L" forces a regular Leader, "PANDA" the
// Pandaman rare slot, "DON" / "DON_GOLD" / "DON_SP" the DON!! card, "GOD" a
// god pack, anything else the hit slot. Without one, about 1 pack in 5,760 is
// a god pack.
// opts (from your crew and the week's event, Progress.packOptions): luck -- hits
// that much likelier; godBoost -- god packs that much likelier; boost -- { tier: factor }.
function makePack(cards, setInfo, forceHit, opts) {
    var cfg = setConfig(setInfo);
    var luck = (opts && opts.luck) || 1, godBoost = (opts && opts.godBoost) || 1;
    if (forceHit === "GOD" || (!forceHit && Math.random() < godBoost * godPacksPerCase(setInfo) / cfg.packsPerCase))
        return makeGodPack(cards, setInfo);
    var byTier = group(cards);
    forceHit = forceHit && byTier[forceHit] ? forceHit : "";
    var special = ["L", "PANDA", "DON", "DON_GOLD", "DON_SP"];

    var leader = !!byTier.L && (forceHit === "L" || Math.random() < cfg.leadersPerBox / cfg.packsPerBox);
    var foils = ["DON_GOLD", "DON_SP"].filter(function (t) { return byTier[t]; });
    var foilRate = cfg.goldDonPerBox ? cfg.goldDonPerBox / cfg.packsPerBox
                 : foils.reduce(function (a, t) { return a + caseAmount(cfg, t); }, 0) / cfg.packsPerCase;
    var r = Math.random();
    var don = forceHit.indexOf("DON") === 0 ? forceHit
            : !byTier.DON ? ""
            : r < foilRate ? pick(foils)
            : r < cfg.donPerBox / cfg.packsPerBox ? "DON" : "";

    // older eras: a Leader pack is a "dead pack"; OP-16 lets it keep an SR
    var live = byTier.L ? cfg.packsPerBox / (cfg.packsPerBox - cfg.leadersPerBox) : 1;
    var hit = forceHit && special.indexOf(forceHit) < 0 ? forceHit
            : leader && cfg.era === "mapped" ? "R"
            : leader && cfg.era === "transition" ? rollHit(byTier, cfg, luck, 0)
            : rollHit(byTier, cfg, luck * (cfg.era === "mapped" ? live : 1), luck * (cfg.era === "random" ? 1 : live),
                      opts && opts.boost);
    var panda = byTier.PANDA && Math.random() < caseAmount(cfg, "PANDA") / cfg.packsPerCase;
    return buildPack(byTier, cfg, {
        leader: leader ? "L" : "",
        don: don,
        rare: forceHit === "PANDA" || panda ? "PANDA" : "R",
        hit: hit
    });
}

// ---- god packs --------------------------------------------------------------------
//
// A god pack is a normal-looking pack in a normal box where every card is a
// hit. Bandai doesn't acknowledge them or publish odds; the community puts
// them at about 1 per 10-20 cases (PRB-01, PRB-02, EB-03, OP-13), so here
// they're a lottery of GOD_PACKS_PER_CASE per case: about 1 in 5,760 packs
// for a 24-pack box. What's inside depends on the set (sets.json "god"):
//   parallel  every card a parallel (alt arts, SEC, SP...), the default
//   manga     PRB-01: every card a Manga Rare (comic parallel)
//   golddon   PRB-02: every card a Gold DON!!
//   sp        EB-03: every card an SP
//   demon     OP-13 "Demon Pack": the Five Elders parallels
// Card counts that a set can't fill (only 9 SPs in a 12-card pack) are
// topped up with parallels.

var GOD_PACKS_PER_CASE = 1 / 20;
var PARALLEL_TIERS = ["AA", "L_AA", "TEX", "SEC", "SEC_AA", "SP", "SP_GOLD", "TR", "MANGA", "SUPER", "SUPER_L"];
var GOD_KINDS = {
    parallel: { name: "God Pack",            tiers: PARALLEL_TIERS },
    manga:    { name: "Manga God Pack",      tiers: ["MANGA"] },
    golddon:  { name: "Gold DON!! God Pack", tiers: ["DON_GOLD"] },
    sp:       { name: "SP God Pack",         tiers: ["SP", "SP_GOLD"] },
    demon:    { name: "Demon Pack",          tiers: PARALLEL_TIERS,
                names: ["Saturn", "Mars", "Warcury", "Nusjuro", "Ju Peter"] }
};

function godKinds(setInfo) {
    var kinds = (setInfo && setInfo.god) || ["parallel"];
    return kinds.filter(function (k) { return GOD_KINDS[k]; });
}

function godPacksPerCase(setInfo) {
    return setInfo && setInfo.godPerCase !== undefined ? setInfo.godPerCase : GOD_PACKS_PER_CASE;
}

// A god pack of the given kind (default: one of the set's), as many cards as
// a normal pack, weakest first so the best comes last.
function makeGodPack(cards, setInfo, kind) {
    var cfg = setConfig(setInfo);
    var kinds = godKinds(setInfo);
    var g = GOD_KINDS[kind && GOD_KINDS[kind] ? kind : pick(kinds.length ? kinds : ["parallel"])];
    var size = cfg.slots.length;
    var main = cards.filter(function (c) {
        return g.tiers.indexOf(c.tier) >= 0
            && (!g.names || g.names.some(function (n) { return c.name.indexOf(n) >= 0; }));
    });
    var fill = cards.filter(function (c) { return PARALLEL_TIERS.indexOf(c.tier) >= 0 && main.indexOf(c) < 0; });
    if (!fill.length) fill = cards.filter(function (c) { return info[c.tier] && info[c.tier].rank >= 4; });
    var out = [], used = {};
    [shuffle(main.slice()), shuffle(fill.slice())].forEach(function (pool) {
        pool.forEach(function (c) {
            if (out.length < size && !used[c.image]) { used[c.image] = true; out.push(c); }
        });
    });
    while (out.length < size && (main.length || fill.length)) out.push(pick(main.length ? main : fill));   // tiny sets: repeats
    return out.sort(function (x, y) { return info[x.tier].rank - info[y.tier].rank; });
}

// every card a hit: no commons, uncommons, rares or Leaders
function isGodPack(pack) {
    return pack.length > 3 && pack.every(function (c) {
        return c.tier === "DON_GOLD" || PARALLEL_TIERS.indexOf(c.tier) >= 0;
    });
}

// which of the set's kinds it is (only the Gold DON!! one needs telling apart)
function godPackName(pack, setInfo) {
    if (pack.every(function (c) { return c.tier === "DON_GOLD"; })) return GOD_KINDS.golddon.name;
    var kinds = godKinds(setInfo).filter(function (k) { return k !== "golddon"; });
    return GOD_KINDS[kinds.length ? kinds[0] : "parallel"].name;
}

// ---- cases ------------------------------------------------------------------------

// A whole case: { boxes: [boxes][packs][cards], toppers: [one card per box or null] }
// opts: as for makePack (a case's hits are fixed, so only godBoost counts)
// a case's premium hits into its boxes (each { hits: [] }); place: the random
// source for the mapped era's fixed pattern
function dealHits(cfg, byTier, boxes, place) {
    var B = boxes.length, hits = [];
    HIT_TIERS.forEach(function (t) {
        if (!byTier[t]) return;
        var n = cfg.fixed[t] !== undefined ? Math.round(cfg.fixed[t]) : poisson(cfg.lottery[t] || 0);
        for (var k = 0; k < n; k++) hits.push(t);
    });
    if (cfg.era === "mapped") {
        // collated: dealt evenly around the case in the set's fixed order
        var boxOrder = shuffle(boxes.slice(), place);
        hits.sort(function (x, y) { return info[y].rank - info[x].rank; });
        hits.forEach(function (t, k) { boxOrder[k % B].hits.push(t); });
    } else {
        shuffle(hits).forEach(function (t) { boxes[Math.floor(Math.random() * B)].hits.push(t); });
        if (cfg.hitsPerBox) {   // nudge into the documented per-box range
            var lo = cfg.hitsPerBox[0], hi = cfg.hitsPerBox[1];
            for (var guard = 0; guard < 200; guard++) {
                var sorted = boxes.slice().sort(function (x, y) { return x.hits.length - y.hits.length; });
                var fewest = sorted[0], most = sorted[B - 1];
                if (most.hits.length > hi || (fewest.hits.length < lo && most.hits.length > lo))
                    fewest.hits.push(most.hits.splice(Math.floor(Math.random() * most.hits.length), 1)[0]);
                else
                    break;
            }
        }
    }
}

function makeCase(cards, setInfo, opts) {
    var cfg = setConfig(setInfo);
    var byTier = group(cards);
    var B = cfg.boxes, P = cfg.packsPerBox, b, i;
    // the "mapped" era places hits in a fixed pattern per set (same every case);
    // which card lands there is still random
    var place = cfg.era === "mapped" ? seededRandom((setInfo && setInfo.name) || "") : Math.random;
    var boxes = [];
    for (b = 0; b < B; b++) boxes.push({ hits: [], srs: [], leaders: [], dons: [], pandas: 0 });
    dealHits(cfg, byTier, boxes, place);

    // SRs: an even number of copies of each, dealt round-robin
    var srCards = byTier.SR || [];
    var copies = srCards.length ? Math.max(1, Math.round(cfg.srPerBox * B / srCards.length)) : 0;
    var srs = [];
    srCards.forEach(function (c) { for (var k = 0; k < copies; k++) srs.push(c); });
    var order = shuffle(boxes.slice());
    shuffle(srs).forEach(function (c, k) { order[k % B].srs.push(c); });

    // Leaders: an even pool of each Leader; fractional rates spread over boxes
    var lcards = byTier.L || [];
    var lTotal = lcards.length ? Math.round(cfg.leadersPerBox * B) : 0;
    var leaders = [];
    for (i = 0; i < lTotal; i++) leaders.push(lcards[i % lcards.length]);
    var lorder = shuffle(boxes.slice());
    shuffle(leaders).forEach(function (c, k) { lorder[k % B].leaders.push(c); });

    // DON!!: donPerBox each; gold / special foil ones replace a regular one
    if (byTier.DON) {
        boxes.forEach(function (box) { for (var k = 0; k < Math.round(cfg.donPerBox); k++) box.dons.push("DON"); });
        var foils = [];
        if (cfg.goldDonPerBox && byTier.DON_GOLD) {   // a fixed number in every box
            boxes.forEach(function (box) { box.dons.fill("DON_GOLD", 0, cfg.goldDonPerBox); });
        }
        for (i = 0; byTier.DON_GOLD && !cfg.goldDonPerBox && i < Math.round(cfg.fixed.DON_GOLD || 0); i++) foils.push("DON_GOLD");
        for (i = byTier.DON_SP ? poisson(cfg.lottery.DON_SP || 0) : 0; i > 0; i--) foils.push("DON_SP");
        foils.forEach(function (t) {
            var box = pick(boxes.filter(function (x) { return x.dons.indexOf("DON") >= 0; }));
            if (box) box.dons[box.dons.indexOf("DON")] = t;
        });
    }

    // Pandaman: random boxes, at most 2 in one box
    for (i = 0; byTier.PANDA && i < (cfg.fixed.PANDA || 0); i++)
        pick(boxes.filter(function (x) { return x.pandas < 2; })).pandas++;

    // deal each box's contents into distinct packs
    var dealt = boxes.map(function (box) {
        var specs = [], p, k;
        for (p = 0; p < P; p++) specs.push({ leader: "", don: "", rare: "R", hit: "R" });
        var slots = [];
        for (p = 0; p < P; p++) slots.push(p);
        shuffle(slots, place);
        // Leader packs first; in the mapped era they stay dead (no SR / premium)
        box.leaders.forEach(function (c, k) { specs[slots[k]].leader = c; });
        var others = slots.slice(box.leaders.length);
        if (cfg.era === "mapped") {
            box.hits.concat(box.srs).forEach(function (c, k) { if (k < others.length) specs[others[k]].hit = c; });
        } else if (cfg.era === "transition") {
            // premium hits avoid Leader packs; SRs can land anywhere left
            box.hits.forEach(function (t, k) { if (k < others.length) specs[others[k]].hit = t; });
            var open = shuffle(slots.filter(function (s) { return specs[s].hit === "R"; }));
            box.srs.forEach(function (c, k) { if (k < open.length) specs[open[k]].hit = c; });
        } else {
            var any = shuffle(slots.slice());
            box.hits.concat(box.srs).forEach(function (c, k) { if (k < any.length) specs[any[k]].hit = c; });
        }
        shuffle(slots.slice()).slice(0, box.dons.length).forEach(function (s, k) { specs[s].don = box.dons[k]; });
        shuffle(slots.slice()).slice(0, box.pandas).forEach(function (s) { specs[s].rare = "PANDA"; });
        return specs.map(function (spec) { return buildPack(byTier, cfg, spec); });
    });

    // god packs: a rare lottery per case, each replacing a random pack
    for (i = poisson(((opts && opts.godBoost) || 1) * godPacksPerCase(setInfo)); i > 0; i--)
        dealt[Math.floor(Math.random() * B)][Math.floor(Math.random() * P)] = makeGodPack(cards, setInfo);

    // box toppers (OP-01/02): one per box, outside the packs
    var toppers = boxes.map(function () { return byTier.TOPPER ? pick(byTier.TOPPER) : null; });
    return { boxes: dealt, toppers: toppers };
}

// What one box of the set holds, from dealing its hits round a case the way
// makeCase does, many times over (not from the box you're about to open): for
// each hit tier the set has, the chance of at least one in a box.
// godBoost: Progress.packOptions(...).godBoost
function boxChances(cards, setInfo, godBoost) {
    var cfg = setConfig(setInfo), byTier = group(cards), B = cfg.boxes, CASES = 2000, seen = {}, hits = [], b, k;
    for (k = 0; k < CASES; k++) {
        var boxes = [];
        for (b = 0; b < B; b++) boxes.push({ hits: [] });
        dealHits(cfg, byTier, boxes, cfg.era === "mapped" ? seededRandom((setInfo && setInfo.name) || "") : Math.random);
        boxes.forEach(function (box) {
            box.hits.filter(function (t, i) { return box.hits.indexOf(t) === i; })
                    .forEach(function (t) { seen[t] = (seen[t] || 0) + 1; });
        });
    }
    var add = function (t, p) { if (p > 0) hits.push({ tier: t, chance: Math.min(1, p) }); };
    Object.keys(seen).forEach(function (t) { add(t, seen[t] / (CASES * B)); });
    if (byTier.DON && byTier.DON_GOLD)
        add("DON_GOLD", cfg.goldDonPerBox ? 1 : 1 - Math.pow(1 - 1 / B, Math.round(cfg.fixed.DON_GOLD || 0)));
    hits.sort(function (x, y) { return info[y.tier].rank - info[x.tier].rank; });
    return {
        hits: hits,
        god: 1 - Math.exp(-((godBoost || 1) * godPacksPerCase(setInfo)) / B),
        packs: cfg.packsPerBox,
        srs: byTier.SR ? cfg.srPerBox : 0,
        leaders: byTier.L ? cfg.leadersPerBox : 0,
        topper: !!byTier.TOPPER
    };
}

// What one box holds on average: { tier: cards a box }, from the pack layout and
// the case budget (lottery hits at their mean). present: the tiers the set has
// ({ tier: true }); without it every tier the layout and budget name. God packs
// aren't in it. Progress.boxPrice prices a box from this.
function boxContents(cfg, present) {
    var has = function (t) { return present ? !!present[t] : true; };
    var P = cfg.packsPerBox, B = cfg.boxes, out = {}, hits = 0;
    var add = function (t, n) { if (n) out[t] = (out[t] || 0) + n; };
    HIT_TIERS.forEach(function (t) {
        if (!has(t)) return;
        var n = caseAmount(cfg, t) / B;
        add(t, n);
        hits += n;
    });
    var sr = has("SR") ? cfg.srPerBox : 0;
    add("SR", sr);
    cfg.slots.forEach(function (s) { if (s !== "HIT") add(s === "RARE" ? "R" : s, P); });
    var rest = Math.max(0, P - hits - sr);   // hit slots without a hit
    if (cfg.rPerBox !== undefined && has("UC")) {
        add("R", Math.min(rest, cfg.rPerBox));
        add("UC", Math.max(0, rest - cfg.rPerBox));
    } else {
        add("R", rest);
    }
    var leaders = has("L") ? cfg.leadersPerBox : 0;
    add("L", leaders);
    add("C", -leaders);
    if (has("DON")) {
        var dons = cfg.donPerBox || 0;
        var gold = !has("DON_GOLD") ? 0 : cfg.goldDonPerBox ? cfg.goldDonPerBox : (cfg.fixed.DON_GOLD || 0) / B;
        var sp = has("DON_SP") ? (cfg.lottery.DON_SP || cfg.fixed.DON_SP || 0) / B : 0;
        add("DON_GOLD", gold);
        add("DON_SP", sp);
        add("DON", Math.max(0, dons - gold - sp));
        if (!cfg.donFront) add("C", -dons);   // a DON!! takes a common's place
    }
    var panda = has("PANDA") ? (cfg.fixed.PANDA || 0) / B : 0;
    add("PANDA", panda);
    add("R", -panda);
    if (present && present.TOPPER) add("TOPPER", 1);
    Object.keys(out).forEach(function (t) { if (out[t] <= 0) delete out[t]; });
    return out;
}

// highest-ranked card in a pack
function best(pack) {
    return pack.reduce(function (a, c) { return tierOf(c).rank > tierOf(a).rank ? c : a; }, pack[0]);
}

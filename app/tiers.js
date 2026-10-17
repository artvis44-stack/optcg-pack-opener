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
// Extra boosters have no uncommons; premium boosters are 10-card packs with a
// foil reprint slot.
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
    premium: { // PRB: 10-card packs, 20 per box, 2 foil DON!! per box; rates unpublished
        packsPerBox: 20, boxes: 12,
        slots: ["C", "C", "C", "UC", "UC", "UC", "R", "FOIL", "RARE", "HIT"],
        srPerBox: 8, leadersPerBox: 0, donPerBox: 2, hitsPerBox: null,
        fixed:   { AA: 40, TEX: 12, SEC: 12, SEC_AA: 4, L_AA: 1, DON_GOLD: 4 },
        lottery: { SP: 2, MANGA: 1 }
    }
};

// The full config for a set: its family's defaults with the set's overrides
// (from sets.json) merged in.
function setConfig(setInfo) {
    var family = (setInfo && setInfo.family) || "main";
    var fam = FAMILIES[family];
    var cfg = {
        family: family,
        era: (setInfo && setInfo.era) || "random",
        packsPerBox: fam.packsPerBox, boxes: fam.boxes, slots: fam.slots,
        fixed: Object.assign({}, fam.fixed), lottery: Object.assign({}, fam.lottery)
    };
    ["srPerBox", "leadersPerBox", "donPerBox", "hitsPerBox"].forEach(function (k) {
        cfg[k] = setInfo && setInfo[k] !== undefined ? setInfo[k] : fam[k];
    });
    var over = (setInfo && setInfo.case) || {};
    Object.keys(over).forEach(function (t) {
        if (cfg.fixed[t] !== undefined || cfg.lottery[t] === undefined) cfg.fixed[t] = over[t];
        else cfg.lottery[t] = over[t];
    });
    cfg.packsPerCase = cfg.packsPerBox * cfg.boxes;
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
    var slots = cfg.slots.slice();
    var lastC = slots.lastIndexOf("C");
    if (spec.don) slots.splice(lastC--, 1);           // the DON!! takes a common's place...
    if (spec.leader) slots[lastC] = spec.leader;      // ...and a Leader replaces another
    slots.forEach(function (s) {
        add(s === "RARE" ? (spec.rare || "R") : s === "HIT" ? (spec.hit || "R") : s);
    });
    if (spec.don) add(spec.don);                      // ...at the very back
    return out;
}

// srScale / premiumScale: how much likelier a hit is in a pack that may hold
// one (dead Leader packs push the box's hits into the other packs)
function rollHit(byTier, cfg, srScale, premiumScale) {
    var r = Math.random();
    var acc = byTier.SR ? srScale * cfg.srPerBox / cfg.packsPerBox : 0;
    if (r < acc) return "SR";
    for (var i = 0; i < HIT_TIERS.length; i++) {
        if (!byTier[HIT_TIERS[i]]) continue;
        acc += premiumScale * caseAmount(cfg, HIT_TIERS[i]) / cfg.packsPerCase;
        if (r < acc) return HIT_TIERS[i];
    }
    return "R";
}

// A single pack with the case budget as odds.
// forceHit (testing / cheating): "L" forces a regular Leader, "PANDA" the
// Pandaman rare slot, "DON" / "DON_GOLD" / "DON_SP" the DON!! card,
// anything else the hit slot.
function makePack(cards, setInfo, forceHit) {
    var cfg = setConfig(setInfo);
    var byTier = group(cards);
    forceHit = forceHit && byTier[forceHit] ? forceHit : "";
    var special = ["L", "PANDA", "DON", "DON_GOLD", "DON_SP"];

    var leader = !!byTier.L && (forceHit === "L" || Math.random() < cfg.leadersPerBox / cfg.packsPerBox);
    var foils = ["DON_GOLD", "DON_SP"].filter(function (t) { return byTier[t]; });
    var foilRate = foils.reduce(function (a, t) { return a + caseAmount(cfg, t); }, 0) / cfg.packsPerCase;
    var r = Math.random();
    var don = forceHit.indexOf("DON") === 0 ? forceHit
            : !byTier.DON ? ""
            : r < foilRate ? pick(foils)
            : r < cfg.donPerBox / cfg.packsPerBox ? "DON" : "";

    // older eras: a Leader pack is a "dead pack"; OP-16 lets it keep an SR
    var live = byTier.L ? cfg.packsPerBox / (cfg.packsPerBox - cfg.leadersPerBox) : 1;
    var hit = forceHit && special.indexOf(forceHit) < 0 ? forceHit
            : leader && cfg.era === "mapped" ? "R"
            : leader && cfg.era === "transition" ? rollHit(byTier, cfg, 1, 0)
            : rollHit(byTier, cfg, cfg.era === "mapped" ? live : 1, cfg.era === "random" ? 1 : live);
    var panda = byTier.PANDA && Math.random() < caseAmount(cfg, "PANDA") / cfg.packsPerCase;
    return buildPack(byTier, cfg, {
        leader: leader ? "L" : "",
        don: don,
        rare: forceHit === "PANDA" || panda ? "PANDA" : "R",
        hit: hit
    });
}

// ---- cases ------------------------------------------------------------------------

// A whole case: { boxes: [boxes][packs][cards], toppers: [one card per box or null] }
function makeCase(cards, setInfo) {
    var cfg = setConfig(setInfo);
    var byTier = group(cards);
    var B = cfg.boxes, P = cfg.packsPerBox, b, i;
    // the "mapped" era places hits in a fixed pattern per set (same every case);
    // which card lands there is still random
    var place = cfg.era === "mapped" ? seededRandom((setInfo && setInfo.name) || "") : Math.random;
    var boxes = [];
    for (b = 0; b < B; b++) boxes.push({ hits: [], srs: [], leaders: [], dons: [], pandas: 0 });

    // premium hits
    var hits = [];
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
        for (i = 0; byTier.DON_GOLD && i < Math.round(cfg.fixed.DON_GOLD || 0); i++) foils.push("DON_GOLD");
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

    // box toppers (OP-01/02): one per box, outside the packs
    var toppers = boxes.map(function () { return byTier.TOPPER ? pick(byTier.TOPPER) : null; });
    return { boxes: dealt, toppers: toppers };
}

// highest-ranked card in a pack
function best(pack) {
    return pack.reduce(function (a, c) { return tierOf(c).rank > tierOf(a).rank ? c : a; }, pack[0]);
}

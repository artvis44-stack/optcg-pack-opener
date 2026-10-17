.pragma library
// Pull tiers, their look, and the pack / case generators.
//
// English OP-17: 12 cards per pack, 24 packs per box, 12 boxes per case.
// Bandai publishes no slot map or odds. Everything below is community data,
// mostly TCGTalk's OP-17 case openings (1,000+ packs), with onepiece.app for
// what that doesn't cover.
//
// Pack:
//   slots 1-7   Common            (a regular Leader replaces one)
//   slots 8-10  Uncommon
//   slot 11     Rare              (or a Pandaman variant)
//   slot 12     hit slot          Rare unless it holds an SR or premium hit. A
//                                 Leader here is only ever a parallel.
//   DON!!       replaces a common and sits at the very back, after the hit.
//
// Box/case: OP-17 dropped fixed hit mapping -- premium hits land randomly,
// 1-4 per box -- but a case still holds a roughly fixed budget of each hit,
// so hits trade off between the boxes of a case. makeCase() deals a case
// from that budget; makePack() uses the same budget as per-pack odds.

var info = {
    C:       { label: "Common",                 holo: 0.0,  gold: 0.0, rank: 0,  color: "#9aa4b2" },
    UC:      { label: "Uncommon",               holo: 0.0,  gold: 0.0, rank: 1,  color: "#7fd1b9" },
    DON:     { label: "DON!! Card",             holo: 0.25, gold: 0.0, rank: 1,  color: "#e6e6e6" },
    R:       { label: "Rare",                   holo: 0.35, gold: 0.0, rank: 2,  color: "#5fa8ff" },
    L:       { label: "Leader",                 holo: 0.0,  gold: 0.0, rank: 3,  color: "#ff5a5a" },
    SR:      { label: "Super Rare",             holo: 0.75, gold: 0.0, rank: 4,  color: "#c07bff" },
    PANDA:   { label: "Pandaman Art",           holo: 0.6,  gold: 0.3, rank: 5,  color: "#ffe9a8" },
    AA:      { label: "Alternate Art",          holo: 1.0,  gold: 0.0, rank: 6,  color: "#ff7bd5" },
    SEC:     { label: "Secret Rare",            holo: 1.0,  gold: 0.4, rank: 7,  color: "#ffd34d" },
    L_AA:    { label: "Alternate Art Leader",   holo: 1.0,  gold: 0.2, rank: 8,  color: "#ff6b6b" },
    SP:      { label: "Special Card",           holo: 1.0,  gold: 0.6, rank: 9,  color: "#ffb347" },
    DON_GOLD:{ label: "Gold DON!!",             holo: 1.0,  gold: 1.0, rank: 9,  color: "#ffd700" },
    DON_SP:  { label: "Special Foil DON!!",     holo: 1.0,  gold: 0.0, rank: 9,  color: "#9be7ff" },
    SEC_AA:  { label: "Secret Rare Alt Art",    holo: 1.0,  gold: 0.5, rank: 10, color: "#ffd34d" },
    SUPER_L: { label: "Super Leader Parallel",  holo: 1.0,  gold: 0.7, rank: 11, color: "#ffd700" },
    TR:      { label: "Treasure Rare",          holo: 1.0,  gold: 1.0, rank: 12, color: "#ffe08a" },
    MANGA:   { label: "Manga Rare",             holo: 1.0,  gold: 0.2, rank: 13, color: "#ffffff" },
    SUPER:   { label: "Super Alternate Art",    holo: 1.0,  gold: 0.8, rank: 14, color: "#ffd700" }
};

// What one case holds.
var CASE = {
    boxes: 12,
    packsPerBox: 24,
    srCopies: 8,         // each SR name ~7-8 times per case -> ~6.7 SR per box
    leadersPerBox: 5,
    donPerBox: 2,
    hitsPerBox: [1, 4],  // premium hits per box
    // always about this many per case ("reliable")
    fixed:   { AA: 10, SEC: 5, L_AA: 4, SEC_AA: 2, PANDA: 7, DON_GOLD: 1 },
    // lottery: Poisson mean per case. Sources disagree on the super parallels
    // (1 in 6 vs 1 in 96 boxes for the Super Leader; 0.04-0.3 per case for the
    // Pirates Crew) -- these sit between them.
    lottery: { SP: 2, DON_SP: 1, TR: 0.75, SUPER_L: 0.5, MANGA: 0.4, SUPER: 0.15 }
};

// premium tiers that take the hit slot
var HIT_TIERS = ["AA", "SEC", "L_AA", "SEC_AA", "SP", "TR", "SUPER_L", "MANGA", "SUPER"];

function caseAmount(tier) {
    return CASE.fixed[tier] !== undefined ? CASE.fixed[tier] : CASE.lottery[tier];
}

// the same budget as per-pack odds
var PACKS_PER_CASE = CASE.boxes * CASE.packsPerBox;
var LEADER_RATE = CASE.leadersPerBox / CASE.packsPerBox;
var PANDA_RATE = CASE.fixed.PANDA / PACKS_PER_CASE;
var DON_RATE = CASE.donPerBox / CASE.packsPerBox;                        // any DON!!
var DON_FOIL_RATE = (CASE.fixed.DON_GOLD + CASE.lottery.DON_SP) / PACKS_PER_CASE;
var hitWeights = HIT_TIERS.map(function (t) { return [t, caseAmount(t) / PACKS_PER_CASE]; });

function tierOf(card) {
    return card && info[card.tier] || info.C;   // card is briefly null while delegates tear down
}

// "Kaido (062) (Super Alternate Art)" -> "Kaido (062)"; the tier label says the rest
function displayName(card) {
    return card.name.replace(/\s*\((Alternate Art|Manga|SP|TR|Super .*Alternate Art|Pandaman Art|Gold|Special Foil)\)/g, "");
}

function pick(list) {
    return list[Math.floor(Math.random() * list.length)];
}

function shuffle(list) {
    for (var i = list.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1));
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

// n distinct pack indices out of `count`
function packSlots(count, n) {
    var idx = [];
    for (var i = 0; i < count; i++) idx.push(i);
    return shuffle(idx).slice(0, n);
}

// Builds one pack. Each slot in spec is a tier name (a random card of that
// tier) or a card object; leader/don may be empty.
function buildPack(byTier, spec) {
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
    var commons = spec.don ? 6 : 7;
    for (var i = 0; i < commons; i++) add(spec.leader && i === commons - 1 ? spec.leader : "C");
    for (i = 0; i < 3; i++) add("UC");
    add(spec.rare || "R");
    add(spec.hit || "R");
    if (spec.don) add(spec.don);
    return out;
}

function rollHit(byTier) {
    var r = Math.random();
    var acc = CASE.srCopies * (byTier.SR || []).length / PACKS_PER_CASE;
    if (r < acc) return "SR";
    for (var i = 0; i < hitWeights.length; i++) {
        acc += hitWeights[i][1];
        if (r < acc) return hitWeights[i][0];
    }
    return "R";
}

// A single pack with the case budget as odds.
// forceHit (testing / cheating): "L" forces a regular Leader, "PANDA" the
// Pandaman rare slot, "DON" / "DON_GOLD" / "DON_SP" the DON!! card,
// anything else the hit slot.
function makePack(cards, forceHit) {
    var byTier = group(cards);
    forceHit = forceHit && byTier[forceHit] ? forceHit : "";
    var special = ["L", "PANDA", "DON", "DON_GOLD", "DON_SP"];
    var r = Math.random();
    return buildPack(byTier, {
        leader: forceHit === "L" || Math.random() < LEADER_RATE ? "L" : "",
        don: forceHit.indexOf("DON") === 0 ? forceHit
             : r < DON_FOIL_RATE ? (Math.random() < 0.5 ? "DON_GOLD" : "DON_SP")
             : r < DON_RATE ? "DON" : "",
        rare: forceHit === "PANDA" || Math.random() < PANDA_RATE ? "PANDA" : "R",
        hit: forceHit && special.indexOf(forceHit) < 0 ? forceHit : rollHit(byTier)
    });
}

// A whole case: 12 boxes x 24 packs, dealt from the case budget.
function makeCase(cards) {
    var byTier = group(cards);
    var B = CASE.boxes, P = CASE.packsPerBox, b, i;
    var boxes = [];
    for (b = 0; b < B; b++) boxes.push({ hits: [], srs: [], leaders: [], dons: [], pandas: 0 });

    // premium hits: random boxes, then nudged into 1-4 per box
    var hits = [];
    HIT_TIERS.forEach(function (t) {
        if (!byTier[t]) return;
        var n = CASE.fixed[t] !== undefined ? CASE.fixed[t] : poisson(CASE.lottery[t]);
        for (var k = 0; k < n; k++) hits.push(t);
    });
    shuffle(hits).forEach(function (t) { boxes[Math.floor(Math.random() * B)].hits.push(t); });
    var lo = CASE.hitsPerBox[0], hi = CASE.hitsPerBox[1];
    for (var guard = 0; guard < 200; guard++) {
        var sorted = boxes.slice().sort(function (x, y) { return x.hits.length - y.hits.length; });
        var fewest = sorted[0], most = sorted[B - 1];
        if (most.hits.length > hi || (fewest.hits.length < lo && most.hits.length > lo))
            fewest.hits.push(most.hits.splice(Math.floor(Math.random() * most.hits.length), 1)[0]);
        else
            break;
    }

    // SRs: srCopies of each, dealt round-robin (6-7 per box), box order shuffled
    var srs = [];
    (byTier.SR || []).forEach(function (c) { for (var k = 0; k < CASE.srCopies; k++) srs.push(c); });
    var order = shuffle(boxes.slice());
    shuffle(srs).forEach(function (c, k) { order[k % B].srs.push(c); });

    // Leaders: an even pool of each Leader, leadersPerBox per box
    var leaders = [];
    var lcards = byTier.L || [];
    for (i = 0; lcards.length && i < B * CASE.leadersPerBox; i++) leaders.push(lcards[i % lcards.length]);
    shuffle(leaders);
    boxes.forEach(function (box, k) { box.leaders = leaders.slice(k * CASE.leadersPerBox, (k + 1) * CASE.leadersPerBox); });

    // DON!!: donPerBox each; the gold / special foil ones replace a regular one
    boxes.forEach(function (box) { for (var k = 0; k < CASE.donPerBox; k++) box.dons.push("DON"); });
    var foils = [];
    for (i = 0; i < CASE.fixed.DON_GOLD; i++) foils.push("DON_GOLD");
    for (i = poisson(CASE.lottery.DON_SP); i > 0; i--) foils.push("DON_SP");
    foils.forEach(function (t) {
        if (!byTier[t]) return;
        var box = pick(boxes.filter(function (x) { return x.dons.indexOf("DON") >= 0; }));
        if (box) box.dons[box.dons.indexOf("DON")] = t;
    });

    // Pandaman: random boxes, at most 2 in one box
    for (i = 0; byTier.PANDA && i < CASE.fixed.PANDA; i++)
        pick(boxes.filter(function (x) { return x.pandas < 2; })).pandas++;

    // deal each box's contents into distinct packs
    return boxes.map(function (box) {
        var specs = [];
        for (var p = 0; p < P; p++) specs.push({ leader: "", don: "", rare: "R", hit: "R" });
        var hitCards = box.srs.concat(box.hits);
        packSlots(P, hitCards.length).forEach(function (p, k) { specs[p].hit = hitCards[k]; });
        packSlots(P, box.leaders.length).forEach(function (p, k) { specs[p].leader = box.leaders[k]; });
        packSlots(P, box.dons.length).forEach(function (p, k) { specs[p].don = box.dons[k]; });
        packSlots(P, box.pandas).forEach(function (p) { specs[p].rare = "PANDA"; });
        return specs.map(function (spec) { return buildPack(byTier, spec); });
    });
}

// highest-ranked card in a pack
function best(pack) {
    return pack.reduce(function (a, c) { return tierOf(c).rank > tierOf(a).rank ? c : a; }, pack[0]);
}

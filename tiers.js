.pragma library
// Pull tiers, their look, and the pack generator.
//
// English OP-17 booster: 12 cards. Bandai publishes no slot map or odds;
// the rates below are community estimates (TCGTalk's 1,000+ pack OP-17
// aggregate, retailer box guides), converted to per-pack odds at
// 24 packs/box and 12 boxes/case.
//
//   slots 1-7   Common            (a regular Leader replaces one ~1 in 4 packs)
//   slots 8-10  Uncommon
//   slot 11     Rare              (Pandaman variant takes this slot ~7/case)
//   slot 12     hit slot          Rare unless upgraded (table below). A Leader
//                                 here is only ever a parallel, never a plain L.

var info = {
    C:       { label: "Common",                 holo: 0.0,  gold: 0.0, rank: 0,  color: "#9aa4b2" },
    UC:      { label: "Uncommon",               holo: 0.0,  gold: 0.0, rank: 1,  color: "#7fd1b9" },
    R:       { label: "Rare",                   holo: 0.35, gold: 0.0, rank: 2,  color: "#5fa8ff" },
    L:       { label: "Leader",                 holo: 0.0,  gold: 0.0, rank: 3,  color: "#ff5a5a" },
    SR:      { label: "Super Rare",             holo: 0.75, gold: 0.0, rank: 4,  color: "#c07bff" },
    PANDA:   { label: "Pandaman Art",           holo: 0.6,  gold: 0.3, rank: 5,  color: "#ffe9a8" },
    AA:      { label: "Alternate Art",          holo: 1.0,  gold: 0.0, rank: 6,  color: "#ff7bd5" },
    SEC:     { label: "Secret Rare",            holo: 1.0,  gold: 0.4, rank: 7,  color: "#ffd34d" },
    L_AA:    { label: "Alternate Art Leader",   holo: 1.0,  gold: 0.2, rank: 8,  color: "#ff6b6b" },
    SP:      { label: "Special Card",           holo: 1.0,  gold: 0.6, rank: 9,  color: "#ffb347" },
    SEC_AA:  { label: "Secret Rare Alt Art",    holo: 1.0,  gold: 0.5, rank: 10, color: "#ffd34d" },
    SUPER_L: { label: "Super Leader Parallel",  holo: 1.0,  gold: 0.7, rank: 11, color: "#ffd700" },
    TR:      { label: "Treasure Rare",          holo: 1.0,  gold: 1.0, rank: 12, color: "#ffe08a" },
    MANGA:   { label: "Manga Rare",             holo: 1.0,  gold: 0.2, rank: 13, color: "#ffffff" },
    SUPER:   { label: "Super Alternate Art",    holo: 1.0,  gold: 0.8, rank: 14, color: "#ffd700" }
};

var LEADER_RATE = 0.2;    // 4-6 regular Leaders per box
var PANDA_RATE = 0.024;   // ~6-8 per case

// Hit-slot upgrades, per pack. Whatever is left over stays a Rare.
var hitWeights = [
    ["SR",      0.29],     // ~7 per box
    ["AA",      0.075],    // ~2 alt-art characters per box
    ["SEC",     0.017],    // ~1 per 2-3 boxes
    ["L_AA",    0.014],    // ~1 per 3 boxes (~4 per case)
    ["SUPER_L", 0.007],    // ~1 per 6 boxes
    ["SP",      0.007],    // ~2 per case
    ["TR",      0.0035],   // ~1 per case
    ["SEC_AA",  0.003],
    ["MANGA",   0.0005],   // ~1 per 65-100 boxes
    ["SUPER",   0.0001]    // Pirate Crew super parallel, ~1 per 338 boxes
];

function tierOf(card) {
    return info[card.tier] || info.C;
}

// "Kaido (062) (Super Alternate Art)" -> "Kaido (062)"; the tier label says the rest
function displayName(card) {
    return card.name.replace(/\s*\((Alternate Art|Manga|SP|TR|Super .*Alternate Art|Pandaman Art)\)/g, "");
}

function rollHit() {
    var r = Math.random(), acc = 0;
    for (var i = 0; i < hitWeights.length; i++) {
        acc += hitWeights[i][1];
        if (r < acc) return hitWeights[i][0];
    }
    return "R";
}

// forceHit (testing / cheating): "L" forces a regular Leader, "PANDA" the
// Pandaman rare slot, anything else the hit slot.
function makePack(cards, forceHit) {
    var byTier = {};
    cards.forEach(function (c) { (byTier[c.tier] = byTier[c.tier] || []).push(c); });
    if (forceHit && !byTier[forceHit]) forceHit = "";

    var out = [], used = {};
    function add(tier) {
        if (!byTier[tier]) tier = "R";
        var pool = byTier[tier].filter(function (c) { return !used[c.image]; });
        if (!pool.length) pool = byTier[tier];
        var c = pool[Math.floor(Math.random() * pool.length)];
        used[c.image] = true;
        out.push(c);
    }

    var leader = forceHit === "L" || Math.random() < LEADER_RATE;
    for (var i = 0; i < 7; i++) add(leader && i === 6 ? "L" : "C");
    for (i = 0; i < 3; i++) add("UC");
    add(forceHit === "PANDA" || Math.random() < PANDA_RATE ? "PANDA" : "R");
    add(forceHit && forceHit !== "L" && forceHit !== "PANDA" ? forceHit : rollHit());
    return out;
}

// highest-ranked card in a pack
function best(pack) {
    return pack.reduce(function (a, c) { return tierOf(c).rank > tierOf(a).rank ? c : a; }, pack[0]);
}

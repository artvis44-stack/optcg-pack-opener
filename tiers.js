.pragma library
// Pull tiers, their look, and the pack generator.
// Rates are approximate fan estimates for a 12-card English booster, not
// official odds.

var info = {
    C:      { label: "Common",              holo: 0.0,  gold: 0.0, rank: 0,  color: "#9aa4b2" },
    UC:     { label: "Uncommon",            holo: 0.0,  gold: 0.0, rank: 1,  color: "#7fd1b9" },
    R:      { label: "Rare",                holo: 0.35, gold: 0.0, rank: 2,  color: "#5fa8ff" },
    L:      { label: "Leader",              holo: 0.6,  gold: 0.0, rank: 3,  color: "#ff5a5a" },
    SR:     { label: "Super Rare",          holo: 0.75, gold: 0.0, rank: 4,  color: "#c07bff" },
    PANDA:  { label: "Pandaman Art",        holo: 0.6,  gold: 0.3, rank: 4,  color: "#ffe9a8" },
    AA:     { label: "Alternate Art",       holo: 1.0,  gold: 0.0, rank: 5,  color: "#ff7bd5" },
    SEC:    { label: "Secret Rare",         holo: 1.0,  gold: 0.4, rank: 6,  color: "#ffd34d" },
    SP:     { label: "Special Card",        holo: 1.0,  gold: 0.6, rank: 7,  color: "#ffb347" },
    TR:     { label: "Treasure Rare",       holo: 1.0,  gold: 1.0, rank: 8,  color: "#ffe08a" },
    SEC_AA: { label: "Secret Rare Alt Art", holo: 1.0,  gold: 0.5, rank: 9,  color: "#ffd34d" },
    MANGA:  { label: "Manga Rare",          holo: 1.0,  gold: 0.2, rank: 10, color: "#ffffff" },
    SUPER:  { label: "Super Alternate Art", holo: 1.0,  gold: 0.8, rank: 11, color: "#ffd700" }
};

// What the last ("hit") slot can be. The leftover probability falls to R.
var hitWeights = [
    ["SR", 0.22], ["L", 0.08], ["PANDA", 0.01], ["AA", 0.10], ["SEC", 0.03], ["SP", 0.02],
    ["SEC_AA", 0.008], ["TR", 0.008], ["MANGA", 0.004], ["SUPER", 0.002]
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

// 7 C, 3 UC, 1 R, 1 hit slot -- weakest first so the hit is revealed last.
// forceHit: optional tier for the last slot (testing / cheating)
function makePack(cards, forceHit) {
    var byTier = {};
    cards.forEach(function (c) { (byTier[c.tier] = byTier[c.tier] || []).push(c); });

    var out = [], used = {};
    function add(tier) {
        var pool = (byTier[tier] || byTier.R || cards).filter(function (c) { return !used[c.image]; });
        if (!pool.length) pool = byTier[tier] || cards;
        var c = pool[Math.floor(Math.random() * pool.length)];
        used[c.image] = true;
        out.push(c);
    }

    var i;
    for (i = 0; i < 7; i++) add("C");
    for (i = 0; i < 3; i++) add("UC");
    add("R");
    add(forceHit && info[forceHit] ? forceHit : rollHit());
    return out;
}

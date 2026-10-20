.pragma library
.import "tiers.js" as Tiers

// Collections: sets of graded cards to complete and save in a display case
// (the vault's Sets tab). Each is a list of slots; a slot takes a slab of any
// of its cards (a card's English and Japanese printings share an id, so either
// fills it). Built from the downloaded sets' cards.json, so a collection grows
// with what you've downloaded. Kinds:
//   set    each set's chase lists: its SPs, Manga Rares, Alt Art Leaders,
//          Secret Rares, and the master set (every card)
//   theme  crews and rarities across sets: Straw Hats, Four Emperors, Admirals
//          (an alt art or better of each), Wanted Posters, Treasure Rares,
//          Gold & Silver SPs
//   char   a character's master set: every chase version of them
//   long   every Manga Rare there is
//   show   the card show's vintage cards and promos (Progress.SHOW_SETS): the
//          2005-06 Gold Rares, Silver Rares and promos, a vintage Straw Hat crew,
//          every P-001 Luffy, and the vintage master set; each Carddass Hyper Battle
//          set, its holos, gold stamps and promos, and every Hyper Battle Luffy

var KINDS = [["set", "Per set"], ["theme", "Themes"], ["char", "Characters"], ["long", "Long hauls"], ["show", "Vintage & promos"]];

// alt art and up: the versions a crew or character set asks for
var CHASE = Tiers.HIT_TIERS;

var PER_SET = [
    ["sp",     "SPs",             ["SP", "SP_GOLD"]],
    ["manga",  "Manga Rares",     ["MANGA", "SIGNED"]],
    ["laa",    "Alt Art Leaders", ["L_AA", "SUPER_L"]],
    ["sec",    "Secret Rares",    ["SEC", "SEC_AA"]],
    ["master", "Master Set",      null]
];

// [id, title, text, [[slot label, character names]...]]
var CREWS = [
    ["strawhats", "The Straw Hat Crew", "An alt art or better of every Straw Hat", [
        ["Luffy", ["Monkey.D.Luffy"]], ["Zoro", ["Roronoa Zoro"]], ["Nami", ["Nami"]], ["Usopp", ["Usopp"]],
        ["Sanji", ["Sanji"]], ["Chopper", ["Tony Tony.Chopper"]], ["Robin", ["Nico Robin"]],
        ["Franky", ["Franky"]], ["Brook", ["Brook"]], ["Jinbe", ["Jinbe"]]]],
    ["emperors", "The Four Emperors", "An alt art or better of Shanks, Kaido, Big Mom and Whitebeard", [
        ["Shanks", ["Shanks"]], ["Kaido", ["Kaido"]], ["Big Mom", ["Charlotte Linlin"]], ["Whitebeard", ["Edward.Newgate"]]]],
    ["admirals", "The Admirals", "An alt art or better of each Admiral", [
        ["Akainu", ["Sakazuki"]], ["Aokiji", ["Kuzan"]], ["Kizaru", ["Borsalino"]],
        ["Fujitora", ["Issho"]], ["Ryokugyu", ["Aramaki"]]]]
];

// [id, title, text, test(card)]
var RARITIES = [
    ["wanted", "Wanted Posters", "Every Wanted Poster SP", function (c) { return c.name.indexOf("(Wanted Poster)") >= 0; }],
    ["tr",     "Treasure Rares", "Every Treasure Rare",    function (c) { return c.tier === "TR"; }],
    ["gold",   "Gold & Silver SPs", "Every Gold and Silver SP", function (c) { return c.tier === "SP_GOLD"; }]
];

// the card show's lists: [id, title, text, style, set, test(card)]
var SHOW_LISTS = [
    ["qbgold",  "The Quest Begins Gold Rares", "The first English set's three Gold Rares (2005)", "vintage", "VINTAGE",
     function (c) { return c.tier === "V_GOLD" && c.origin === "The Quest Begins"; }],
    ["pglgold", "Grand Line Gold Rares", "Passage to the Grand Line's Gold Rares (2006)", "vintage", "VINTAGE",
     function (c) { return c.tier === "V_GOLD" && c.origin === "Passage to the Grand Line"; }],
    ["silver",  "Silver Rares", "Passage to the Grand Line's Silver Rares (2006)", "vintage", "VINTAGE", function (c) { return c.tier === "V_SILVER"; }],
    ["vpromo",  "The 2005 Promos", "Every vintage promo: tournament prizes and stamped cards", "vintage", "VINTAGE",
     function (c) { return c.tier === "V_PROMO"; }],
    ["p001",    "Every P-001 Luffy", "Each printing of the first promo", "promo", "PROMO",
     function (c) { return /^P-001(_|$)/.test(c.id); }],
    ["hbholo",  "Hyper Battle Holos", "Every holo of Carddass Hyper Battle (1999-2002)", "vintage", "HYPERBATTLE",
     function (c) { return c.rarity === "holo" || c.rarity === "secret"; }],
    ["hbgold",  "Hyper Battle Gold Stamps", "The gold-stamped card of every Grand Box deck", "vintage", "HYPERBATTLE",
     function (c) { return c.rarity === "gold"; }],
    ["hbpromo", "Hyper Battle Promos", "The event and tournament promos, 2000-2002", "vintage", "HYPERBATTLE",
     function (c) { return c.rarity === "promo"; }],
    ["hbluffy", "Every Hyper Battle Luffy", "Every card of Luffy, 1999-2002", "char", "HYPERBATTLE",
     function (c) { return c.name === "Luffy"; }]
];
// each Hyper Battle set (a Stage, a Grand Box, a Compilation): every card of it
// the vintage crew: one card of each, any rarity ([slot, the names the 2005 cards use: 4Kids' English])
var VINTAGE_CREW = [["Luffy", ["Luffy"]], ["Zoro", ["Roronoa Zolo", "Zoro"]], ["Nami", ["Nami the Navigator", "Nami"]],
                    ["Usopp", ["Usopp"]], ["Sanji", ["Sanji"]], ["Chopper", ["Chopper"]], ["Robin", ["Ms. Sunday (Nico Robin)", "Robin"]]];

// [id, short name, card name]
var CHARACTERS = [
    ["luffy", "Luffy", "Monkey.D.Luffy"], ["zoro", "Zoro", "Roronoa Zoro"], ["nami", "Nami", "Nami"],
    ["sanji", "Sanji", "Sanji"], ["robin", "Robin", "Nico Robin"], ["shanks", "Shanks", "Shanks"],
    ["ace", "Ace", "Portgas.D.Ace"], ["law", "Law", "Trafalgar Law"], ["yamato", "Yamato", "Yamato"],
    ["hancock", "Boa Hancock", "Boa Hancock"]
];

// "Monkey.D.Luffy - OP09-119 (Manga)" -> "Monkey.D.Luffy"
function baseName(name) {
    return String(name || "").replace(/\s*\([^)]*\)/g, "").replace(/\s+-\s+[A-Z0-9]+-\d+$/, "").trim();
}

function cardKey(set, c) {
    return set + ":" + String(c.image || "").split("/").pop();
}

function rank(c) {
    return Tiers.tierOf(c).rank;
}

// cardsBySet: { set: [cards] } for the downloaded sets; sets: sets.json (release order)
function build(cardsBySet, sets) {
    var order = Object.keys(sets).filter(function (s) { return cardsBySet[s]; });
    var english = function (s) { return (sets[s] || {}).lang !== "jp"; };
    // every printing by card id: its copies in every set; an English one shows for it
    var byId = {}, ids = [];
    order.forEach(function (s) {
        if ((sets[s] || {}).show) return;   // a promo can share its card's id, but it's not that card
        cardsBySet[s].forEach(function (c) {
            var e = byId[c.id];
            if (!e) {
                e = byId[c.id] = { card: c, set: s, keys: [] };
                ids.push(c.id);
            } else if (english(s) && !english(e.set)) {
                e.card = c;
                e.set = s;
            }
            var k = cardKey(s, c);
            if (e.keys.indexOf(k) < 0) e.keys.push(k);
        });
    });
    var slotOf = function (e) {
        return { label: Tiers.displayName(e.card), keys: e.keys, card: e.card, set: e.set };
    };
    var bestFirst = function (a, b) { return rank(b.card) - rank(a.card) || (a.card.id < b.card.id ? -1 : 1); };
    var out = [];

    order.forEach(function (s) {
        var info = sets[s] || {};
        if (info.show && s !== "VINTAGE") return;   // the promos: a thousand cards, no master set
        PER_SET.forEach(function (l) {
            var seen = {}, slots = [];
            cardsBySet[s].forEach(function (c) {
                if (l[2] ? l[2].indexOf(c.tier) < 0 : c.tier.indexOf("DON") === 0) return;
                var k = cardKey(s, c);
                if (seen[k]) return;
                seen[k] = true;
                slots.push({ label: Tiers.displayName(c), keys: [k], card: c, set: s });
            });
            if (slots.length < 2) return;
            out.push({ id: "set:" + s + ":" + l[0], kind: "set", style: l[0], set: s,
                       title: s + " " + l[1], text: info.name || "", slots: slots.sort(bestFirst) });
        });
    });

    CREWS.forEach(function (t) {
        var slots = t[3].map(function (m) {
            var es = ids.map(function (id) { return byId[id]; })
                        .filter(function (e) { return m[1].indexOf(baseName(e.card.name)) >= 0 && CHASE.indexOf(e.card.tier) >= 0; })
                        .sort(bestFirst);
            if (!es.length) return null;
            return { label: m[0], keys: es.reduce(function (a, e) { return a.concat(e.keys); }, []), card: es[0].card, set: es[0].set,
                     any: true };
        });
        if (slots.some(function (x) { return !x; })) return;   // someone with no alt art downloaded yet
        out.push({ id: "theme:" + t[0], kind: "theme", style: t[0], title: t[1], text: t[2], slots: slots });
    });
    RARITIES.forEach(function (t) {
        var slots = ids.map(function (id) { return byId[id]; }).filter(function (e) { return t[3](e.card); })
                       .sort(bestFirst).map(slotOf);
        if (slots.length >= 2)
            out.push({ id: "theme:" + t[0], kind: "theme", style: t[0], title: t[1], text: t[2], slots: slots });
    });

    CHARACTERS.forEach(function (ch) {
        var slots = ids.map(function (id) { return byId[id]; })
                       .filter(function (e) { return baseName(e.card.name) === ch[2] && CHASE.indexOf(e.card.tier) >= 0; })
                       .sort(bestFirst).map(slotOf);
        if (slots.length >= 2)
            out.push({ id: "char:" + ch[0], kind: "char", style: "char", title: ch[1] + " Master Set",
                       text: "Every chase version of " + ch[2], slots: slots });
    });

    SHOW_LISTS.forEach(function (l) {
        var seen = {}, slots = [];
        (cardsBySet[l[4]] || []).forEach(function (c) {
            var k = cardKey(l[4], c);
            if (seen[k] || !l[5](c)) return;
            seen[k] = true;
            slots.push({ label: Tiers.displayName(c), keys: [k], card: c, set: l[4] });
        });
        if (slots.length >= 2)
            out.push({ id: "show:" + l[0], kind: "show", style: l[3], title: l[1], text: l[2], slots: slots.sort(bestFirst) });
    });
    var hbSets = [];
    (cardsBySet.HYPERBATTLE || []).forEach(function (c) { if (c.origin && c.origin !== "Promotionals" && hbSets.indexOf(c.origin) < 0) hbSets.push(c.origin); });
    hbSets.forEach(function (name) {
        var slots = (cardsBySet.HYPERBATTLE || []).filter(function (c) { return c.origin === name; })
            .map(function (c) { return { label: c.id + " " + c.name, keys: [cardKey("HYPERBATTLE", c)], card: c, set: "HYPERBATTLE" }; });
        if (slots.length >= 2)
            out.push({ id: "show:hb:" + name, kind: "show", style: "vintage", title: "Hyper Battle " + name,
                       text: "Every card of " + name + " (Carddass Hyper Battle)", slots: slots });
    });
    var crew = VINTAGE_CREW.map(function (who) {
        var cs = (cardsBySet.VINTAGE || []).filter(function (c) { return who[1].indexOf(c.character) >= 0; })
                                           .sort(function (a, b) { return rank(b) - rank(a); });
        if (!cs.length) return null;
        return { label: who[0], keys: cs.map(function (c) { return cardKey("VINTAGE", c); }), card: cs[0], set: "VINTAGE", any: true };
    });
    if (crew.every(function (x) { return x; }))
        out.push({ id: "show:crew", kind: "show", style: "vintage", title: "Vintage Straw Hats",
                   text: "A 2005-06 card of each Straw Hat, any rarity", slots: crew });

    var manga = ids.map(function (id) { return byId[id]; }).filter(function (e) { return e.card.tier === "MANGA"; })
                   .sort(bestFirst).map(slotOf);
    if (manga.length >= 2)
        out.push({ id: "long:manga", kind: "long", style: "manga", title: "Every Manga Rare",
                   text: "One of each Manga Rare there is", slots: manga });
    return out;
}

// Fill a collection's slots from your slabs. free: { card key: [slab, ...] }
// (the slabs not in a display case, best first). Each slot takes the best slab
// of any of its cards, a slab only once. -> { slabs: [slab or null], filled, total, complete }
function fill(def, free) {
    var used = {}, filled = 0;
    var slabs = def.slots.map(function (slot) {
        var best = null;
        slot.keys.forEach(function (k) {
            (free[k] || []).forEach(function (s) {
                if (used[s.slabId]) return;
                if (!best || gradeOf(s) > gradeOf(best)) best = s;
            });
        });
        if (best) {
            used[best.slabId] = true;
            filled++;
        }
        return best;
    });
    return { slabs: slabs, filled: filled, total: def.slots.length, complete: filled === def.slots.length };
}

// a Diamond Label counts as a 10, a hair better
function gradeOf(s) {
    return s.grade + (s.diamond ? 0.5 : 0);
}

// a saved set's rating: the average grade, and whether every slab is a 10
function rating(slabs) {
    var got = slabs.filter(function (s) { return s; });
    if (!got.length) return { avg: 0, gem: false };
    var sum = got.reduce(function (n, s) { return n + Math.min(10, s.grade); }, 0);
    return { avg: sum / got.length, gem: got.every(function (s) { return s.grade >= 10; }) };
}

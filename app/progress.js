.pragma library
// Progression: berries (฿), free packs, the daily streak, passive income,
// focus sessions, daily bounties and wanted-poster achievements.
//
// State lives in progress.json (separate per computer). The pack opener and
// the desktop companion both change it, always as read-modify-write through
// update(), so neither overwrites the other's changes.
//
// Every change that earns something goes through record(), which updates the
// stats, advances the daily bounties and unlocks achievements; it returns what
// was newly completed so the caller can celebrate it.

// ---- the economy -----------------------------------------------------------------

var PACK_PRICE = { main: 500, extra: 500, premium: 800 };   // ฿ (an English pack is ~$5)
var BOX_DISCOUNT = 0.95;
var CASE_DISCOUNT = 0.85;          // on the boxes left in the case
var USD_TO_BERRY = 100;            // selling: $1 market value = 100 ฿
var INCOME_PER_MINUTE = 4;         // while you're at the computer
var INCOME_DAILY_CAP = 2000;
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
    SUPER: 100000
};

function packPrice(family) {
    return PACK_PRICE[family] || PACK_PRICE.main;
}

function boxPrice(family, packsPerBox) {
    return Math.round(packPrice(family) * packsPerBox * BOX_DISCOUNT / 100) * 100;
}

function casePrice(family, packsPerBox, boxesLeft) {
    return Math.round(boxPrice(family, packsPerBox) * boxesLeft * CASE_DISCOUNT / 100) * 100;
}

function format(n) {
    return "฿" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatBounty(n) {
    if (n >= 1e9) return "฿" + (n / 1e9).toFixed(n % 1e9 ? 2 : 0) + "B";
    if (n >= 1e6) return "฿" + (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + "M";
    return format(n);
}

// ---- achievements: wanted posters ---------------------------------------------

function pulled(p, tiers) {
    return tiers.reduce(function (a, t) { return a + (p.stats.pulled[t] || 0); }, 0);
}

var ACHIEVEMENTS = [
    { id: "pack1",    title: "Set Sail",             text: "Open your first pack",               bounty: 1e6,   reward: 500,   test: function (p) { return p.stats.packs >= 1; } },
    { id: "leader",   title: "Captain",              text: "Pull a Leader",                      bounty: 3e6,   reward: 300,   test: function (p) { return pulled(p, ["L"]) >= 1; } },
    { id: "sr",       title: "Super Rookie",         text: "Pull a Super Rare",                  bounty: 5e6,   reward: 500,   test: function (p) { return pulled(p, ["SR"]) >= 1; } },
    { id: "pack10",   title: "Rookie",               text: "Open 10 packs",                      bounty: 8e6,   reward: 800,   test: function (p) { return p.stats.packs >= 10; } },
    { id: "box1",     title: "Box Breaker",          text: "Open a whole booster box",           bounty: 1e7,   reward: 1500,  test: function (p) { return p.stats.boxes >= 1; } },
    { id: "aa",       title: "Alternate Reality",    text: "Pull an Alternate Art",              bounty: 2e7,   reward: 2000,  test: function (p) { return pulled(p, ["AA", "TEX"]) >= 1; } },
    { id: "sec",      title: "Secret Keeper",        text: "Pull a Secret Rare",                 bounty: 3e7,   reward: 3000,  test: function (p) { return pulled(p, ["SEC", "SEC_AA"]) >= 1; } },
    { id: "laa",      title: "Leader of Legends",    text: "Pull an Alternate Art Leader",       bounty: 5e7,   reward: 5000,  test: function (p) { return pulled(p, ["L_AA", "SUPER_L"]) >= 1; } },
    { id: "panda",    title: "Where's Pandaman?",    text: "Find a Pandaman variant",            bounty: 6.6e7, reward: 3000,  test: function (p) { return pulled(p, ["PANDA"]) >= 1; } },
    { id: "sp",       title: "Special Delivery",     text: "Pull an SP card",                    bounty: 8e7,   reward: 8000,  test: function (p) { return pulled(p, ["SP", "SP_GOLD"]) >= 1; } },
    { id: "golddon",  title: "Golden DON!!",         text: "Pull a Gold or Special Foil DON!!",  bounty: 1e8,   reward: 8000,  test: function (p) { return pulled(p, ["DON_GOLD", "DON_SP"]) >= 1; } },
    { id: "pack100",  title: "Supernova",            text: "Open 100 packs",                     bounty: 1.2e8, reward: 5000,  test: function (p) { return p.stats.packs >= 100; } },
    { id: "case1",    title: "Case Closed",          text: "Open every box in a case",           bounty: 1.5e8, reward: 20000, test: function (p) { return p.stats.cases >= 1; } },
    { id: "tr",       title: "Treasure Hunter",      text: "Pull a Treasure Rare",               bounty: 3e8,   reward: 20000, test: function (p) { return pulled(p, ["TR"]) >= 1; } },
    { id: "manga",    title: "Manga Panel",          text: "Pull a Manga Rare",                  bounty: 5e8,   reward: 50000, test: function (p) { return pulled(p, ["MANGA", "SIGNED"]) >= 1; } },
    { id: "super",    title: "Super Parallel",       text: "Pull a Super Alternate Art",         bounty: 1e9,   reward: 80000, test: function (p) { return pulled(p, ["SUPER", "SUPER_L"]) >= 1; } },
    { id: "pack1000", title: "Emperor",              text: "Open 1,000 packs",                   bounty: 1.5e9, reward: 50000, test: function (p) { return p.stats.packs >= 1000; } },
    { id: "sets5",    title: "World Traveler",       text: "Open packs from 5 different sets",   bounty: 2e7,   reward: 2000,  test: function (p) { return Object.keys(p.stats.sets).length >= 5; } },
    { id: "half",     title: "Halfway to Laugh Tale", text: "Own half of a set",                 bounty: 4e7,   reward: 4000,  test: function (p) { return p.stats.bestCompletion >= 0.5; } },
    { id: "most",     title: "Laugh Tale",           text: "Own 90% of a set",                   bounty: 4e8,   reward: 30000, test: function (p) { return p.stats.bestCompletion >= 0.9; } },
    { id: "sell1",    title: "Merchant",             text: "Sell a card",                        bounty: 2e6,   reward: 200,   test: function (p) { return p.stats.sold >= 1; } },
    { id: "rich",     title: "Big Spender",          text: "Hold 100,000 ฿ at once",             bounty: 6e7,   reward: 0,     test: function (p) { return p.berries >= 100000; } },
    { id: "streak7",  title: "Loyal Crew",           text: "Keep a 7-day streak",                bounty: 3e7,   reward: 3000,  test: function (p) { return p.streak.count >= 7; } },
    { id: "streak30", title: "Nakama for Life",      text: "Keep a 30-day streak",               bounty: 3e8,   reward: 20000, test: function (p) { return p.streak.count >= 30; } },
    { id: "focus1",   title: "Focused",              text: "Finish a focus session",             bounty: 4e6,   reward: 300,   test: function (p) { return p.stats.focus >= 1; } },
    { id: "focus25",  title: "Haki Master",          text: "Finish 25 focus sessions",           bounty: 2.5e8, reward: 15000, test: function (p) { return p.stats.focus >= 25; } }
];

function totalBounty(p) {
    return ACHIEVEMENTS.reduce(function (a, x) { return a + (p.achievements[x.id] ? x.bounty : 0); }, 0);
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
                 sets: {}, pulled: {}, bestCompletion: 0 },
        achievements: {},              // id -> date unlocked
        bounties: { day: "", list: [] }
    };
}

function parse(text, now) {
    var p = fresh(now);
    try {
        var saved = text ? JSON.parse(text) : null;
        if (saved) {
            Object.keys(saved).forEach(function (k) { p[k] = saved[k]; });
            Object.keys(fresh(now).stats).forEach(function (k) { if (p.stats[k] === undefined) p.stats[k] = fresh(now).stats[k]; });
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

// The day's three bounties, the same all day. sets: [{ id, name }] to pick from.
function makeBounties(day, sets) {
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
    while (picked.length < 3 && all.length) picked.push(all.splice(Math.floor(rnd() * all.length), 1)[0]);
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
    var step = FREE_PACK_HOURS * 3600 * 1000;
    if (p.freePacks >= FREE_PACK_MAX) {
        p.freePackClock = now;
    } else {
        while (p.freePackClock + step <= now && p.freePacks < FREE_PACK_MAX) {
            p.freePacks++;
            p.freePackClock += step;
            events.push({ kind: "freePack" });
        }
        if (p.freePacks >= FREE_PACK_MAX) p.freePackClock = now;
    }
    var today = dayOf(now);
    if (p.streak.day !== today) {
        var yesterday = dayOf(now - 86400 * 1000);
        p.streak.count = p.streak.day === yesterday ? p.streak.count + 1 : 1;
        p.streak.day = today;
        var reward = STREAK_REWARD[Math.min(p.streak.count, STREAK_REWARD.length) - 1];
        var bonusPack = p.streak.count % 7 === 0;
        p.berries += reward;
        p.stats.earned += reward;
        if (bonusPack) p.freePacks++;
        events.push({ kind: "streak", count: p.streak.count, reward: reward, freePack: bonusPack });
    }
    // sets: [{ id, name }] for the day's set bounty, or a function returning them (only called on a new day)
    if (p.bounties.day !== today && sets) p.bounties = { day: today, list: makeBounties(today, typeof sets === "function" ? sets() : sets) };
    return events;
}

// time until the next free pack, ms (0 when full)
function nextFreePackIn(p, now) {
    if (p.freePacks >= FREE_PACK_MAX) return 0;
    return Math.max(0, p.freePackClock + FREE_PACK_HOURS * 3600 * 1000 - now);
}

// Spend on a pack/box: a free pack first (packs only), then berries.
// Returns "free", "paid" or "" (can't afford).
function pay(p, price, freePackOk) {
    if (freePackOk && p.freePacks > 0) {
        p.freePacks--;
        if (p.freePacks === FREE_PACK_MAX - 1) p.freePackClock = Date.now();   // start counting again
        return "free";
    }
    if (p.berries < price) return "";
    p.berries -= price;
    return "paid";
}

function earn(p, amount) {
    p.berries += amount;
    p.stats.earned += amount;
}

// Something happened. ev:
//   { type: "pack", set, tiers: [...], completion: 0..1 }   a pack was opened
//   { type: "box" } / { type: "case" }                         a box / a whole case finished
//   { type: "sell", count, value }                             cards sold
//   { type: "focus" }                                          a focus session finished
//   { type: "income", amount }                                 passive income
// Returns what got completed: [{ kind: "achievement", a } | { kind: "bounty", b }]
function record(p, ev) {
    var s = p.stats, done = [];
    if (ev.type === "pack") {
        s.packs++;
        s.sets[ev.set] = (s.sets[ev.set] || 0) + 1;
        ev.tiers.forEach(function (t) { s.pulled[t] = (s.pulled[t] || 0) + 1; });
        if (ev.completion > s.bestCompletion) s.bestCompletion = ev.completion;
    } else if (ev.type === "box") {
        s.boxes++;
    } else if (ev.type === "case") {
        s.cases++;
    } else if (ev.type === "sell") {
        s.sold += ev.count;
        s.soldValue += ev.value;
    } else if (ev.type === "focus") {
        s.focus++;
    }

    // daily bounties
    var srTiers = ["SR", "AA", "TEX", "SEC", "L_AA", "SP", "SEC_AA", "SUPER_L", "SP_GOLD", "TR", "MANGA", "SIGNED", "SUPER", "PANDA"];
    (p.bounties.list || []).forEach(function (b) {
        if (b.done) return;
        var add = 0;
        if (ev.type === "pack") {
            if (b.kind === "packs") add = 1;
            if (b.kind === "setPacks" && ev.set === b.set) add = 1;
            if (b.kind === "leader") add = ev.tiers.filter(function (t) { return t === "L" || t === "L_AA" || t === "SUPER_L"; }).length;
            if (b.kind === "srplus") add = ev.tiers.filter(function (t) { return srTiers.indexOf(t) >= 0; }).length;
        }
        if (ev.type === "sell" && b.kind === "sell") add = ev.count;
        if (ev.type === "focus" && b.kind === "focus") add = 1;
        if (ev.type === "income" && b.kind === "income") add = ev.amount;
        if (!add) return;
        b.progress = Math.min(b.goal, b.progress + add);
        if (b.progress >= b.goal) {
            b.done = true;
            if (b.freePack) p.freePacks++;
            else earn(p, b.reward);
            done.push({ kind: "bounty", b: b });
        }
    });

    // achievements
    ACHIEVEMENTS.forEach(function (a) {
        if (p.achievements[a.id] || !a.test(p)) return;
        p.achievements[a.id] = dayOf(Date.now());
        if (a.reward) earn(p, a.reward);
        done.push({ kind: "achievement", a: a });
    });
    return done;
}

// passive income for `minutes` active minutes (capped per day)
function addIncome(p, minutes, now) {
    var today = dayOf(now);
    if (p.income.day !== today) p.income = { day: today, earned: 0 };
    var amount = Math.min(INCOME_PER_MINUTE * minutes, INCOME_DAILY_CAP - p.income.earned);
    if (amount <= 0) return [];
    p.income.earned += amount;
    earn(p, amount);
    return record(p, { type: "income", amount: amount });
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
function finishFocus(p) {
    stopFocus(p);
    p.freePacks++;
    earn(p, FOCUS_BERRIES);
    return record(p, { type: "focus" });
}

// ---- what cards are worth ----------------------------------------------------------

// market: { "<card id>|<name>": usd } from optcgapi (see Stage.loadMarket)
function cardValue(card, market) {
    var usd = market ? market[card.id + "|" + card.name] : undefined;
    if (usd !== undefined && usd !== null && usd > 0) return Math.max(1, Math.round(usd * USD_TO_BERRY));
    return BASE_VALUE[card.tier] || 5;
}

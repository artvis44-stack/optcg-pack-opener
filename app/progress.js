.pragma library
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

var PACK_PRICE = { main: 500, extra: 500, premium: 800 };   // ฿ (an English pack is ~$5)
var BOX_DISCOUNT = 0.95;
var CASE_DISCOUNT = 0.85;          // on the boxes left in the case
var USD_TO_BERRY = 100;            // selling: $1 market value = 100 ฿
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
    SUPER: 100000
};

// p (optional): the player, for crew discounts
function packPrice(family, p) {
    return Math.round((PACK_PRICE[family] || PACK_PRICE.main) * (p && hasCrew(p, "sanji") ? 0.9 : 1));
}

function boxPrice(family, packsPerBox, p) {
    var full = (PACK_PRICE[family] || PACK_PRICE.main) * packsPerBox * BOX_DISCOUNT;
    return Math.round(full * (p && hasCrew(p, "franky") ? 0.9 : 1) / 100) * 100;
}

function casePrice(family, packsPerBox, boxesLeft, p) {
    return Math.round(boxPrice(family, packsPerBox, p) * boxesLeft * CASE_DISCOUNT / 100) * 100;
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
// free packs come faster or stack higher.

var SHIPS = [
    { name: "Rowboat",                        price: 0,        income: 0,    freeHours: 6, freeMax: 2,
      text: "Where every pirate starts." },
    { name: "Fishing Boat",                   price: 20000,    income: 0.2,  freeHours: 6, freeMax: 2,
      text: "+20% passive income" },
    { name: "Going Merry",                    price: 100000,   income: 0.5,  freeHours: 6, freeMax: 3,
      text: "+50% passive income, hold 3 free packs" },
    { name: "Going Merry (Flying Model)",     price: 500000,   income: 1,    freeHours: 5, freeMax: 3,
      text: "+100% passive income, a free pack every 5 hours" },
    { name: "Thousand Sunny",                 price: 2500000,  income: 2,    freeHours: 5, freeMax: 4,
      text: "+200% passive income, hold 4 free packs" },
    { name: "Thousand Sunny (Shark Submerge)", price: 12000000, income: 3.5, freeHours: 4, freeMax: 4,
      text: "+350% passive income, a free pack every 4 hours" },
    { name: "Thousand Sunny (Coup de Burst)", price: 60000000, income: 6,    freeHours: 3, freeMax: 5,
      text: "+600% passive income, a free pack every 3 hours, hold 5" }
];

// each recruited once, for good
var CREW = [
    { id: "zoro",    name: "Roronoa Zoro",  price: 15000,   perk: "Focus sessions pay double berries" },
    { id: "nami",    name: "Nami",          price: 25000,   perk: "+25% passive income" },
    { id: "usopp",   name: "Usopp",         price: 40000,   perk: "Single packs: hits 15% likelier" },
    { id: "sanji",   name: "Sanji",         price: 60000,   perk: "Packs cost 10% less" },
    { id: "chopper", name: "Tony Tony Chopper", price: 80000, perk: "Missing a single day doesn't break your streak" },
    { id: "robin",   name: "Nico Robin",    price: 120000,  perk: "Reads a sealed pack: tells you how good it is" },
    { id: "franky",  name: "Franky",        price: 200000,  perk: "Boxes and cases cost 10% less" },
    { id: "brook",   name: "Brook",         price: 300000,  perk: "Cards sell for 10% more" },
    { id: "jinbe",   name: "Jinbe",         price: 500000,  perk: "A fourth daily bounty" },
    { id: "luffy",   name: "Monkey D. Luffy (Gear 5)", price: 5000000, perk: "God packs twice as likely" }
];

// ---- the Port: grading ------------------------------------------------------------
// Send a card off; it comes back in a slab with a grade from 1 to 10 that
// multiplies what it's worth. The grade is rolled when you send it.

var GRADING = [
    { id: "value",    name: "Value",    hours: 24,  base: 300,  pct: 0.05 },
    { id: "standard", name: "Standard", hours: 6,   base: 1000, pct: 0.1 },
    { id: "express",  name: "Express",  hours: 0.5, base: 5000, pct: 0.2 }
];
var GRADE_ODDS = [[10, 0.08], [9, 0.34], [8, 0.3], [7, 0.15], [6, 0.07], [5, 0.03], [4, 0.015], [3, 0.008], [2, 0.004], [1, 0.003]];
var GRADE_MULT = { 10: 4, 9: 1.6, 8: 1.1, 7: 0.9, 6: 0.75, 5: 0.6, 4: 0.5, 3: 0.45, 2: 0.4, 1: 0.35 };
var GRADE_NAME = { 10: "GEM MINT", 9: "MINT", 8: "NM-MT", 7: "NEAR MINT", 6: "EX-MT", 5: "EXCELLENT",
                   4: "VG-EX", 3: "VERY GOOD", 2: "GOOD", 1: "POOR" };

// ---- the Port: the card shop and sealed products ---------------------------------

var DEAL_MARKUP = 1.1;      // today's deals: a little over market value
var ORDER_MARKUP = 1.5;     // any card, ordered from the binder
var DEALS_PER_DAY = 8;
var SEALED_RATE = [0.004, 0.016];   // value growth a week: the newest set .. the oldest

// ---- the Port: cosmetics ---------------------------------------------------------------
// colours: base behind everything, glow in the middle (#AARRGGBB)

var BACKDROPS = [
    { id: "default",   name: "Night Sea",      price: 0,       base: "#05070d", glow: "#18324a80" },
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
    a("sealed1",  "Shrink Wrap",           "Buy a sealed product",                 5e6,   500,   null, function (p) { return Object.keys(p.sealed).length + p.stats.sealedOpened; }, 1),
    a("sealed5",  "Hoarder",               "Hold 5 sealed products at once",       1.2e8, 10000, null, function (p) { return Object.keys(p.sealed).length; }, 5),
    a("investor", "Investor",              "Hold a sealed product worth twice what you paid", 1e9, 80000,
      null, function (p) { return bestSealedGain(p, Date.now()); }, 2, "x"),
    a("cosm3",    "Fashion Pirate",        "Own 3 cosmetics",                      6e7,   5000,  null, function (p) { return Object.keys(p.cosmetics.owned).length; }, 3),
    a("cosmAll",  "Dressed to Kill",       "Own every cosmetic",                   2e9,   150000, null, function (p) { return Object.keys(p.cosmetics.owned).length; }, BACKDROPS.length + SLABS.length - 2),
    a("spend1m",  "Money Talks",           "Spend ฿1,000,000 in total",            2e8,   20000, null, function (p) { return p.stats.spent; }, 1e6, "money"),
    a("spend100m","Berry Burner",          "Spend ฿100,000,000 in total",          4e9,   500000, null, function (p) { return p.stats.spent; }, 1e8, "money")
];

// one set's stats, with defaults for anything not recorded yet
function setStats(p, set) {
    var s = (p.stats.bySet || {})[set] || {};
    return { packs: s.packs || 0, boxes: s.boxes || 0, cases: s.cases || 0, pulled: s.pulled || {}, god: s.god || 0,
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

// set: "" = everything (the overall bounty), else just that set's posters
function totalBounty(p, set) {
    return Object.keys(p.achievements).reduce(function (sum, id) {
        if (set && id.indexOf(set + ":") !== 0) return sum;
        return sum + bountyOf(id);
    }, 0);
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
                 spent: 0, bought: 0, boughtValue: 0, graded: 0, gem10: 0, sealedOpened: 0 },
        achievements: {},              // id -> date unlocked
        bounties: { day: "", list: [] },
        // the Port
        ship: { level: 0 },
        crew: {},                      // id -> date recruited
        grading: {},                   // order id -> { key, card, service, fee, grade, sentAt, readyAt }
        sealed: {},                    // id -> { set, setName, kind, boxes, paid, rate, at }
        prepaidBoxes: {},              // set -> boxes opened from sealed products, waiting in box mode
        shop: { day: "", bought: {} }, // today's deals bought (card key -> true)
        cosmetics: { owned: {}, backdrop: "default", slab: "classic" }
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
        p.berries += reward;
        p.stats.earned += reward;
        if (bonusPack) p.freePacks++;
        events.push({ kind: "streak", count: p.streak.count, reward: reward, freePack: bonusPack });
    }
    // sets: [{ id, name }] for the day's set bounty, or a function returning them (only called on a new day)
    if (p.bounties.day !== today && sets) p.bounties = { day: today, list: makeBounties(today, typeof sets === "function" ? sets() : sets,
                                                                                hasCrew(p, "jinbe") ? 4 : 3) };
    return events;
}

// time until the next free pack, ms (0 when full)
function nextFreePackIn(p, now) {
    if (p.freePacks >= freePackMax(p)) return 0;
    return Math.max(0, p.freePackClock + freePackHours(p) * 3600 * 1000 - now);
}

// Spend on a pack/box: a free pack first (packs only), then berries.
// Returns "free", "paid" or "" (can't afford).
function pay(p, price, freePackOk) {
    if (freePackOk && p.freePacks > 0) {
        p.freePacks--;
        if (p.freePacks === freePackMax(p) - 1) p.freePackClock = Date.now();   // start counting again
        return "free";
    }
    return spend(p, price) ? "paid" : "";
}

// pay berries for anything; false if you can't afford it
function spend(p, amount) {
    amount = Math.round(amount);
    if (p.berries < amount) return false;
    p.berries -= amount;
    p.stats.spent += amount;
    return true;
}

function earn(p, amount) {
    p.berries += amount;
    p.stats.earned += amount;
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

    // achievements: the set posters first (the overall board counts them)
    var check = function (x) {
        if (p.achievements[x.id] || !x.test(p)) return;
        p.achievements[x.id] = dayOf(Date.now());
        if (x.reward) earn(p, x.reward);
        done.push({ kind: "achievement", a: x });
    };
    Object.keys(s.bySet).forEach(function (set) { setAchievements(set).forEach(check); });
    ACHIEVEMENTS.forEach(check);
    return done;
}

// ฿ a minute while you're active: grows with what your collection is worth
function incomePerMinute(p) {
    var base = INCOME_PER_MINUTE + INCOME_VALUE_SCALE * Math.sqrt(Math.max(0, p.stats.value || 0) / 1000);
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
function focusBerries(p) {
    return hasCrew(p, "zoro") ? FOCUS_BERRIES * 2 : FOCUS_BERRIES;
}

function finishFocus(p) {
    stopFocus(p);
    p.freePacks++;
    earn(p, focusBerries(p));
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
function collectionValue(host, dataDir, cards, graded) {
    var markets = {}, out = { total: 0, bySet: {} };
    if (!cards) {
        try {
            var col = JSON.parse(host.readText(dataDir + "/collection.json") || "{}");
            cards = col.cards || {};
            graded = col.graded || {};
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
    return out;
}

// record a fresh collectionValue() (plus your sealed products); returns the completions
function setValue(p, v) {
    return record(p, { type: "value", total: v.total + sealedTotal(p, Date.now()), bySet: v.bySet });
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
    if (!next || !spend(p, next.price)) return false;
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
    if (!c || hasCrew(p, id) || !spend(p, c.price)) return false;
    p.crew[id] = dayOf(Date.now());
    return true;
}

// pack odds the crew changes: { luck (Usopp), godBoost (Luffy) }
function packOptions(p) {
    return { luck: hasCrew(p, "usopp") ? 1.15 : 1, godBoost: hasCrew(p, "luffy") ? 2 : 1 };
}

function sellBonus(p) {
    return hasCrew(p, "brook") ? 1.1 : 1;
}

// ---- the Port: grading ------------------------------------------------------------------

function gradingFee(serviceId, value) {
    var g = GRADING.filter(function (x) { return x.id === serviceId; })[0] || GRADING[0];
    return Math.round(Math.max(g.base, g.pct * value) / 10) * 10;
}

function rollGrade() {
    var r = Math.random(), acc = 0;
    for (var i = 0; i < GRADE_ODDS.length; i++) {
        acc += GRADE_ODDS[i][1];
        if (r < acc) return GRADE_ODDS[i][0];
    }
    return 8;
}

// a slab: { set, key, id, name, tier, image, grade, ... }
function slabValue(slab, market) {
    return Math.round(cardValue(slab, market) * (GRADE_MULT[slab.grade] || 1));
}

// send one copy of a card off (the caller takes it out of the collection);
// card: { id, name, tier, set, image, key }, value: what it's worth raw
function sendToGrading(p, card, serviceId, value, now) {
    var g = GRADING.filter(function (x) { return x.id === serviceId; })[0];
    var fee = gradingFee(serviceId, value);
    if (!g || !spend(p, fee)) return null;
    var id = now.toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    p.grading[id] = { card: card, service: g.id, fee: fee, grade: rollGrade(),
                      sentAt: now, readyAt: now + g.hours * 3600 * 1000 };
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
    return Object.assign({}, o.card, { grade: o.grade, gradedAt: Date.now(), service: o.service });
}

// ---- the Port: the card shop ------------------------------------------------------------

// Today's deals, the same all day: pool is [{ key, card }] (cards you could
// find in your downloaded sets); a couple of chase cards, some mid ones, some cheap.
function dailyDeals(day, pool, rank) {
    var rnd = hash("deals " + day), out = [], used = {};
    var tiers = [[10, 2], [6, 2], [4, 2], [0, 2]];   // [minimum rank, how many]
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

function shopToday(p, now) {
    var today = dayOf(now);
    if (p.shop.day !== today) p.shop = { day: today, bought: {} };
    return p.shop;
}

// ---- the Port: sealed products --------------------------------------------------------------

function sealedValue(item, now) {
    var weeks = Math.max(0, now - item.at) / (7 * 86400 * 1000);
    return Math.round(item.paid * Math.pow(1 + item.rate, weeks));
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

// age: 0 (the newest set) .. 1 (the oldest): older sets gain value faster
function buySealed(p, set, setName, kind, boxes, price, age) {
    if (!spend(p, price)) return null;
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
    earn(p, v);
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

// ---- the Port: cosmetics -----------------------------------------------------------------------

function cosmetic(list, id) {
    return list.filter(function (x) { return x.id === id; })[0] || list[0];
}

function backdrop(p) {
    return cosmetic(BACKDROPS, p.cosmetics && p.cosmetics.backdrop);
}

function slabStyle(p) {
    return cosmetic(SLABS, p.cosmetics && p.cosmetics.slab);
}

function ownsCosmetic(p, id) {
    return id === "default" || id === "classic" || !!(p.cosmetics && p.cosmetics.owned[id]);
}

// buy (if needed) and wear it; kind: "backdrop" | "slab"
function equipCosmetic(p, kind, id) {
    var item = cosmetic(kind === "slab" ? SLABS : BACKDROPS, id);
    if (item.id !== id) return false;
    if (!ownsCosmetic(p, id)) {
        if (!spend(p, item.price)) return false;
        p.cosmetics.owned[id] = dayOf(Date.now());
    }
    p.cosmetics[kind] = id;
    return true;
}

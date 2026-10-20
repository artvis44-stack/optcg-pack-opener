import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress
import "sync.js" as Sync
import "collections.js" as Collections

// Full-screen overlay: sealed pack -> tear -> reveal one by one -> summary.
// Box mode wraps that: sealed box -> grid of 24 packs -> box summary, with the
// boxes dealt from a saved virtual case.
//
// Platform-independent: everything outside the window comes from `host`
// (env / readText / writeText / run, see QuickshellHost.qml).
Item {
    id: stage

    required property QtObject host
    readonly property string home: host.env("HOME")
    readonly property string cacheRoot: (host.env("XDG_CACHE_HOME") || home + "/.cache") + "/optcg"
    readonly property string dataDir: (host.env("XDG_DATA_HOME") || home + "/.local/share") + "/optcg"

    // ---- sets -------------------------------------------------------------
    readonly property string fetchScript: host.appPath("fetch_cards.py")
    readonly property string python: host.env("OPTCG_PYTHON") || "python3"   // runs fetch_cards.py
    property var sets: ({})             // sets.json, loaded once at startup
    readonly property string settingsPath: dataDir + "/settings.json"
    property string setId: host.env("OPTCG_SET") || "OP-17"
    readonly property var setInfo: sets[setId] || {}
    readonly property var cfg: Tiers.setConfig(setInfo)
    property string downloadLine: ""
    property string pickerReturn: "pack"
    readonly property string cacheDir: cacheRoot + "/" + setId
    // official images built by fetch_cards.py; each falls back to a drawn version
    readonly property string packImage: packProbe.status === Image.Ready ? packProbe.source : ""
    readonly property real packAspect: packImage ? packProbe.implicitWidth / packProbe.implicitHeight : 0.625
    readonly property string deckBack: "file://" + cacheRoot + "/assets/back.png"
    readonly property string leaderBack: "file://" + cacheRoot + "/assets/back_leader.png"
    readonly property string donBack: "file://" + cacheRoot + "/assets/back_don.png"
    readonly property string vintageBack: Qt.resolvedUrl("pictures/vintage-back.png")   // the 2005-06 CCG's back (comes with the app)

    readonly property string boxImage: boxProbe.status === Image.Ready ? boxProbe.source : ""

    Image {
        id: packProbe
        source: stage.db ? "file://" + stage.cacheDir + "/pack.png" : ""   // only once the set is on disk
        visible: false
    }
    Image {
        id: boxProbe
        source: stage.db ? "file://" + stage.cacheDir + "/box.png" : ""
        visible: false
    }

    property var db: null
    property string error: ""
    property string phase: "loading"   // loading | error | pack | reveal | summary | binder
                                       // | boxSealed | boxGrid | boxSummary | sets | downloading
                                       // | showcaseView (opened by double-clicking the desktop showcase)
                                       // | board (the wanted board: bounties and achievements)
                                       // | sync (the sync account screen) | port (ship, crew, shop, sealed, cosmetics)
                                       // | vault (graded slabs, grading orders, the set registry)
                                       // | show (the weekly card show: no prices anywhere until you leave)
    property string boardReturn: "pack"
    property string mode: host.env("OPTCG_MODE") === "box" ? "box" : "pack"
    readonly property bool inBoxScreen: phase === "boxSealed" || phase === "boxGrid" || phase === "boxSummary"
    // ---- sound (Sounds.qml; M mutes, remembered in settings.json) ----------------
    property bool muted: host.env("OPTCG_MUTE") === "1" || !!readSettings().muted
    Loader {
        id: soundLoader
        source: "Sounds.qml"
        onLoaded: item.dir = "file://" + stage.host.appPath("app/sounds")
    }
    function sfx(name) {
        if (!muted && soundLoader.item) soundLoader.item.play(name);
    }
    // the sound for revealing a card of this tier (nothing below Super Rare)
    function revealSound(tier) {
        return tier.rank >= 10 ? "legendary" : tier.rank >= 6 ? "epic" : tier.rank >= 4 ? "rare" : "";
    }
    function toggleMute() {
        muted = !muted;
        saveSettings({ muted: muted });
        toast(muted ? "Sound off (M)" : "Sound on (M)");
        if (muted && soundLoader.item) soundLoader.item.stop("charge");
    }
    function readSettings() {
        try { return JSON.parse(host.readText(settingsPath) || "{}"); } catch (e) { return {}; }
    }
    function saveSettings(changes) {
        host.writeText(settingsPath, JSON.stringify(Object.assign(readSettings(), changes)));
    }

    property var pack: []
    readonly property string godPack: pack.length && Tiers.isGodPack(pack) ? Tiers.godPackName(pack, setInfo) : ""
    property int revealed: 0
    property bool cardsIn: false
    property bool charging: false
    property int inspectIndex: -1
    property int packsOpened: 0
    property string packArt: ""
    property real shake: 0

    // holo clock, in seconds
    property real t: 0
    NumberAnimation on t { from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite }

    readonly property real cw: Math.min(360, height * 0.47 * 0.716)
    readonly property var centerTier: revealed > 0 && revealed <= pack.length ? Tiers.tierOf(pack[revealed - 1]) : Tiers.info.C
    readonly property var nextTier: revealed < pack.length ? Tiers.tierOf(pack[revealed]) : Tiers.info.C

    // ---- collection: every opened pack is saved (forced packs aren't) -----
    readonly property string collectionPath: host.env("OPTCG_COLLECTION") || dataDir + "/collection.json"
    readonly property string forceHit: host.env("OPTCG_FORCE_HIT")
    readonly property bool cheating: forceHit !== ""
    // sandbox: everything free, nothing saved (no collection, no progression)
    readonly property bool sandbox: host.env("OPTCG_SANDBOX") === "1"
    readonly property bool offTheRecord: cheating || sandbox

    // ---- progression (see progress.js) ----------------------------------------------
    readonly property string progressPath: dataDir + "/progress.json"
    property var progress: Progress.fresh(Date.now())
    property bool packPaid: false           // the sealed single pack on screen is paid for
    property var celebrations: []           // completions waiting to be shown
    property var markets: ({})              // set id -> { "<id>|<name>": usd } (market prices)
    readonly property var market: markets[setId] || ({})
    readonly property int setTotal: {
        var seen = {};
        if (db) db.cards.forEach(c => seen[c.image.split("/").pop()] = true);
        return Object.keys(seen).length;
    }
    property var collection: ({ packs: 0, cards: {} })
    property var packNew: []            // per card of the current pack: first time pulled?
    property string binderReturn: "pack"

    // ---- box mode: a saved virtual case, opened box by box --------------
    readonly property string casePath: host.env("OPTCG_CASE") || dataDir + "/case-" + setId + ".json"
    property var caseState: null        // { set, box, opened, topperTaken, boxes: [box][pack][card key], toppers: [key] }
    property var boxPacks: []           // the current box: its packs of cards
    property var boxOpened: []
    property var boxTopper: null        // OP-01/02: a card on top of the box, outside the packs
    property bool topperTaken: false
    property int boxIndex: 0            // within the case
    property int currentPackIdx: -1     // pack of the box being opened

    focus: true
    opacity: 0
    NumberAnimation on opacity { id: fadeIn; to: 1; duration: 250 }

    Component.onCompleted: {
        sets = JSON.parse(host.readText(host.appPath("app/sets.json")) || "{}");
        reloadCollection();
        if (!offTheRecord) {
            prog(p => Progress.backfill(p, host, dataDir, cacheRoot).concat(Progress.accrue(p, Date.now(), () => downloadedSets())));
            Object.keys(Progress.SHOW_SETS).forEach(id => loadMarket(id));   // the show's, and what they're worth in the collection
            refreshValue();
            refreshRegistry();
        }
        if (host.env("OPTCG_INSPECT") === "1" && openShowcaseView()) return;
        if (!host.env("OPTCG_SET")) {
            try {
                var last = readSettings().set;
                if (last && sets[last]) setId = last;
            } catch (e) {}
        }
        loadSet(setId);
        if (atShow) {   // you closed the app at the show: you're still there
            showReturn = "pack";
            phase = "show";
        }
        backgroundDownload.start();
    }

    // ---- updates (the Mac app: mac/update.py, which a LaunchAgent also runs every few hours) ----
    readonly property bool canUpdate: Qt.platform.os === "osx"
    property string updateState: ""     // "" | checking | upToDate | available | updating | updated | failed
    property string updateHave: ""
    property string updateLatest: ""
    function checkForUpdate() {
        if (!canUpdate || updateState === "checking" || updateState === "updating" || updateState === "updated") return;
        updateState = "checking";
        var answer = null;
        host.run([python, "-I", "-u", host.appPath("mac/update.py"), "--check"],
                 line => { try { answer = JSON.parse(line); } catch (e) {} },
                 code => {
                     if (!answer || answer.error) {
                         updateState = "failed";
                         return;
                     }
                     updateHave = answer.have;
                     updateLatest = answer.latest;
                     updateState = answer.newer ? "available" : "upToDate";
                 });
    }
    // U / the top bar: check, or install what's out
    function updateButton() {
        if (!canUpdate) return;
        if (updateState !== "available") {
            checkForUpdate();
            return;
        }
        updateState = "updating";
        toast("Updating to " + updateLatest + "...");
        host.run([python, "-I", "-u", host.appPath("mac/update.py")], null, code => {
            updateState = code === 0 ? "updated" : "failed";
            toast(code === 0 ? "Updated to " + updateLatest + ". Close the pack opener and open it again to use it."
                             : "The update didn't work; it'll try again by itself in a few hours.");
        });
    }
    Timer {   // see if there's one a little after opening
        running: stage.canUpdate
        interval: 5 * 1000
        onTriggered: stage.checkForUpdate()
    }

    // the rest downloads in the background, so it's there when you want it (the
    // desktop companion does this too; fetch_cards.py runs one at a time)
    Timer {
        id: backgroundDownload
        interval: 20 * 1000
        onTriggered: stage.host.run([stage.python, "-I", "-u", stage.fetchScript, "background",
                                     JSON.stringify(Progress.playmatDownloads())], null, null)
    }

    // ---- progression ----------------------------------------------------------------

    // change progress.json; completions (achievements, bounties, streak...) get celebrated
    function prog(fn) {
        if (offTheRecord) return null;
        var r = Progress.update(host, progressPath, fn);
        progress = r.p;
        if (Array.isArray(r.result) && r.result.length) celebrate(r.result);
        return r.result;
    }

    // what the collection is worth feeds the passive income and the value posters
    function refreshValue() {
        prog(p => Progress.setValue(p, Progress.collectionValue(host, dataDir, collection.cards, collection.graded || {}, collection.sets || {})));
    }

    function reloadProgress() {
        if (!offTheRecord) progress = Progress.parse(host.readText(progressPath), Date.now());
    }

    function downloadedSets() {
        return Object.keys(sets).filter(id => downloaded(id)).map(id => ({ id: id, name: sets[id].name }));
    }

    function celebrate(items) {
        celebrations = celebrations.concat(items);
        if (!celebrationTimer.running) nextCelebration();
    }

    property var currentCelebration: null
    function nextCelebration() {
        if (!celebrations.length) {
            currentCelebration = null;
            return;
        }
        currentCelebration = celebrations[0];
        celebrations = celebrations.slice(1);
        var ck = currentCelebration;
        var diamond = ck.kind === "graded" && !!ck.slab.diamond;
        celebrationTimer.interval = diamond ? 9000 : 3800;
        if (diamond) {   // the secret grade (DiamondReveal.qml): everything at once
            diamondFlash.restart();
            sfx("god");
            diamondSounds.restart();
        } else {
            if (ck.kind === "graded" && ck.slab.grade === 10) flashAnim.restart();
            sfx(ck.kind === "achievement" ? "poster" : ck.kind === "graded" && ck.slab.grade === 10 ? "legendary"
                : ck.kind === "graded" && ck.slab.grade >= 9 ? "epic" : "chime");
        }
        celebrationTimer.restart();
    }
    // try the Diamond Label reveal on this set's best card; only shown, nothing saved
    function testDiamond() {
        if (!db || !db.cards.length) return;
        var c = db.cards.slice().sort((a, b) => Tiers.tierOf(b).rank - Tiers.tierOf(a).rank)[0];
        celebrations = [{ kind: "graded", slab: Object.assign({}, c, { set: setId, key: cardKey(c), grade: 10, diamond: true }) }]
                       .concat(currentCelebration ? [currentCelebration] : [], celebrations);   // now, ahead of the rest
        celebrationTimer.stop();
        nextCelebration();
    }
    readonly property bool diamondShowing: !!currentCelebration && currentCelebration.kind === "graded" && !!currentCelebration.slab.diamond
    SequentialAnimation {
        id: diamondSounds
        PauseAnimation { duration: 650 }
        ScriptAction { script: stage.sfx("legendary") }
        PauseAnimation { duration: 900 }
        ScriptAction { script: stage.sfx("coin") }
    }
    // a click dismisses the one on screen; "clear all" (or a right click) the whole queue
    function clearCelebrations() {
        celebrations = [];
        celebrationTimer.stop();
        nextCelebration();
    }
    function skipCelebration() {
        celebrationTimer.stop();
        nextCelebration();
    }
    Timer {
        id: celebrationTimer
        interval: 3800
        onTriggered: stage.nextCelebration()
    }
    Timer {   // the companion changes progress too (income, focus, free packs), and sync both files
        interval: 3000
        running: !stage.offTheRecord
        repeat: true
        onTriggered: {
            stage.reloadProgress();
            stage.reloadCollection();
            stage.collectGrading();
        }
    }

    // ---- sync (see sync.js): the companion does it; this only while it isn't running ----
    property string syncStatus: ""
    property bool syncOn: false
    function syncRound() {
        syncOn = Sync.signedIn(Sync.account(host, dataDir));
        if (syncOn && !offTheRecord && !Sync.companionSyncing(host, dataDir))
            Sync.syncOnce(host, dataDir, sets, "opener", changed => {
                if (changed.indexOf("collection") >= 0) reloadCollection();
                if (changed.indexOf("progress") >= 0) reloadProgress();
            });
        syncStatus = Sync.statusText(host, dataDir);
    }
    Timer {
        interval: Sync.INTERVAL
        running: true
        triggeredOnStart: true
        repeat: true
        onTriggered: stage.syncRound()
    }

    // the collection as it is on disk (another device's pulls arrive there via sync)
    property string collectionText: ""
    function readCollection() {
        var text = host.readText(collectionPath);
        try {
            return text ? JSON.parse(text) : { packs: 0, cards: {} };
        } catch (e) {
            console.warn("collection file unreadable:", e);
            return JSON.parse(JSON.stringify(collection));
        }
    }
    function reloadCollection() {
        var text = host.readText(collectionPath);
        if (text === collectionText) return;
        collectionText = text;
        try {
            if (text) collection = JSON.parse(text);
        } catch (e) {
            console.warn("collection file unreadable:", e);
        }
    }
    function writeCollection(col) {
        collection = col;
        collectionText = JSON.stringify(col, null, 1);
        host.writeText(collectionPath, collectionText);
    }

    // what a card of each tier of a set is worth on average, ฿: { tier: ฿ } (Progress.boxPrice
    // prices boxes and packs from it). From the set's cards and its market prices (loaded, or
    // the cached file); null for a set that isn't downloaded (base values then)
    property var tierValueCache: ({})
    function tierValues(id) {
        var m = markets[id];   // a dependency: prices change when the market comes in
        var cached = tierValueCache[id];
        if (cached && cached.m === m && cached.v) return cached.v;
        var cards = id === setId && db ? db.cards : null;
        if (!cards) {
            try { cards = (JSON.parse(host.readText(cacheRoot + "/" + id + "/cards.json") || "null") || {}).cards || null; }
            catch (e) { cards = null; }
        }
        var prices = m;
        if (!prices) {
            try { prices = (JSON.parse(host.readText(dataDir + "/market/" + id + ".json") || "null") || {}).prices || null; }
            catch (e) { prices = null; }
        }
        var v = null;
        if (cards && cards.length) {
            var sum = {}, n = {}, seen = {};
            cards.forEach(c => {
                var k = c.image.split("/").pop();
                if (seen[k]) return;
                seen[k] = true;
                sum[c.tier] = (sum[c.tier] || 0) + Progress.cardValue(c, prices);
                n[c.tier] = (n[c.tier] || 0) + 1;
            });
            v = {};
            Object.keys(sum).forEach(t => v[t] = sum[t] / n[t]);
        }
        tierValueCache[id] = { m: m, v: v };
        return v;
    }
    readonly property int packCost: Progress.packPrice(cfg, progress, setId, tierValues(setId))
    readonly property int boxCost: Progress.boxPrice(cfg, progress, setId, tierValues(setId))
    // caseState is changed in place, so these depend on caseRev (bumped by saveCase) to stay current
    property int caseRev: 0
    readonly property int boxesLeftToBuy: { caseRev; return boxesLeft(); }
    readonly property int prepaidBoxes: { caseRev; return caseState ? caseState.prepaid || 0 : 0; }
    readonly property bool boxPaidNow: { caseRev; return !!(caseState && caseState.boxPaid); }
    // what this box cost you (BoxView's profit); free (off the record) or from before it was kept: the box price
    readonly property int boxPaidPrice: { caseRev; return caseState && caseState.boxPrice !== undefined ? caseState.boxPrice : boxCost; }
    // the set's per-box chances (Tiers.boxChances), worked out once per set (progress reloads
    // every few seconds; godBoost only signals when it changes)
    readonly property real godBoost: Progress.packOptions(progress, setId).godBoost || 1
    readonly property var boxOdds: db ? Tiers.boxChances(db.cards, setInfo, godBoost) : null
    // C: the rest of this case, or once that's paid for, another whole case (its boxes carry over)
    readonly property int caseCost: Progress.casePrice(cfg, boxesLeftToBuy > 0 ? boxesLeftToBuy : cfg.boxes, progress, setId, tierValues(setId))

    // boxes of this case not paid for yet (the open one counts once it's paid)
    function boxesLeft() {
        if (!caseState) return 0;
        return Math.max(0, cfg.boxes - boxIndex - (caseState.boxPaid ? 1 : 0) - (caseState.prepaid || 0));
    }

    function payForPack() {
        if (offTheRecord || packPaid) return true;
        var how = prog(p => Progress.pay(p, packCost, true, "packs"));
        if (!how) {
            toast("Not enough berries: a pack is " + Progress.format(packCost) + ". Focus, keep your streak, sell duplicates or wait for a free pack.");
            return false;
        }
        packPaid = true;
        if (how === "paid") sfx("coin");
        return true;
    }

    function payForBox() {
        if (offTheRecord || caseState.boxPaid) return true;
        if ((caseState.prepaid || 0) > 0) {
            var cost = prepaidCostSoFar(), each = Math.round(cost / caseState.prepaid);   // its share of what they cost
            caseState.prepaidCost = Math.max(0, cost - each);
            caseState.prepaid--;
            caseState.boxPrice = each;
        } else if (!prog(p => Progress.pay(p, boxCost, false, "boxes"))) {
            toast("Not enough berries: a box is " + Progress.format(boxCost) + " (you have " + Progress.format(progress.berries) + ").");
            return false;
        } else {
            caseState.boxPrice = boxCost;
        }
        caseState.boxPaid = true;
        saveCase();
        sfx("coin");
        return true;
    }

    function buyCase() {
        if (offTheRecord || !inBoxScreen || !caseState) return;
        // worked out now, not from a binding: pressing C fast must not pay twice for the same boxes
        var rest = boxesLeft(), n = rest > 0 ? rest : cfg.boxes;
        var cost = Progress.casePrice(cfg, n, progress, setId, tierValues(setId));
        if (!prog(p => Progress.pay(p, cost, false, "cases"))) {
            toast("Not enough berries: " + (rest > 0 ? "the rest of this case (" + n + " boxes)" : "another case (" + n + " boxes)")
                  + " is " + Progress.format(cost) + ".");
            return;
        }
        caseState.prepaidCost = prepaidCostSoFar() + cost;
        caseState.prepaid = (caseState.prepaid || 0) + n;
        saveCase();
        sfx("coin");
        toast((rest > 0 ? "Bought the rest of the case: " : "Bought another case: ") + n + " boxes for " + Progress.format(cost)
              + "  ·  " + caseState.prepaid + " prepaid boxes waiting");
    }

    // a pack's worth of cards went into the binder
    function recordPackProgress(cards) {
        recordPacksProgress([cards]);
    }
    // packs' worth (each already in the binder), in one go: one progress update for all of them
    function recordPacksProgress(packs) {
        if (offTheRecord || !packs.length) return;
        var have = ownedKeys();
        var owned = Object.keys(have).filter(k => k.indexOf(setId + ":") === 0).length;
        // how much of each tier group (every Leader, every SR...) you own, and which tiers the set has
        var sp = Progress.setProgress(setId, db.cards, have);
        prog(p => packs.reduce((done, cards) => done.concat(
            Progress.record(p, { type: "pack", set: setId, tiers: cards.map(c => c.tier), god: Tiers.isGodPack(cards),
                                 completion: setTotal ? owned / setTotal : 0,
                                 groups: sp.groups, present: sp.present }) || []), []));
    }

    // the box (and maybe the case) is done
    function recordBoxDone() {
        if (offTheRecord || caseState.boxRecorded) return;
        caseState.boxRecorded = true;
        saveCase();
        prog(p => {
            var done = Progress.record(p, { type: "box", set: setId });
            if (boxIndex === cfg.boxes - 1) done = done.concat(Progress.record(p, { type: "case", set: setId }));
            return done;
        });
    }

    // ---- selling --------------------------------------------------------------------

    function cardValue(c) {
        return Progress.cardValue(c, markets[c.set || setId]);
    }

    // what selling it gets you (Brook adds 10%)
    function sellPrice(c) {
        return Math.round(cardValue(c) * Progress.sellBonus(progress));
    }

    // ---- the Port (PortView.qml): buying, grading, sealed products, ship, crew, cosmetics ----

    // buy a card: price in ฿; deal: one of today's deals (bought once a day)
    function buyCard(c, price, deal) {
        if (offTheRecord) return false;
        var key = cardKey(c);
        var ok = prog(p => {
            if (deal && Progress.shopToday(p, Date.now()).bought[key]) return "sold";
            if (!Progress.spend(p, price, "shop")) return "short";
            if (deal) p.shop.bought[key] = true;
            return "ok";
        });
        if (ok !== "ok") {
            toast(ok === "sold" ? "You already bought that deal today." : "Not enough berries: that's " + Progress.format(price) + ".");
            return false;
        }
        var col = readCollection(), e = col.cards[key];
        if (e) e.count++;
        else col.cards[key] = { id: c.id, name: c.name, tier: c.tier, count: 1, first: new Date().toISOString() };
        writeCollection(col);
        prog(p => Progress.record(p, { type: "bought", count: 1, value: price }));
        refreshValue();
        sfx("coin");
        toast("Bought " + Tiers.displayName(c) + " for " + Progress.format(price));
        return true;
    }

    // send one copy off for grading; cond: which copy ("unchecked" or a Progress.CONDITIONS id)
    function gradeCard(c, service, cond) {
        if (offTheRecord) return false;
        cond = cond || "unchecked";
        var key = cardKey(c), col = readCollection(), e = col.cards[key];
        if (!e || !(Progress.conditions(e)[cond] > 0)) return false;
        var card = { id: c.id, name: c.name, tier: c.tier, set: c.set || setId, image: c.image, key: key, cond: cond };
        var id = prog(p => Progress.sendToGrading(p, card, service, cardValue(c), Date.now()));
        if (!id) {
            toast("Not enough berries: grading it costs " + Progress.format(Progress.gradingFee(service, cardValue(c), progress)) + ".");
            return false;
        }
        Progress.takeCopy(e, cond);
        if (e.count <= 0) delete col.cards[key];
        writeCollection(col);
        refreshValue();
        sfx("coin");
        var g = Progress.GRADING.filter(x => x.id === service)[0];
        toast("Sent " + Tiers.displayName(c) + " for grading: back in " + (g.hours < 1 ? g.hours * 60 + " minutes" : g.hours + " hours"));
        return true;
    }

    // pre-grade: look one unchecked copy over; returns its condition ("" if it didn't happen)
    function preGradeCard(c) {
        if (offTheRecord) return "";
        var key = cardKey(c), col = readCollection(), e = col.cards[key];
        if (!e || Progress.conditions(e).unchecked <= 0) return "";
        var fee = Progress.preGradeFee(cardValue(c));
        if (prog(p => Progress.spend(p, fee, "grading")) !== true) {
            toast("Not enough berries: a pre-grade costs " + Progress.format(fee) + ".");
            return "";
        }
        var cond = Progress.preGrade(e);
        writeCollection(col);
        sfx("flip");
        toast(Tiers.displayName(c) + ": this copy is " + Progress.CONDITION[cond].name + "  ·  "
              + Math.round(Progress.serviceOdds(cond, "value")[0][1] * 100) + "% chance of a 10");
        return cond;
    }

    // prep a copy of condition cond: a level up, or (Progress.PREP_SLIP) a level down
    function prepCard(c, cond) {
        if (offTheRecord) return false;
        var key = cardKey(c), col = readCollection(), e = col.cards[key];
        if (!e || !(Progress.conditions(e)[cond] > 0) || Progress.CONDITION[cond].rank === 0) return false;
        var fee = Progress.prepFee(cardValue(c));
        if (prog(p => Progress.spend(p, fee, "grading")) !== true) {
            toast("Not enough berries: prep costs " + Progress.format(fee) + ".");
            return false;
        }
        var r = Progress.prep(e, cond);
        writeCollection(col);
        sfx(r.slipped ? "flip" : "chime");
        toast(r.slipped ? "The prep went wrong: that copy is " + Progress.CONDITION[r.to].name + " now."
                        : "Prepped: that copy is " + Progress.CONDITION[r.to].name + " now.");
        return true;
    }

    // crack a slab open: the card goes back in the binder, raw (Progress.crackCondition)
    function crackSlab(id) {
        var col = readCollection(), s = (col.graded || {})[id];
        if (!s || offTheRecord || inCase(col, id)) return;
        var cond = Progress.crackCondition(s);
        delete col.graded[id];
        var key = s.key || (s.set + ":" + String(s.image).split("/").pop());
        var e = col.cards[key];
        if (!e) e = col.cards[key] = { id: s.id, name: s.name, tier: s.tier, count: 0, first: new Date().toISOString() };
        Progress.addCopy(e, cond);
        writeCollection(col);
        refreshValue();
        refreshRegistry();
        sfx("tear");
        var was = Progress.CONDITION[s.cond];
        toast("Cracked the " + s.grade + " " + Tiers.displayName(s) + ": it's back in the binder, "
              + (!cond ? "unchecked" : Progress.CONDITION[cond].name
                 + (was && was.id !== cond ? " (it got a little worn coming out)" : "")) + ".");
    }

    // review: a slab's grade goes up one, or stays (Progress.reviewChance); once per slab
    function reviewSlab(id) {
        var col = readCollection(), s = (col.graded || {})[id];
        if (!s || offTheRecord || inCase(col, id)) return;
        var chance = Progress.reviewChance(s);
        if (chance <= 0) return;
        var fee = Progress.reviewFee(slabValue(s));
        if (prog(p => Progress.spend(p, fee, "grading")) !== true) {
            toast("Not enough berries: a review costs " + Progress.format(fee) + ".");
            return;
        }
        var up = Math.random() < chance;
        s.reviewed = true;
        if (up) s.grade++;
        writeCollection(col);
        refreshValue();
        if (up) {
            prog(p => Progress.record(p, { type: "reviewed", grade: s.grade }));
            refreshRegistry();
            celebrate([{ kind: "graded", slab: Object.assign({ slabId: id }, s) }]);
        } else {
            sfx("flip");
            toast("The review kept it at " + s.grade + ".");
        }
    }

    // graded cards that are back go into the collection, each celebrated
    function collectGrading() {
        if (offTheRecord || !Progress.readyOrders(progress, Date.now()).length) return;
        var slabs = [];
        prog(p => {
            Progress.readyOrders(p, Date.now()).forEach(id => {
                var slab = Progress.collectOrder(p, id);
                slab.slabId = id;
                slabs.push(slab);
            });
            return [];
        });
        if (!slabs.length) return;
        var col = readCollection();
        col.graded = col.graded || {};
        slabs.forEach(s => col.graded[s.slabId] = s);
        writeCollection(col);
        slabs.forEach(s => prog(p => Progress.record(p, { type: "graded", grade: s.grade })));
        refreshRegistry();
        celebrate(slabs.map(s => ({ kind: "graded", slab: s })));
        refreshValue();
    }

    // the set registry: your best grade of each card, per set (Progress.registry)
    function refreshRegistry() {
        if (offTheRecord) return;
        var graded = collection.graded || {}, cardsBySet = {};
        Object.keys(graded).forEach(id => {
            var set = graded[id].set;
            if (!cardsBySet[set]) cardsBySet[set] = cardsOf(set);
        });
        var reg = Progress.registry(graded, cardsBySet, c => Tiers.tierOf(c).rank);
        prog(p => Progress.record(p, { type: "registry", bySet: reg }));
    }

    function slabValue(s) {
        return Math.round(Progress.slabValue(s, markets[s.set]) * Progress.sellBonus(progress));
    }

    function sellSlab(id) {
        var col = readCollection(), s = (col.graded || {})[id];
        if (!s || offTheRecord || inCase(col, id)) return;
        var v = slabValue(s);
        delete col.graded[id];
        writeCollection(col);
        prog(p => {
            Progress.earn(p, v, "sell");
            return Progress.record(p, { type: "sell", count: 1, value: v });
        });
        refreshValue();
        refreshRegistry();
        sfx("coin");
        toast("Sold the " + s.grade + " " + Tiers.displayName(s) + " for " + Progress.format(v));
    }

    // ---- collections (collections.js) and the display cases they're saved in -----------
    // every downloaded set's cards (to build the collections from), read when first needed
    property var allCards: null
    function loadAllCards() {
        var out = {};
        Object.keys(sets).forEach(id => {
            var text = host.readText(cacheRoot + "/" + id + "/cards.json");
            if (!text) return;
            try { out[id] = JSON.parse(text).cards || []; } catch (e) {}
        });
        Object.keys(Progress.SHOW_SETS).forEach(id => { var c = cardsOf(id); if (c.length) out[id] = c; });
        allCards = out;
    }
    readonly property var collectionDefs: allCards ? Collections.build(allCards, Object.assign({}, sets, Progress.SHOW_SETS)) : []
    readonly property var collectionById: {
        var m = {};
        collectionDefs.forEach(d => m[d.id] = d);
        return m;
    }
    // saved sets: id -> { title, kind, style, set, slabs: [slab id], gem, avg, savedAt }
    readonly property var savedSets: collection.sets || ({})
    readonly property var lockedSlabs: {   // slab id -> the saved set it's in
        var m = {};
        Object.keys(savedSets).forEach(id => (savedSets[id].slabs || []).forEach(s => m[s] = id));
        return m;
    }
    // the slabs not in a display case, by card key, best first (Collections.fill)
    readonly property var freeSlabs: {
        var m = {};
        Object.keys(slabsByKey).forEach(k => {
            var free = slabsByKey[k].filter(s => !lockedSlabs[s.slabId]);
            if (free.length) m[k] = free;
        });
        return m;
    }

    // a slab in a display case can't go on its own; says so
    function inCase(col, slabId) {
        var sets = col.sets || {};
        var id = Object.keys(sets).filter(k => (sets[k].slabs || []).indexOf(slabId) >= 0)[0];
        if (id) toast("That slab is in the " + sets[id].title + " display case: break the set first (the vault's Sets tab).");
        return !!id;
    }

    // a saved set's slabs (localCard'd, with slabId; null for one that's gone, sold on another computer)
    function savedSlabs(id) {
        var g = collection.graded || {};
        return ((savedSets[id] || {}).slabs || []).map(s => g[s] ? Object.assign({ slabId: s }, localCard(g[s])) : null);
    }
    // what a saved set is worth: its slabs, plus the set bonus
    function savedWorth(id) {
        var bonus = Progress.setBonus((savedSets[id] || {}).gem);
        return Math.round(savedSlabs(id).reduce((n, s) => n + (s ? slabValue(s) : 0), 0) * (1 + bonus));
    }

    // put a complete collection in a display case: its best free slabs, locked in
    function saveCollectionSet(defId) {
        var def = collectionById[defId];
        if (!def || offTheRecord || savedSets[defId]) return;
        var f = Collections.fill(def, freeSlabs);
        if (!f.complete) return;
        var r = Collections.rating(f.slabs), col = readCollection();
        if (f.slabs.some(s => !(col.graded || {})[s.slabId])) return;   // changed under us; try again
        col.sets = col.sets || {};
        col.sets[defId] = { title: def.title, kind: def.kind, style: def.style, set: def.set || "",
                            slabs: f.slabs.map(s => s.slabId), gem: r.gem, avg: Math.round(r.avg * 100) / 100,
                            savedAt: new Date().toISOString() };
        writeCollection(col);
        var worth = f.slabs.reduce((n, s) => n + Progress.slabValue(s, markets[s.set]), 0);
        var rewarded = false;
        prog(p => {
            var poster = Progress.rewardSet(p, defId, def.title, def.slots.length, worth, r.gem);
            rewarded = !!poster;
            return poster ? [poster] : [];
        });
        refreshValue();
        if (r.gem) flashAnim.restart();
        sfx(r.gem ? "legendary" : "epic");
        if (!rewarded) toast(def.title + " is back in its display case.");
    }

    // take a set out of its case: the slabs are free again, the bonus goes
    function breakCollectionSet(id) {
        var col = readCollection();
        if (!col.sets || !col.sets[id] || offTheRecord) return;
        var title = col.sets[id].title;
        delete col.sets[id];
        writeCollection(col);
        refreshValue();
        sfx("tear");
        toast("Took " + title + " out of its display case: its slabs are loose again.");
    }

    // sealed products: kind "box" | "case"; older sets gain value faster
    function buySealed(set, kind) {
        if (offTheRecord) return;
        var info = sets[set] || {}, c = Tiers.setConfig(info);
        var ids = Object.keys(sets).filter(id => (sets[id].lang || "en") === (info.lang || "en"));   // release order
        var boxes = kind === "case" ? c.boxes : 1;
        var price = kind === "case" ? Progress.casePrice(c, c.boxes, progress, set, tierValues(set))
                                    : Progress.boxPrice(c, progress, set, tierValues(set));
        var age = ids.length > 1 ? (ids.length - 1 - ids.indexOf(set)) / (ids.length - 1) : 0;
        if (!prog(p => Progress.buySealed(p, set, info.name || set, kind, boxes, price, age))) {
            toast("Not enough berries: that's " + Progress.format(price) + ".");
            return;
        }
        refreshValue();
        sfx("coin");
        toast("Bought a sealed " + set + " " + kind + " for " + Progress.format(price));
    }

    function sellSealed(id) {
        var v = prog(p => Progress.sellSealed(p, id));
        if (!v) return;
        refreshValue();
        sfx("coin");
        toast("Sold it for " + Progress.format(v));
    }

    // ---- the card show (CardShow.qml; the rules are in progress.js) ---------------------
    // While you're there nothing shows a price: the binder, the vault, the port, the
    // wanted board and the shop stay shut until you leave (and the desktop showcase hides its price).
    readonly property bool atShow: !offTheRecord && Progress.atShow(progress, Date.now())
    property string showReturn: "pack"
    property var showRecap: null         // what you came home with, after you leave

    // say so if you're at the show (and so can't look at prices); true: you are
    function noPeeking() {
        if (!atShow) return false;
        toast("You're at the card show: no looking up prices. Leave the show (Esc) first.");
        return true;
    }

    // the vintage cards (app/vintage.json) as cards.json has them (fetch_cards.py vintage_cards):
    // each Character card's holo foil is a card of its own. Their pictures, when fetch_cards.py
    // has them, go in the cache's VINTAGE folder (DrawnFace draws the rest).
    property var vintageData: null
    function vintageCards() {
        if (!vintageData) {
            try { vintageData = JSON.parse(host.readText(host.appPath("app/vintage.json")) || "{}"); } catch (e) { vintageData = {}; }
        }
        var v = vintageData, out = [];
        (v.cards || []).forEach(c => {
            var card = { id: c.id, name: c.name, tier: c.tier, rarity: c.rarity, type: "Character", origin: c.set,
                         character: c.character, year: (v.sets || {})[c.set] || 0, refUsd: c.refUsd,
                         image: cacheRoot + "/VINTAGE/" + c.id + ".jpg" };
            out.push(card);
            if (c.foil) out.push(Object.assign({}, card, { id: c.id + "-F", tier: "V_FOIL", refUsd: c.foil,
                                                           image: cacheRoot + "/VINTAGE/" + c.id + "-F.jpg" }));
        });
        return out;
    }

    // a set's cards: the cached cards.json (the vintage ones come with the app)
    function cardsOf(id) {
        if (id === "VINTAGE") return vintageCards();
        try { return JSON.parse(host.readText(cacheRoot + "/" + id + "/cards.json") || "{}").cards || []; } catch (e) { return []; }
    }

    // sealed vintage packs and boxes, ฿: { "<set name>": { pack, box } } (app/vintage.json "sealed", USD)
    function vintageSealed() {
        vintageCards();   // loads vintageData
        var out = {}, s = vintageData.sealed || {};
        Object.keys(s).forEach(k => out[k] = { pack: s[k].pack * Progress.USD_TO_BERRY, box: s[k].box * Progress.USD_TO_BERRY });
        return out;
    }

    // every card of your downloaded sets, plus the promos and vintage cards, at its market
    // price: what the vendors stock
    function showPool() {
        var out = [];
        Object.keys(Progress.SHOW_SETS).forEach(id => { if (!markets[id]) loadMarket(id); });
        downloadedSets().concat(Object.keys(Progress.SHOW_SETS).map(id => ({ id: id }))).forEach(s => {
            var cards = cardsOf(s.id), prices = markets[s.id] || null;
            if (!prices) {
                try { prices = (JSON.parse(host.readText(dataDir + "/market/" + s.id + ".json") || "null") || {}).prices || null; }
                catch (e) { prices = null; }
            }
            var seen = {};
            cards.forEach(c => {
                var key = s.id + ":" + c.image.split("/").pop();
                if (seen[key]) return;
                seen[key] = true;
                out.push({ key: key, value: Progress.cardValue(c, prices),
                           card: { id: c.id, name: c.name, tier: c.tier, type: c.type, image: c.image, set: s.id, origin: c.origin, character: c.character } });
            });
        });
        return out;
    }

    // K: walk into today's show (or back in, if you're there); says when the next one is otherwise
    function toggleShow() {
        if (offTheRecord) return;
        if (phase === "show") return;   // leaving is Esc, with a question first (CardShow)
        if (!(phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen || phase === "board" || phase === "port"))
            return;
        reloadProgress();
        if (!atShow) {
            if (!Progress.canEnterShow(progress, Date.now())) {
                var next = Progress.nextShowDay(progress, Date.now());
                toast(Progress.showDay(Date.now()) ? "You've been to today's card show. The next one is on " + next + "."
                                                   : "No card show today. The next one is on " + next + " (every Saturday).");
                return;
            }
            var pool = showPool();
            if (!pool.length) {
                toast("Download a set first (S): the vendors sell cards from the sets you have.");
                return;
            }
            prog(p => { Progress.enterShow(p, Date.now(), pool, vintageSealed()); return []; });
            sfx("chime");
        }
        showReturn = phase === "board" ? boardReturn : phase === "port" ? portReturn : phase;
        showRecap = null;
        phase = "show";
    }

    // buy a listing: it goes in the collection (a fake goes with the fakes, but you don't know that yet)
    function buyAtShow(id) {
        var x = prog(p => { var r = Progress.buyAtShow(p, id, Date.now()); return r ? { listing: r } : null; });
        if (!x) {
            var l = Progress.showListing(progress, id);
            if (l) toast("Not enough berries: that's " + Progress.format(Progress.showPrice(progress, l)) + ".");
            return false;
        }
        var it = x.listing, col = readCollection(), c = it.card;
        var id36 = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
        if (it.sealed) {   // Progress.buyAtShow put it with your sealed products
            prog(p => Progress.record(p, { type: "bought", count: 1, value: Progress.showState(p).bought[id].price }));
            sfx("coin");
            toast("Bought a sealed " + c.name + " for " + Progress.format(Progress.showState(progress).bought[id].price)
                  + ". It's in the port's Sealed tab.");
            return true;
        }
        if (it.fake) {
            col.fakes = col.fakes || {};
            col.fakes[id36] = { card: c, key: it.key, grade: it.grade, paid: Progress.showState(progress).bought[id].price,
                                day: Progress.showState(progress).day, vendor: (Progress.showVendor(progress, id) || {}).name || "" };
        } else if (it.grade) {
            col.graded = col.graded || {};
            col.graded[id36] = Object.assign({}, c, { key: it.key, grade: it.grade, gradedAt: Date.now(), service: "show", cond: "unchecked" });
        } else {
            var e = col.cards[it.key];
            if (!e) e = col.cards[it.key] = { id: c.id, name: c.name, tier: c.tier, count: 0, first: new Date().toISOString() };
            Progress.addCopy(e, it.cond || null);
        }
        writeCollection(col);
        prog(p => Progress.record(p, { type: "bought", count: 1, value: Progress.showState(p).bought[id].price }));
        sfx("coin");
        toast("Bought " + Tiers.displayName(c) + (it.grade ? " (graded " + it.grade + ")" : "") + " for "
              + Progress.format(Progress.showState(progress).bought[id].price));
        return true;
    }

    // leave the show: the visit's over until the next one; the recap shows what you really got
    function leaveShow() {
        var recap = null;
        prog(p => { recap = Progress.leaveShow(p, Date.now()); return recap ? recap.done : []; });
        refreshValue();
        refreshRegistry();
        showRecap = recap;
        if (!recap) phase = showReturn;
    }

    // after the recap: back to where you were
    function closeShow() {
        showRecap = null;
        phase = showReturn === "show" ? "pack" : showReturn;
        if (phase === "pack" && db && mode !== "box") newPack();
        stage.forceActiveFocus();
    }

    // a counterfeit from a show, gone for good
    function destroyFake(id) {
        var col = readCollection();
        if (!col.fakes || !col.fakes[id]) return;
        delete col.fakes[id];
        if (!Object.keys(col.fakes).length) delete col.fakes;
        writeCollection(col);
        sfx("tear");
        toast("Destroyed the fake. Good riddance.");
    }

    // open it: its boxes wait in that set's box mode
    function openSealed(id) {
        var it = prog(p => Progress.openSealed(p, id));
        if (!it) return;
        refreshValue();
        sfx("box");
        mode = "box";
        if (it.set === setId && db) {
            caseState = null;
            startBox();
        } else {
            db = null;
            loadSet(it.set);
        }
    }

    // ---- a sealed vintage pack (from a card show), opened from the port ----------------------
    // The pack goes through the usual tear and reveal; it's taken out of the sealed product
    // when it tears (so backing out before that loses nothing). After the summary, back to the port.
    property var vintageRip: null   // { id (the sealed product), origin, code } while one's on screen
    function openVintagePack(id) {
        var it = (progress.sealed || {})[id];
        if (!it || !it.vintage || offTheRecord) return;
        var cards = vintageCards().filter(c => c.origin === it.setName).map(c => Object.assign({ set: "VINTAGE" }, c));
        if (!cards.length) return;
        pack = Tiers.makeVintagePack(cards, !!it.resealed);
        var art = cards.filter(c => c.tier === "V_GOLD" || c.tier === "V_SILVER" || c.tier === "V_SR");
        packArt = art.length ? "file://" + art[Math.floor(Math.random() * art.length)].image : "";
        vintageRip = { id: id, origin: it.setName, code: it.setName === "The Quest Begins" ? "2005" : "2006" };
        packPaid = true;
        revealed = 0;
        cardsIn = false;
        inspectIndex = -1;
        phase = "pack";
        sfx("box");
    }

    // torn: out of the sealed product, into the collection; counts as a pack opened (of VINTAGE)
    function recordVintagePack() {
        var id = vintageRip.id;
        prog(p => { Progress.openVintagePack(p, id); return []; });
        packNew = pack.map(c => !collection.cards[cardKey(c)]);
        recordCards(pack);
        if (offTheRecord) return;
        var have = ownedKeys(), all = vintageCards();
        var owned = Object.keys(have).filter(k => k.indexOf("VINTAGE:") === 0).length;
        prog(p => Progress.record(p, { type: "pack", set: "VINTAGE", tiers: pack.map(c => c.tier), god: false,
                                       completion: all.length ? owned / all.length : 0, groups: {}, present: null }));
        refreshValue();
    }

    // boxes from opened sealed products go to this set's case as prepaid
    function claimPrepaid() {
        if (offTheRecord || !caseState || !(progress.prepaidBoxes || {})[setId]) return;
        var n = 0;
        prog(p => {
            n = p.prepaidBoxes[setId] || 0;
            p.prepaidBoxes[setId] = 0;
            return [];
        });
        if (!n) return;
        caseState.prepaidCost = prepaidCostSoFar() + n * boxCost;   // a sealed product's boxes: what a box goes for now
        caseState.prepaid = (caseState.prepaid || 0) + n;
        saveCase();
    }
    // what the prepaid boxes waiting cost (from before this was kept: today's box price each)
    function prepaidCostSoFar() {
        return caseState.prepaidCost !== undefined ? caseState.prepaidCost : (caseState.prepaid || 0) * boxCost;
    }

    // market prices for the current set, cached per day in market/<set>.json
    function setMarket(id, prices) {
        var m = Object.assign({}, markets);
        m[id] = prices;
        markets = m;
    }

    // market prices for a set (default: the current one), cached per day in market/<set>.json.
    // There's no public price list for Japanese cards: a Japanese set's come from its
    // English counterparts' (the same printing, so the same id and English name), scaled
    // by Progress.JP_CARD_PRICE.
    function loadMarket(id) {
        id = id || setId;
        var path = dataDir + "/market/" + id + ".json", cached = null;
        if (id === "VINTAGE") {   // no live prices for these: the app's reference prices (rewritten: the list may have changed)
            var ref = {};
            vintageCards().forEach(c => ref[c.id + "|" + c.name] = c.refUsd);
            host.writeText(path, JSON.stringify({ day: Progress.dayOf(Date.now()), prices: ref }));
            setMarket(id, ref);
            return;
        }
        try { cached = JSON.parse(host.readText(path) || "null"); } catch (e) {}
        if (cached) setMarket(id, cached.prices);
        if (cached && cached.day === Progress.dayOf(Date.now())) return;
        var info = sets[id] || {};
        var sources = info.lang === "jp" ? (info.en || []) : [id];
        var scale = info.lang === "jp" ? Progress.JP_CARD_PRICE : 1;
        var prices = {}, left = sources.length;
        sources.forEach(src => {
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                try {
                    if (xhr.status === 200) JSON.parse(xhr.responseText).forEach(c => {
                        if (c.market_price !== null && c.market_price !== undefined)
                            prices[c.card_image_id + "|" + c.card_name] = Number(c.market_price) * scale;
                    });
                } catch (e) {}
                if (--left > 0 || !Object.keys(prices).length) return;   // all in, and something came back
                host.writeText(path, JSON.stringify({ day: Progress.dayOf(Date.now()), prices: prices }));
                stage.setMarket(id, prices);
                if (!stage.offTheRecord) stage.refreshValue();
            };
            xhr.open("GET", src === "PROMO" ? "https://optcgapi.com/api/allPromos/" : "https://optcgapi.com/api/sets/" + src + "/");
            xhr.send();
        });
    }

    // sell `count` copies of these cards: [{ card, count }]; returns ฿ earned
    function sell(items) {
        if (offTheRecord || !items.length) return 0;
        var col = readCollection(), total = 0, n = 0;
        items.forEach(it => {
            var e = col.cards[cardKey(it.card)];
            if (!e) return;
            var k = Math.min(it.count, e.count);
            total += k * sellPrice(it.card);
            n += k;
            e.count -= k;
            if (e.count <= 0) delete col.cards[cardKey(it.card)];
        });
        if (!n) return 0;
        writeCollection(col);
        prog(p => {
            Progress.earn(p, total, "sell");
            return Progress.record(p, { type: "sell", count: n, value: total });
        });
        refreshValue();
        sfx("coin");
        toast("Sold " + n + " card" + (n > 1 ? "s" : "") + " for " + Progress.format(total));
        return total;
    }

    // copies past the first, of cards worth less than BULK_LIMIT, in the current set
    readonly property var bulkDuplicates: {
        var out = [];
        if (!db) return out;
        db.cards.forEach(c => {
            var e = collection.cards[cardKey(c)];
            if (e && e.count > 1 && cardValue(c) < Progress.BULK_LIMIT) out.push({ card: c, count: e.count - 1 });
        });
        return out;
    }
    readonly property int bulkValue: bulkDuplicates.reduce((a, it) => a + it.count * cardValue(it.card), 0)

    function downloaded(id) {
        return host.readText(cacheRoot + "/" + id + "/cards.json") !== "";
    }

    // load a set's card data (downloading it first if needed) and start a
    // pack or a box, by mode
    function loadSet(id, afterDownload) {
        setId = id;
        caseState = null;
        var text = host.readText(cacheDir + "/cards.json");
        if (!text && !afterDownload) {
            downloadSet(id);
            return;
        }
        if (!text) {
            error = "Couldn't download " + id + ". Check your connection, or run ~/.config/quickshell/optcg/fetch_cards.py " + id;
            phase = "error";
            return;
        }
        try {
            db = JSON.parse(text);
        } catch (e) {
            error = "cards.json is unreadable: " + e;
            phase = "error";
            return;
        }
        saveSettings({ set: id });
        if (afterDownload && allCards) loadAllCards();   // its collections join the rest
        loadMarket();
        loadAllMarkets();   // slabs and cards from other sets are priced from theirs
        if (mode === "box") startBox();
        else newPack();
    }

    function downloadSet(id) {
        setId = id;
        db = null;
        downloadLine = "";
        phase = "downloading";
        host.run([python, "-I", "-u", fetchScript, id],
                 line => downloadLine = line,
                 code => loadSet(id, true));
    }

    function toggleAllSets() {   // the binder's "This set" / "All sets"
        if (phase === "binder") binderView.allSets = !binderView.allSets;
    }

    function toggleBoard() {
        if (noPeeking()) return;
        if (phase === "board") {
            phase = boardReturn;
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen) {
            reloadProgress();
            boardReturn = phase;
            phase = "board";
        }
    }

    function togglePort() {
        if (noPeeking()) return;
        if (phase === "port") {
            phase = portReturn;
            stage.forceActiveFocus();
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen || phase === "board") {
            reloadProgress();
            collectGrading();
            portReturn = phase === "board" ? boardReturn : phase;
            phase = "port";
        }
    }
    property string portReturn: "pack"

    function toggleVault() {
        if (noPeeking()) return;
        if (phase === "vault") {
            phase = vaultReturn;
            stage.forceActiveFocus();
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen
                   || phase === "board" || phase === "port" || phase === "binder") {
            reloadProgress();
            collectGrading();
            loadAllMarkets();
            vaultReturn = phase === "board" ? boardReturn : phase === "port" ? portReturn : phase;
            phase = "vault";
        }
    }
    property string vaultReturn: "pack"

    function toggleSync() {
        if (phase === "sync") {
            phase = syncReturn;
            stage.forceActiveFocus();
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen || phase === "board") {
            syncReturn = phase === "board" ? boardReturn : phase;
            phase = "sync";
        }
    }
    property string syncReturn: "pack"

    function toggleSets() {
        if (noPeeking()) return;
        if (phase === "sets") {
            phase = pickerReturn;
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen) {
            pickerReturn = phase;
            phase = "sets";
        }
    }

    // kind: "pack" (from the shop counter) | "box" (from the shelf); left out, the mode stays
    function chooseSet(id, kind) {
        var switching = !!kind && kind !== mode;
        if (kind) mode = kind;
        if (id === setId && db && db.set === id) {
            if (!switching) phase = pickerReturn;
            else if (mode === "box") startBox();
            else newPack();
            return;
        }
        db = null;
        loadSet(id);
    }

    function switchMode() {
        if (!db || charging || !((phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen)) return;
        if (mode === "box") {
            mode = "pack";
            newPack();
        } else {
            mode = "box";
            startBox();
        }
    }

    // card key -> card, to turn a saved case back into cards
    readonly property var cardByKey: {
        var map = {};
        if (db) db.cards.forEach(c => map[cardKey(c)] = c);
        return map;
    }

    function saveCase() {
        caseState.opened = boxOpened;
        host.writeText(casePath, JSON.stringify(caseState));
        caseRev++;
    }

    function newCase() {
        caseState = {
            set: setId,
            box: 0,
            opened: [],
            boxPaid: false,
            boxRecorded: false,
            prepaid: caseState ? caseState.prepaid || 0 : 0,   // boxes from a sealed case carry over
            prepaidCost: caseState ? prepaidCostSoFar() : 0,
            topperTaken: false,
            toppers: [],
            boxes: []
        };
        var dealt = Tiers.makeCase(db.cards, setInfo, Progress.packOptions(progress, setId));
        caseState.boxes = dealt.boxes.map(box => box.map(p => p.map(c => cardKey(c))));
        caseState.toppers = dealt.toppers.map(c => c ? cardKey(c) : null);
    }

    // resume the saved case (unfinished box first), or deal a new one
    function startBox() {
        if (!caseState) {
            try {
                caseState = JSON.parse(host.readText(casePath));
                if (caseState.set !== setId || caseState.boxes.length !== cfg.boxes) caseState = null;
            } catch (e) {
                caseState = null;
            }
        }
        if (!caseState) newCase();
        var done = caseState.opened.length === cfg.packsPerBox && caseState.opened.every(o => o);
        if (done) {
            caseState.box++;
            caseState.opened = [];
            caseState.topperTaken = false;
            caseState.boxPaid = false;
            delete caseState.boxPrice;
            caseState.boxRecorded = false;
            if (caseState.box >= cfg.boxes) newCase();
        }
        claimPrepaid();
        boxIndex = caseState.box;
        var packs = caseState.boxes[boxIndex].map(p => p.map(k => cardByKey[k]));
        if (packs.some(p => p.some(c => !c))) {   // card data changed under the case
            newCase();
            boxIndex = 0;
            packs = caseState.boxes[0].map(p => p.map(k => cardByKey[k]));
        }
        boxPacks = packs;
        boxOpened = caseState.opened.length ? caseState.opened : packs.map(() => false);
        boxTopper = caseState.toppers && caseState.toppers[boxIndex] ? cardByKey[caseState.toppers[boxIndex]] || null : null;
        topperTaken = !!caseState.topperTaken;
        saveCase();
        inspectIndex = -1;
        cardsIn = false;
        phase = boxOpened.some(o => o) ? "boxGrid" : "boxSealed";
    }

    function openBoxPack(i) {
        if (i < 0 || boxOpened[i]) return;
        currentPackIdx = i;
        pack = boxPacks[i];
        packNew = [];
        revealed = 0;
        cardsIn = false;
        inspectIndex = -1;
        phase = "pack";
    }

    function nextUnopened() {
        return boxOpened.indexOf(false);
    }

    function backToBox() {
        currentPackIdx = -1;
        if (nextUnopened() < 0) {
            recordBoxDone();
            phase = "boxSummary";
        } else {
            phase = "boxGrid";
        }
    }

    function openAllRemaining() {
        if (phase !== "boxGrid") return;
        // all of them at once: one collection write and one progress update, not one per pack
        var opened = boxOpened.slice(), packs = boxPacks.filter((p, i) => !opened[i]);
        recordCards([].concat.apply([], packs), packs.length);
        recordPacksProgress(packs);
        boxOpened = opened.map(() => true);
        saveCase();
        recordBoxDone();
        phase = "boxSummary";
    }

    // The sealed single pack waiting in each set, saved (pending-packs.json, per computer:
    // { set: [card key] }) until it's torn open, so closing the app, switching sets or
    // modes and coming back brings back the same pack: Robin's reading of it holds.
    readonly property string pendingPath: dataDir + "/pending-packs.json"
    function readPending() {
        try { return JSON.parse(host.readText(pendingPath) || "{}"); } catch (e) { return {}; }
    }
    function savePending(cards) {
        if (offTheRecord) return;
        var all = readPending();
        if (cards) all[setId] = cards.map(c => cardKey(c));
        else delete all[setId];
        host.writeText(pendingPath, JSON.stringify(all));
    }
    function pendingPack() {
        if (offTheRecord) return null;
        var keys = readPending()[setId];
        if (!keys || !keys.length) return null;
        var cards = keys.map(k => cardByKey[k]);
        return cards.every(c => c) ? cards : null;   // card data changed: deal a new one
    }

    function newPack() {
        vintageRip = null;
        var leaders = db.cards.filter(c => c.tier === "L");
        packArt = leaders.length ? "file://" + leaders[Math.floor(Math.random() * leaders.length)].image : "";
        var waiting = pendingPack();
        pack = waiting || Tiers.makePack(db.cards, setInfo, forceHit, Progress.packOptions(progress, setId));
        if (!waiting) savePending(pack);
        packPaid = false;
        revealed = 0;
        cardsIn = false;
        inspectIndex = -1;
        phase = "pack";
        packsOpened++;
    }

    function advance() {
        if (charging) return;
        if (phase === "showcaseView") {
            close();
            return;
        }
        if (phase === "boxSealed") {
            if (!payForBox()) return;
            phase = "boxGrid";
            sfx("box");
            if (boxTopper && !topperTaken) {   // the box topper comes off first
                recordCards([boxTopper]);
                topperTaken = true;
                caseState.topperTaken = true;
                saveCase();
                boxView.inspected = boxTopper;
            }
        } else if (phase === "boxGrid") {
            openBoxPack(nextUnopened());
        } else if (phase === "boxSummary") {
            startBox();
        } else if (phase === "pack") {
            if (cardsIn || !packLoader.item) return;
            if (mode !== "box" && !payForPack()) return;
            packLoader.item.tear();
        } else if (phase === "reveal") {
            if (revealed >= pack.length) {
                phase = "summary";
            } else if (nextTier.rank >= 4) {
                charging = true;   // build suspense before a big card
                sfx("charge");
                chargeTimer.start();
            } else {
                revealed++;
                sfx("flip");
            }
        } else if (phase === "summary") {
            if (inspectIndex >= 0) inspectIndex = -1;
            else if (vintageRip) { vintageRip = null; phase = "port"; }   // back to the sealed products
            else if (mode === "box") backToBox();
            else newPack();
        }
    }

    function revealAll() {
        if (phase === "reveal" && !charging) {
            var best = pack.slice(revealed).reduce((a, c) => Math.max(a, Tiers.tierOf(c).rank), -1);
            revealed = pack.length;
            phase = "summary";
            sfx(revealSound({ rank: best }) || "flip");
        }
    }

    function cardKey(c) {
        // unique per printing; cards from the all-sets binder carry their own set
        return (c.set || setId) + ":" + c.image.split("/").pop();
    }

    // a card with its picture in this device's cache: slabs and grading orders
    // synced from another device carry that device's path
    function localCard(c) {
        var k = c.key || cardKey(c), cut = k.indexOf(":");
        return Object.assign({}, c, { image: cacheRoot + "/" + k.slice(0, cut) + "/" + k.slice(cut + 1) });
    }

    // ---- the whole collection, across sets (the binder's "All sets" view) --------------

    // every owned printing as a card: { id, name, tier, type, image, set }, plus its count
    // graded slabs by card key, best grade first: { "<set>:<file>": [slab, ...] }
    readonly property var slabsByKey: {
        var out = {}, g = collection.graded || {};
        Object.keys(g).forEach(id => {
            var s = Object.assign({ slabId: id }, localCard(g[id]));
            var k = s.key || (s.set + ":" + (s.image || "").split("/").pop());
            (out[k] = out[k] || []).push(s);
        });
        Object.keys(out).forEach(k => out[k].sort((a, b) => b.grade - a.grade));
        return out;
    }

    // how many copies of a card you have: { raw, graded } (slabs in display cases count)
    function ownedCount(key) {
        var e = collection.cards[key];
        return { raw: e ? e.count || 0 : 0, graded: (slabsByKey[key] || []).length };
    }

    // every card you have, raw or graded (for completion and the binder)
    function ownedKeys() {
        var out = Object.assign({}, collection.cards);
        Object.keys(slabsByKey).forEach(k => { if (!out[k]) out[k] = { count: 0 }; });
        return out;
    }

    // every owned printing as a card, with its raw count and its slabs; a card
    // you only have graded is still yours (count 0, slabs)
    readonly property var allOwned: {
        var out = [], seen = {};
        var add = (k, e) => {
            var cut = k.indexOf(":"), set = k.slice(0, cut);
            seen[k] = true;
            out.push({ card: { id: e.id, name: e.name, tier: e.tier, set: set,
                               type: e.tier && e.tier.indexOf("DON") === 0 ? "DON!!" : (e.tier === "L" || e.tier === "L_AA" || e.tier === "SUPER_L" ? "Leader" : ""),
                               image: cacheRoot + "/" + set + "/" + k.slice(cut + 1) },
                       count: e.count || 0, slabs: slabsByKey[k] || [] });
        };
        Object.keys(collection.cards).forEach(k => add(k, collection.cards[k]));
        Object.keys(slabsByKey).forEach(k => { if (!seen[k]) add(k, slabsByKey[k][0]); });
        return out;
    }

    // spare copies worth under BULK_LIMIT, in every set
    readonly property var allBulkDuplicates: allOwned.filter(it => it.count > 1 && cardValue(it.card) < Progress.BULK_LIMIT)
                                                     .map(it => ({ card: it.card, count: it.count - 1 }))
    readonly property int allBulkValue: allBulkDuplicates.reduce((a, it) => a + it.count * cardValue(it.card), 0)

    function loadAllMarkets() {
        var seen = {};
        allOwned.forEach(it => seen[it.card.set] = true);
        Object.keys(seen).forEach(id => { if (!markets[id]) loadMarket(id); });
    }

    function recordPack() {
        if (vintageRip) return recordVintagePack();
        if (mode !== "box") savePending(null);   // opened: the next one is dealt fresh
        packNew = pack.map(c => !collection.cards[cardKey(c)]);
        recordCards(pack);
        recordPackProgress(pack);
        if (!offTheRecord) refreshValue();
        if (mode === "box" && currentPackIdx >= 0) {
            var opened = boxOpened.slice();
            opened[currentPackIdx] = true;
            boxOpened = opened;
            saveCase();
        }
    }

    // packs: how many packs these cards came from (1 unless given)
    function recordCards(cards, packs) {
        if (offTheRecord) return;   // forced pulls / sandbox don't go in the binder
        var col = readCollection();
        cards.forEach(c => {
            var e = col.cards[cardKey(c)];
            if (e) e.count++;
            else col.cards[cardKey(c)] = { id: c.id, name: c.name, tier: c.tier, count: 1, first: new Date().toISOString() };
        });
        col.packs = (col.packs || 0) + (packs === undefined ? 1 : packs);
        writeCollection(col);
    }

    function toggleBinder() {
        if (noPeeking()) return;
        if (phase === "binder") {
            phase = binderReturn;
        } else if ((phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen) {
            binderReturn = phase;
            phase = "binder";
        }
    }

    // ---- desktop showcase ----------------------------------------------------

    // the card you're looking at: inspected in the binder / summary / box, or
    // the one just revealed
    function focusedCard() {
        if (phase === "binder") return binderView.inspected || binderView.hoveredCard;
        if (inBoxScreen) return boxView.inspected;
        if (phase === "summary" && inspectIndex >= 0) return pack[inspectIndex];
        if (phase === "reveal" && revealed > 0 && !charging) return pack[revealed - 1];
        return null;
    }

    function showcase(c) {
        if (!c) return;
        var path = dataDir + "/showcase.json", s = {};
        try { s = JSON.parse(host.readText(path) || "{}"); } catch (e) {}
        s.card = { id: c.id, name: c.name, tier: c.tier, type: c.type, image: c.image, set: c.set || setId };
        if (c.grade) s.card.grade = c.grade;   // a graded slab: its grade goes on the label
        if (c.diamond) s.card.diamond = true;
        host.writeText(path, JSON.stringify(s));
        host.startShowcase();
        toast("Showing " + Tiers.displayName(c) + " on your desktop  ·  drag to move, scroll to resize, right-click to remove");
    }

    // ---- the showcased card, big (double-click on the desktop widget) ------------------
    property var viewCard: null
    property real viewPrice: -1

    function openShowcaseView() {
        try {
            viewCard = JSON.parse(host.readText(dataDir + "/showcase.json") || "{}").card || null;
        } catch (e) {
            viewCard = null;
        }
        if (!viewCard) return false;
        var set = viewCard.set || ((viewCard.image || "").match(/optcg\/([^/]+)\//) || [])[1] || "";
        try {
            var hist = JSON.parse(host.readText(dataDir + "/prices.json") || "{}")[set + ":" + viewCard.image.split("/").pop()] || [];
            viewPrice = hist.length ? hist[hist.length - 1].p : -1;
        } catch (e) {}
        phase = "showcaseView";
        return true;
    }

    property string toastText: ""
    function toast(text) {
        toastText = text;
        toastTimer.restart();
    }
    Timer {
        id: toastTimer
        interval: 4000
        onTriggered: stage.toastText = ""
    }

    function close() {
        fadeIn.stop();
        closeAnim.start();
    }

    // position/scale/z for card i in the current phase
    function layout(i) {
        var W = cw, H = cw / 0.716, cx = width / 2, cy = height / 2 - 40;
        if (phase === "summary") {
            if (i === inspectIndex)
                return { x: cx, y: height / 2, s: Math.min(1.5, height * 0.86 / H), z: 200 };
            var gx = 28, gy = 40;
            var s = Math.min(0.55, height * 0.34 / H, (width * 0.9 - 5 * gx) / 6 / W);
            var w = W * s, h = H * s;
            var totalW = 6 * w + 5 * gx, totalH = 2 * h + gy;
            var col = i % 6, row = Math.floor(i / 6);
            return { x: cx - totalW / 2 + col * (w + gx) + w / 2,
                     y: height / 2 + 20 - totalH / 2 + row * (h + gy) + h / 2, s: s, z: i };
        }
        if (phase === "pack" || i >= revealed) {
            var rise = cardsIn ? 0 : height * 0.35;
            // the tease: the last card peeks out from behind the stack, back
            // showing (red = Leader, green = DON!!) until it's next up
            if (i === pack.length - 1 && i > revealed)
                return { x: cx + W * 0.24, y: cy + H * 0.03 + rise, s: 1, z: 20, r: 9 };
            var d = i - revealed;
            return { x: cx + d * 1.2, y: cy + d * 1.5 + rise, s: 1, z: i === revealed ? 90 : 50 - i };
        }
        // while charging, the last card moves aside so the shaking one is visible
        if (i === revealed - 1 && !charging)
            return { x: cx, y: cy, s: 1, z: 100 };
        var gap = 12;
        var s2 = Math.min(0.3, (width * 0.92 - 11 * gap) / 12 / W);
        var w2 = W * s2, h2 = H * s2, tot = 12 * w2 + 11 * gap;
        return { x: cx - tot / 2 + i * (w2 + gap) + w2 / 2, y: height - 28 - h2 / 2, s: s2, z: 10 + i };
    }

    Keys.onPressed: event => {
        if (phase === "sync" && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Y) return;   // typing in the account screen
        switch (event.key) {
        case Qt.Key_Escape:
            if (phase === "binder") binderView.back();
            else if (phase === "sets") toggleSets();
            else if (phase === "board") toggleBoard();
            else if (phase === "sync") toggleSync();
            else if (phase === "port") portView.back();
            else if (phase === "vault") vaultView.back();
            else if (phase === "show") showView.back();
            else if (inBoxScreen && boxView.inspected) boxView.inspected = null;
            else if (mode === "box" && phase === "pack" && !cardsIn) backToBox();
            else if (inspectIndex >= 0) inspectIndex = -1;
            else close();
            break;
        case Qt.Key_B:
            toggleBinder();
            break;
        case Qt.Key_O:
            if (phase === "binder") binderView.toggleOwned();
            break;
        case Qt.Key_Left:
            if (phase === "vault") vaultView.step(-1);
            else if (phase === "port") portView.step(-1);
            else if (phase === "board") boardView.step(-1);
            else return;
            break;
        case Qt.Key_Right:
            if (phase === "vault") vaultView.step(1);
            else if (phase === "port") portView.step(1);
            else if (phase === "board") boardView.step(1);
            else advance();
            break;
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            advance();
            break;
        case Qt.Key_Tab:
            if (phase === "binder") toggleAllSets();
            else revealAll();
            break;
        case Qt.Key_R:
            if (phase === "summary") mode === "box" ? backToBox() : newPack();
            break;
        case Qt.Key_A:
            openAllRemaining();
            break;
        case Qt.Key_X:
            switchMode();
            break;
        case Qt.Key_W:
            toggleBoard();
            break;
        case Qt.Key_Y:
            toggleSync();
            break;
        case Qt.Key_M:
            toggleMute();
            break;
        case Qt.Key_U:
            updateButton();
            break;
        case Qt.Key_P:
            togglePort();
            break;
        case Qt.Key_G:
            toggleVault();
            break;
        case Qt.Key_K:
            toggleShow();
            break;
        case Qt.Key_F:
            if (phase === "binder") binderView.filtersOpen = !binderView.filtersOpen;
            else return;
            break;
        case Qt.Key_C:
            buyCase();
            break;
        case Qt.Key_S:
            toggleSets();
            break;
        case Qt.Key_D:
            showcase(focusedCard());
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ---- backdrop -------------------------------------------------------

    // the backdrop is a cosmetic (the Port); playmats are downloaded the first time they're
    // needed, except the ones that come with the app (playmat.file, in app/)
    readonly property var backdrop: Progress.backdrop(progress)
    property int playmatVersion: 0          // bumped when a playmat picture arrives
    property var playmatTried: ({})
    function playmatUrl(item) {
        if (item && item.playmat && item.playmat.file) return Qt.resolvedUrl(item.playmat.file);
        return item && item.playmat ? "file://" + cacheRoot + "/playmats/" + item.id + ".img?v=" + playmatVersion : "";
    }
    function fetchPlaymat(item) {
        if (!item || !item.playmat || item.playmat.file || playmatTried[item.id]) return;
        playmatTried[item.id] = true;
        host.run([python, "-I", "-u", fetchScript, "--playmat", item.id, String(item.playmat.tcg || ""), item.playmat.page || ""],
                 null, code => playmatVersion++);
    }
    Rectangle {
        anchors.fill: parent
        color: stage.backdrop.base
        opacity: 0.78
        Behavior on color { ColorAnimation { duration: 400 } }
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(parent.width, parent.height) * 1.3
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.5; color: stage.backdrop.glow }
            GradientStop { position: 1.0; color: "#00000000" }
        }
        opacity: 0.6
    }
    // a playmat backdrop: the picture, darkened so the cards stay readable
    Image {
        id: playmatBackdrop
        anchors.fill: parent
        visible: !!stage.backdrop.playmat && status === Image.Ready
        source: stage.playmatUrl(stage.backdrop)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: if (status === Image.Error) stage.fetchPlaymat(stage.backdrop)
    }
    Rectangle {
        anchors.fill: parent
        visible: playmatBackdrop.visible
        color: "#05070d"
        opacity: 0.5
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? stage.close() : stage.advance()
    }

    // ---- pack ------------------------------------------------------------

    Loader {
        id: packLoader
        anchors.centerIn: parent
        active: stage.phase === "pack" && stage.db !== null
        z: 40
        sourceComponent: Pack {
            height: stage.height * 0.66
            width: height * stage.packAspect
            time: stage.t
            packImage: stage.vintageRip ? "" : stage.packImage   // a vintage pack: drawn
            artSource: stage.packArt
            setCode: stage.vintageRip ? stage.vintageRip.code : stage.db.set
            setName: stage.vintageRip ? stage.vintageRip.origin : stage.db.set_name
            cardCount: stage.vintageRip ? stage.pack.length : 12
            onTearStarted: {
                stage.cardsIn = true;
                stage.sfx("tear");
            }
            onTapped: stage.advance()
            onTorn: {
                stage.recordPack();
                stage.phase = "reveal";
                if (stage.godPack) {
                    flashAnim.restart();
                    godAnim.restart();
                    stage.sfx("god");
                }
            }
        }
    }

    // ---- hit effects -----------------------------------------------------

    // a god pack: announced as soon as it's torn open, and stays up
    Column {
        id: godBanner
        z: 285
        visible: stage.godPack !== "" && (stage.phase === "reveal" || stage.phase === "summary")
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.06
        spacing: 2
        Text {
            id: godTitle
            anchors.horizontalCenter: parent.horizontalCenter
            text: "✦  " + stage.godPack.toUpperCase() + "  ✦"
            color: "#ffd700"
            style: Text.Outline; styleColor: "#5a3a00"
            font { pixelSize: 44; weight: Font.Black; italic: true; letterSpacing: 3 }
            SequentialAnimation on opacity {
                running: godBanner.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.7; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "every card is a hit  ·  about 1 pack in " + Math.round(stage.cfg.packsPerCase / Tiers.godPacksPerCase(stage.setInfo)).toLocaleString(Qt.locale("en_US"), "f", 0)
            color: "#fff6e0"
            style: Text.Outline; styleColor: "#000000"
            font { pixelSize: 16; weight: Font.Bold }
        }
    }
    SequentialAnimation {
        id: godAnim
        NumberAnimation { target: godTitle; property: "scale"; from: 0.2; to: 1.3; duration: 380; easing.type: Easing.OutBack }
        NumberAnimation { target: godTitle; property: "scale"; to: 1; duration: 260 }
    }

    ShaderEffect {
        id: rays
        readonly property bool showing: stage.charging || (stage.phase === "reveal" && stage.centerTier.rank >= 4)
        width: stage.cw * 3.4
        height: width
        x: stage.width / 2 - width / 2
        y: stage.height / 2 - 40 - height / 2
        z: 75
        opacity: showing ? (stage.charging ? 0.55 : 1) : 0
        scale: showing ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        visible: opacity > 0
        property real time: stage.t
        property color color: stage.charging ? stage.nextTier.color : stage.centerTier.color
        fragmentShader: Qt.resolvedUrl("shaders/rays.frag.qsb")
    }

    SequentialAnimation on shake {
        running: stage.charging
        loops: Animation.Infinite
        NumberAnimation { to: 7; duration: 40 }
        NumberAnimation { to: -7; duration: 80 }
        NumberAnimation { to: 0; duration: 40 }
        onRunningChanged: if (!running) stage.shake = 0
    }

    Timer {
        id: chargeTimer
        interval: 1100
        onTriggered: {
            stage.charging = false;
            stage.revealed++;
            stage.sfx(stage.revealSound(stage.centerTier));
            if (stage.centerTier.rank >= 6) flashAnim.restart();
            popAnim.restart();
        }
    }

    // ---- cards -----------------------------------------------------------

    Repeater {
        model: stage.pack
        delegate: Card {
            id: cardItem
            required property var modelData
            required property int index
            readonly property var slot: stage.layout(index)
            readonly property bool chargingMe: stage.charging && index === stage.revealed

            card: modelData
            backSource: Tiers.isVintage(modelData) ? stage.vintageBack
                      : modelData.type === "Leader" ? stage.leaderBack
                      : modelData.type === "DON!!" ? stage.donBack : stage.deckBack
            width: stage.cw
            time: stage.t
            x: slot.x - width / 2 + (chargingMe ? stage.shake : 0)
            y: slot.y - height / 2
            z: slot.z
            scale: slot.s
            rotation: slot.r || 0
            faceUp: stage.phase !== "pack" && index < stage.revealed
            sway: stage.phase === "reveal" && index === stage.revealed - 1
            hoverTilt: stage.phase === "summary"
            opacity: !stage.cardsIn || stage.phase === "binder" || stage.phase === "sets" || stage.inBoxScreen ? 0
                     : (stage.inspectIndex >= 0 && stage.inspectIndex !== index ? 0.25 : 1)
            onClicked: stage.inspectIndex = stage.inspectIndex === index ? -1 : index

            Behavior on x { enabled: !cardItem.chargingMe; NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            Behavior on rotation { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }

            // rarity tag under each summary card
            Text {
                visible: stage.phase === "summary" && stage.inspectIndex < 0
                anchors.top: parent.bottom
                anchors.topMargin: 6 / Math.max(0.01, cardItem.scale)
                anchors.horizontalCenter: parent.horizontalCenter
                text: (stage.packNew[cardItem.index] ? "NEW · " : "") + cardItem.tier.label
                color: cardItem.tier.color
                font { pixelSize: 15 / Math.max(0.01, cardItem.scale); weight: Font.Bold }
            }
        }
    }

    // ---- text ------------------------------------------------------------

    Column {
        id: banner
        z: 150
        visible: stage.phase === "reveal" && stage.revealed > 0 && !stage.charging
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height / 2 - 40 + stage.cw / 0.716 / 2 + 14
        spacing: 2
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!stage.packNew[stage.revealed - 1]
            width: newText.width + 16
            height: newText.height + 4
            radius: height / 2
            color: "#ff4d6d"
            Text {
                id: newText
                anchors.centerIn: parent
                text: "NEW!"
                color: "white"
                font { pixelSize: 13; weight: Font.Black; letterSpacing: 1 }
            }
        }
        Text {
            id: tierLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.centerTier.rank >= 4 ? stage.centerTier.label.toUpperCase() + "!" : stage.centerTier.label
            color: stage.centerTier.color
            style: Text.Outline; styleColor: "#000000"
            font { pixelSize: stage.centerTier.rank >= 4 ? 34 : 20; weight: Font.Black; italic: stage.centerTier.rank >= 4 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.revealed > 0 ? Tiers.displayName(stage.pack[stage.revealed - 1]) + "  ·  " + stage.pack[stage.revealed - 1].id : ""
            color: "#e8e8ee"
            font.pixelSize: 15
        }
    }
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: tierLabel; property: "scale"; from: 0.4; to: 1.25; duration: 220; easing.type: Easing.OutBack }
        NumberAnimation { target: tierLabel; property: "scale"; to: 1; duration: 200 }
    }

    Column {
        z: 150
        visible: stage.phase === "summary" && stage.inspectIndex < 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.06
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.db ? stage.db.set + "  ·  " + stage.db.set_name : ""
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var best: stage.pack.length ? Tiers.best(stage.pack) : null
            text: !best ? ""
                  : "Best pull: " + Tiers.displayName(best) + " (" + Tiers.tierOf(best).label + ")   ·   "
                    + (stage.mode === "box" ? "box " + (stage.boxIndex + 1) + " of " + stage.cfg.boxes + ", "
                                              + stage.boxOpened.filter(o => o).length + " / " + stage.boxPacks.length + " packs opened"
                                            : "packs opened: " + stage.packsOpened)
            color: "#d0d4dc"
            font.pixelSize: 16
        }
    }

    Text {
        z: 150
        visible: stage.phase === "summary" && stage.inspectIndex >= 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        readonly property var c: stage.inspectIndex >= 0 ? stage.pack[stage.inspectIndex] : null
        text: c ? Tiers.displayName(c) + "  ·  " + c.id + "  ·  " + Tiers.tierOf(c).label : ""
        color: c ? Tiers.tierOf(c).color : "white"
        style: Text.Outline; styleColor: "#000000"
        font { pixelSize: 20; weight: Font.Bold }
    }

    Text {
        z: 150
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: stage.phase === "reveal" ? stage.cw / 0.716 * 0.3 + 44 : 14
        color: "#9aa0ad"
        font.pixelSize: 14
        text: ({
            loading: "Loading cards…",
            error: "S: choose another set   ·   Esc to close",
            pack: stage.mode === "box" ? "Click or Space to tear it open   ·   Esc: back to the box"
                  : "Click or Space to tear it open   ·   X: open a box   ·   S: sets   ·   B: binder   ·   W: wanted board   ·   P: port   ·   Esc to close",
            binder: "",
            boxSealed: "",
            showcaseView: "Move the mouse to tilt   ·   click, Space or Esc to close",
            board: "",
            port: "",
            vault: "",
            show: "",
            sync: "",
            sets: "",
            downloading: "",
            boxGrid: "",
            boxSummary: "",
            reveal: "Space / click: next card   ·   Tab: reveal all   ·   D: show on desktop   ·   Esc: close",
            summary: stage.inspectIndex >= 0 ? "Move the mouse to tilt   ·   D: show on desktop   ·   click or Esc to go back"
                     : stage.mode === "box" ? "Hover to tilt   ·   click a card to inspect   ·   Space: back to the box   ·   B: binder   ·   Esc: close"
                     : "Hover to tilt   ·   click a card to inspect   ·   Space: open another pack   ·   X: open a box   ·   S: sets   ·   B: binder   ·   W: wanted board   ·   Esc: close"
        })[stage.phase]
    }

    Text {
        z: 150
        visible: stage.phase === "error"
        anchors.centerIn: parent
        text: stage.error
        color: "#ff8080"
        font.pixelSize: 20
    }

    Column {
        z: 150
        visible: stage.phase === "downloading"
        anchors.centerIn: parent
        spacing: 14
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Downloading " + stage.setId + (stage.setInfo.name ? "  ·  " + stage.setInfo.name : "")
            color: "#ffd56b"
            font { pixelSize: 26; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.downloadLine || "Starting…"
            color: "#c8ccd6"
            font.pixelSize: 15
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "card images (~40 MB) go to ~/.cache/optcg, once per set"
            color: "#7a8090"
            font.pixelSize: 13
        }
    }

    // the showcased card, big
    Card {
        z: 150
        visible: stage.phase === "showcaseView"
        anchors.centerIn: parent
        width: Math.min(440, stage.height * 0.78 * 0.716)
        card: stage.viewCard
        faceUp: true
        hoverTilt: true
        time: stage.t
        onClicked: stage.close()
    }
    Column {
        z: 150
        visible: stage.phase === "showcaseView" && !!stage.viewCard
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.04
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.viewCard ? Tiers.displayName(stage.viewCard) : ""
            color: "#fff6e0"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !stage.viewCard ? "" : stage.viewCard.id + "   ·   " + Tiers.tierOf(stage.viewCard).label
                  + (stage.viewPrice >= 0 ? "   ·   $" + stage.viewPrice.toFixed(2) + " market" : "")
            color: Tiers.tierOf(stage.viewCard).color
            font { pixelSize: 17; weight: Font.Bold }
        }
    }

    // ---- progression on screen ----------------------------------------------------------

    // wallet, top left
    Row {
        z: 280
        visible: stage.phase !== "loading" && stage.phase !== "showcaseView" && stage.phase !== "downloading"
        x: 22
        y: 16
        spacing: 18
        Text {
            visible: stage.offTheRecord
            text: stage.sandbox ? "SANDBOX: free, nothing is saved" : "FORCED PULLS: nothing is saved"
            color: "#ff9a7a"
            font { pixelSize: 15; weight: Font.Black }
        }
        Text {
            visible: !stage.offTheRecord
            text: Progress.format(stage.progress.berries)
            color: "#ffd56b"
            font { pixelSize: 20; weight: Font.Black }
        }
        Text {
            visible: !stage.offTheRecord
            anchors.baseline: parent.children[1].baseline
            text: stage.progress.freePacks > 0
                  ? stage.progress.freePacks + " free pack" + (stage.progress.freePacks > 1 ? "s" : "")
                  : "next free pack in " + Math.ceil(Progress.nextFreePackIn(stage.progress, Date.now()) / 3600000) + "h"
            color: stage.progress.freePacks > 0 ? "#7fd1b9" : "#9aa0ad"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Text {
            visible: !stage.offTheRecord && stage.progress.streak.count > 0
            anchors.baseline: parent.children[1].baseline
            text: "day " + stage.progress.streak.count + " streak"
            color: "#ffb347"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Text {
            visible: !stage.offTheRecord
            anchors.baseline: parent.children[1].baseline
            text: "bounty " + Progress.formatBounty(Progress.totalBounty(stage.progress)) + "   (W)   ·   port (P)   ·   vault (G)"
                  + (Progress.canEnterShow(stage.progress, Date.now()) ? "   ·   card show today (K)" : "")
                  + (Progress.currentEvent(stage.progress) ? "   ·   this week: " + Progress.currentEvent(stage.progress).name : "")
            color: "#c8ccd6"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Text {
            visible: !stage.offTheRecord
            anchors.baseline: parent.children[1].baseline
            text: "+" + Progress.format(Progress.incomePerMinute(stage.progress)) + "/min while active"
            color: "#c8ccd6"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Text {
            visible: !stage.offTheRecord
            anchors.baseline: parent.children[1].baseline
            text: (stage.syncOn ? "sync: " + stage.syncStatus : "sync: off") + "   (Y)"
            color: stage.syncOn ? (stage.syncStatus.indexOf("synced") === 0 ? "#7fd1b9" : "#ff9a7a") : "#7a8090"
            font { pixelSize: 14; weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: stage.toggleSync()
            }
        }
        Text {
            visible: !stage.offTheRecord
            anchors.baseline: parent.children[1].baseline
            text: stage.muted ? "sound off  (M)" : "sound on  (M)"
            color: stage.muted ? "#7a8090" : "#c8ccd6"
            font { pixelSize: 14; weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: stage.toggleMute()
            }
        }
        Text {
            visible: stage.canUpdate
            anchors.baseline: parent.children[1].baseline
            readonly property string s: stage.updateState
            text: s === "available" ? "update to " + stage.updateLatest + "  (U)"
                  : s === "checking" ? "checking for updates..."
                  : s === "updating" ? "updating to " + stage.updateLatest + "..."
                  : s === "updated" ? "updated to " + stage.updateLatest + ": reopen to use it"
                  : s === "failed" ? "update failed: try again  (U)"
                  : s === "upToDate" ? stage.updateHave + ", up to date  (U)"
                  : "check for updates  (U)"
            color: s === "available" ? "#ffd56b" : s === "updated" ? "#7fd1b9" : s === "failed" ? "#ff9a7a" : "#7a8090"
            font { pixelSize: 14; weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: stage.updateButton()
            }
        }
    }

    // Robin reads the sealed pack (a crew perk)
    Text {
        z: 150
        visible: stage.phase === "pack" && !stage.cardsIn && !stage.offTheRecord && Progress.hasCrew(stage.progress, "robin") && stage.pack.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.875 + 30
        readonly property int best: stage.pack.reduce((a, c) => Math.max(a, Tiers.tierOf(c).rank), 0)
        text: "Robin: " + (stage.godPack ? "\"...every page of this one glows. I've never seen anything like it.\""
                           : best >= 10 ? "\"This one holds a treasure. A real one.\""
                           : best >= 6 ? "\"Something special is in here.\""
                           : best >= 4 ? "\"There's a Super Rare or better in here.\""
                           : "\"Nothing remarkable, I'm afraid.\"")
        color: "#c8a0ff"
        font { pixelSize: 15; italic: true; weight: Font.Bold }
    }

    // what the sealed pack costs
    Text {
        z: 150
        visible: stage.phase === "pack" && stage.mode !== "box" && !stage.cardsIn && !stage.offTheRecord && !stage.packPaid
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.875
        readonly property bool free: stage.progress.freePacks > 0
        readonly property bool short: !free && stage.progress.berries < stage.packCost
        text: free ? "Free pack  (" + stage.progress.freePacks + " left)"
              : short ? Progress.format(stage.packCost) + "  ·  not enough berries yet"
              : Progress.format(stage.packCost)
        color: free ? "#7fd1b9" : short ? "#ff8a7a" : "#ffd56b"
        font { pixelSize: 18; weight: Font.Black }
    }

    // celebrations: a wanted poster for achievements, a banner for the rest
    Item {
        id: celebration
        z: 295
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.09
        width: poster.visible ? poster.width : slabReveal.visible ? slabReveal.width : banner2.width
        height: poster.visible ? poster.height : slabReveal.visible ? slabReveal.height : banner2.height
        readonly property var c: stage.currentCelebration
        opacity: c && !stage.diamondShowing ? 1 : 0   // a Diamond Label has its own (DiamondReveal)
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        scale: c ? 1 : 0.85
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        MouseArea {
            anchors.fill: parent
            enabled: !!celebration.c
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mouse.button === Qt.RightButton ? stage.clearCelebrations() : stage.skipCelebration()
        }
        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 10
            visible: !!celebration.c && stage.celebrations.length > 0
            text: "Clear all  (" + stage.celebrations.length + " more)"
            fontSize: 12
            onClicked: stage.clearCelebrations()
        }

        Rectangle {   // behind the slab reveal, so what's on screen doesn't show through the case
            visible: slabReveal.visible
            x: slabReveal.x - 18; y: slabReveal.y - 14
            width: slabReveal.width + 36; height: slabReveal.height + 30
            radius: 14
            color: "#0c1020"
            border.color: slabReveal.visible && celebration.c.slab.grade === 10 ? "#ffd700" : "#3a4258"
        }
        Column {   // a graded card is back: the slab, and its grade
            id: slabReveal
            visible: !!celebration.c && celebration.c.kind === "graded"
            spacing: 8
            width: 240
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: slabReveal.visible ? "GRADED  " + celebration.c.slab.grade + "  " + Progress.gradeName(celebration.c.slab) : ""
                color: slabReveal.visible && celebration.c.slab.grade === 10 ? "#ffd700" : "#fff6e0"
                style: Text.Outline; styleColor: "#000000"
                font { pixelSize: 24; weight: Font.Black; italic: true }
            }
            Slab {
                width: 240
                card: slabReveal.visible ? stage.localCard(celebration.c.slab) : null
                labelStyle: Progress.slabStyle(stage.progress)
                time: stage.t
                hoverTilt: false
            }
        }

        Rectangle {
            id: poster
            visible: !!celebration.c && celebration.c.kind === "achievement"
            width: 300
            height: posterColumn.height + 36
            color: "#ead9ae"
            border.color: "#5a4325"
            border.width: 3
            radius: 4
            Column {
                id: posterColumn
                anchors.horizontalCenter: parent.horizontalCenter
                y: 16
                spacing: 4
                readonly property var a: celebration.c && celebration.c.a ? celebration.c.a : null
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "WANTED"
                    color: "#3b2a16"
                    font { pixelSize: 40; weight: Font.Black; family: "serif"; letterSpacing: 4 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: posterColumn.a ? posterColumn.a.title.toUpperCase() : ""
                    color: "#3b2a16"
                    font { pixelSize: 20; weight: Font.Black; family: "serif" }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!posterColumn.a && !!posterColumn.a.set
                    text: posterColumn.a && posterColumn.a.set ? posterColumn.a.set + "  ·  " + ((stage.sets[posterColumn.a.set] || {}).name || "") : ""
                    color: "#7a4e10"
                    font { pixelSize: 13; weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: posterColumn.a ? posterColumn.a.text : ""
                    color: "#5a4325"
                    font.pixelSize: 13
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: posterColumn.a ? Progress.format(posterColumn.a.bounty) : ""
                    color: "#3b2a16"
                    font { pixelSize: 24; weight: Font.Black; family: "serif" }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!posterColumn.a && posterColumn.a.reward > 0
                    text: posterColumn.a ? "reward  +" + Progress.format(posterColumn.a.reward) : ""
                    color: "#7a4e10"
                    font { pixelSize: 13; weight: Font.Bold }
                }
            }
        }

        Rectangle {
            id: banner2
            visible: !!celebration.c && celebration.c.kind !== "achievement" && celebration.c.kind !== "graded"
            width: bannerText.width + 40
            height: bannerText.height + 22
            radius: height / 2
            color: "#1b2236"
            border.color: "#7fd1b9"
            border.width: 2
            Text {
                id: bannerText
                anchors.centerIn: parent
                readonly property var c: celebration.c
                text: !c ? ""
                      : c.kind === "bounty" ? "Bounty complete: " + Progress.bountyText(c.b) + "   +" + Progress.bountyRewardText(c.b)
                      : c.kind === "weekly" ? "Weekly bounty complete: " + Progress.weeklyText(c.b) + "   +" + Progress.weeklyRewardText(c.b)
                      : c.kind === "season" && c.goal ? "Season goal: " + c.goal.text + "   +" + c.goal.pts + " points"
                      : c.kind === "season" ? "Season reward: " + c.text
                      : c.kind === "streak" ? "Day " + c.count + " streak   +" + Progress.format(c.reward) + (c.freePack ? "  and a free pack" : "")
                      : c.kind === "freePack" ? "A free pack is ready"
                      : c.kind === "graded" ? "Grading is back: " + Tiers.displayName(c.slab) + "  ·  "
                                              + c.slab.grade + " " + Progress.gradeName(c.slab)
                      : c.kind === "backfill" ? "Back-dated " + c.count + " wanted posters for what you'd already done   +" + Progress.format(c.reward)
                      : ""
                color: "#fff6e0"
                font { pixelSize: 17; weight: Font.Bold }
            }
        }
    }

    DiamondReveal {
        anchors.fill: parent
        z: 296
        slab: stage.diamondShowing ? stage.localCard(stage.currentCelebration.slab) : null
        value: stage.diamondShowing ? stage.slabValue(stage.currentCelebration.slab) : 0
        time: stage.t
        onDismissed: stage.skipCelebration()
    }

    VaultView {
        id: vaultView
        anchors.fill: parent
        z: 249
        visible: stage.phase === "vault"
        stage: stage
    }

    CardShow {
        id: showView
        anchors.fill: parent
        z: 251
        visible: stage.phase === "show"
        stage: stage
    }

    PortView {
        id: portView
        anchors.fill: parent
        z: 249
        visible: stage.phase === "port"
        stage: stage
    }

    SyncPanel {
        anchors.fill: parent
        z: 249
        visible: stage.phase === "sync"
        stage: stage
    }

    BountyBoard {
        id: boardView
        anchors.fill: parent
        z: 248
        visible: stage.phase === "board"
        stage: stage
    }

    SetPicker {
        id: setPicker
        anchors.fill: parent
        z: 245
        visible: stage.phase === "sets"
        stage: stage
    }

    BoxView {
        id: boxView
        anchors.fill: parent
        z: 240
        visible: stage.inBoxScreen
        stage: stage
    }

    Binder {
        id: binderView
        anchors.fill: parent
        z: 250
        visible: stage.phase === "binder"
        stage: stage
    }

    Rectangle {   // toast
        z: 290
        visible: opacity > 0
        opacity: stage.toastText ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height * 0.12
        width: toastLabel.width + 32
        height: toastLabel.height + 16
        radius: height / 2
        color: "#1b2236"
        border.color: "#ffd56b"
        Text {
            id: toastLabel
            anchors.centerIn: parent
            text: stage.toastText
            color: "#fff6e0"
            font.pixelSize: 15
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        z: 300
        color: "#ffffff"
        opacity: 0
    }
    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: flash; property: "opacity"; to: 0.85; duration: 60 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 700; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {   // a Diamond Label: three flashes, the last one long
        id: diamondFlash
        NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 50 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 120 }
        NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 50 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 120 }
        PauseAnimation { duration: 280 }
        NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 60 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 1100; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 200 }
        ScriptAction { script: Qt.quit() }
    }
}

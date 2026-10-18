import QtQuick
import "tiers.js" as Tiers

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
    property string mode: host.env("OPTCG_MODE") === "box" ? "box" : "pack"
    readonly property bool inBoxScreen: phase === "boxSealed" || phase === "boxGrid" || phase === "boxSummary"
    property var pack: []
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
        var saved = host.readText(collectionPath);
        if (saved) {
            try {
                collection = JSON.parse(saved);
            } catch (e) {
                console.warn("collection file unreadable, starting a new one:", e);
            }
        }
        if (!host.env("OPTCG_SET")) {
            try {
                var last = JSON.parse(host.readText(settingsPath) || "{}").set;
                if (last && sets[last]) setId = last;
            } catch (e) {}
        }
        loadSet(setId);
    }

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
        host.writeText(settingsPath, JSON.stringify({ set: id }));
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

    function toggleSets() {
        if (phase === "sets") {
            phase = pickerReturn;
        } else if (phase === "error" || (phase === "pack" && !cardsIn) || phase === "summary" || inBoxScreen) {
            pickerReturn = phase;
            phase = "sets";
        }
    }

    function chooseSet(id) {
        if (id === setId && db && db.set === id) {
            phase = pickerReturn;
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
    }

    function newCase() {
        caseState = {
            set: setId,
            box: 0,
            opened: [],
            topperTaken: false,
            toppers: [],
            boxes: []
        };
        var dealt = Tiers.makeCase(db.cards, setInfo);
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
            if (caseState.box >= cfg.boxes) newCase();
        }
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
        phase = nextUnopened() < 0 ? "boxSummary" : "boxGrid";
    }

    function openAllRemaining() {
        if (phase !== "boxGrid") return;
        var opened = boxOpened.slice();
        boxPacks.forEach((p, i) => {
            if (!opened[i]) recordCards(p);
            opened[i] = true;
        });
        boxOpened = opened;
        saveCase();
        phase = "boxSummary";
    }

    function newPack() {
        var leaders = db.cards.filter(c => c.tier === "L");
        packArt = leaders.length ? "file://" + leaders[Math.floor(Math.random() * leaders.length)].image : "";
        pack = Tiers.makePack(db.cards, setInfo, forceHit);
        revealed = 0;
        cardsIn = false;
        inspectIndex = -1;
        phase = "pack";
        packsOpened++;
    }

    function advance() {
        if (charging) return;
        if (phase === "boxSealed") {
            phase = "boxGrid";
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
            if (packLoader.item) packLoader.item.tear();
        } else if (phase === "reveal") {
            if (revealed >= pack.length) {
                phase = "summary";
            } else if (nextTier.rank >= 4) {
                charging = true;   // build suspense before a big card
                chargeTimer.start();
            } else {
                revealed++;
            }
        } else if (phase === "summary") {
            if (inspectIndex >= 0) inspectIndex = -1;
            else if (mode === "box") backToBox();
            else newPack();
        }
    }

    function revealAll() {
        if (phase === "reveal" && !charging) {
            revealed = pack.length;
            phase = "summary";
        }
    }

    function cardKey(c) {
        return setId + ":" + c.image.split("/").pop();   // unique per printing
    }

    function recordPack() {
        packNew = pack.map(c => !collection.cards[cardKey(c)]);
        recordCards(pack);
        if (mode === "box" && currentPackIdx >= 0) {
            var opened = boxOpened.slice();
            opened[currentPackIdx] = true;
            boxOpened = opened;
            saveCase();
        }
    }

    function recordCards(cards) {
        if (cheating) return;   // forced pulls don't go in the binder
        var col = JSON.parse(JSON.stringify(collection));
        cards.forEach(c => {
            var e = col.cards[cardKey(c)];
            if (e) e.count++;
            else col.cards[cardKey(c)] = { id: c.id, name: c.name, tier: c.tier, count: 1, first: new Date().toISOString() };
        });
        col.packs = (col.packs || 0) + 1;
        collection = col;
        host.writeText(collectionPath, JSON.stringify(col, null, 1));
    }

    function toggleBinder() {
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
        s.card = { id: c.id, name: c.name, tier: c.tier, type: c.type, image: c.image };
        host.writeText(path, JSON.stringify(s));
        host.startShowcase();
        toast("Showing " + Tiers.displayName(c) + " on your desktop  ·  drag to move, scroll to resize, right-click to remove");
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
        switch (event.key) {
        case Qt.Key_Escape:
            if (phase === "binder") binderView.back();
            else if (phase === "sets") toggleSets();
            else if (inBoxScreen && boxView.inspected) boxView.inspected = null;
            else if (mode === "box" && phase === "pack" && !cardsIn) backToBox();
            else if (inspectIndex >= 0) inspectIndex = -1;
            else close();
            break;
        case Qt.Key_B:
            toggleBinder();
            break;
        case Qt.Key_O:
            if (phase === "binder") binderView.ownedOnly = !binderView.ownedOnly;
            break;
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Right:
            advance();
            break;
        case Qt.Key_Tab:
            revealAll();
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

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.78
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(parent.width, parent.height) * 1.3
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.5; color: "#18324a80" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
        opacity: 0.6
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
            packImage: stage.packImage
            artSource: stage.packArt
            setCode: stage.db.set
            setName: stage.db.set_name
            onTearStarted: stage.cardsIn = true
            onTorn: {
                stage.recordPack();
                stage.phase = "reveal";
            }
        }
    }

    // ---- hit effects -----------------------------------------------------

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
            backSource: modelData.type === "Leader" ? stage.leaderBack
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
                  : "Click or Space to tear it open   ·   X: open a box   ·   S: sets   ·   B: binder   ·   Esc to close",
            binder: "",
            boxSealed: "",
            sets: "",
            downloading: "",
            boxGrid: "",
            boxSummary: "",
            reveal: "Space / click: next card   ·   Tab: reveal all   ·   D: show on desktop   ·   Esc: close",
            summary: stage.inspectIndex >= 0 ? "Move the mouse to tilt   ·   D: show on desktop   ·   click or Esc to go back"
                     : stage.mode === "box" ? "Hover to tilt   ·   click a card to inspect   ·   Space: back to the box   ·   B: binder   ·   Esc: close"
                     : "Hover to tilt   ·   click a card to inspect   ·   Space: open another pack   ·   X: open a box   ·   S: sets   ·   B: binder   ·   Esc: close"
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

    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 200 }
        ScriptAction { script: Qt.quit() }
    }
}

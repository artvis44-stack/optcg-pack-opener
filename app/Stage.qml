import QtQuick
import "tiers.js" as Tiers

// Full-screen overlay: sealed pack -> tear -> reveal one by one -> summary.
// Box mode wraps that: sealed box -> grid of 24 packs -> box summary, with the
// boxes dealt from a saved virtual case.
//
// Platform-independent: everything outside the window comes from `host`
// (env / readText / writeText, see QuickshellHost.qml).
Item {
    id: stage

    required property QtObject host
    readonly property string home: host.env("HOME")
    readonly property string cacheRoot: (host.env("XDG_CACHE_HOME") || home + "/.cache") + "/optcg"
    readonly property string dataDir: (host.env("XDG_DATA_HOME") || home + "/.local/share") + "/optcg"

    property string setId: "OP-17"
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
        source: "file://" + stage.cacheDir + "/pack.png"
        visible: false
    }
    Image {
        id: boxProbe
        source: "file://" + stage.cacheDir + "/box.png"
        visible: false
    }

    property var db: null
    property string error: ""
    property string phase: "loading"   // loading | error | pack | reveal | summary | binder
                                       // | boxSealed | boxGrid | boxSummary
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
    property var caseState: null        // { set, box, opened: [24 bools], boxes: [12][24][12] card keys }
    property var boxPacks: []           // the current box: 24 packs of cards
    property var boxOpened: []
    property int boxIndex: 0            // 0-11 within the case
    property int currentPackIdx: -1     // pack of the box being opened

    focus: true
    opacity: 0
    NumberAnimation on opacity { id: fadeIn; to: 1; duration: 250 }

    Component.onCompleted: {
        var saved = host.readText(collectionPath);
        if (saved) {
            try {
                collection = JSON.parse(saved);
            } catch (e) {
                console.warn("collection file unreadable, starting a new one:", e);
            }
        }
        loadSet(setId);
    }

    // load a set's card data and start (a pack or a box, by mode)
    function loadSet(id) {
        setId = id;
        caseState = null;
        var text = host.readText(cacheDir + "/cards.json");
        if (!text) {
            error = "No card data for " + id + " yet. Run ~/.config/quickshell/optcg/fetch_cards.py " + id;
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
        if (mode === "box") startBox();
        else newPack();
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
            boxes: Tiers.makeCase(db.cards).map(box => box.map(p => p.map(c => cardKey(c))))
        };
    }

    // resume the saved case (unfinished box first), or deal a new one
    function startBox() {
        if (!caseState) {
            try {
                caseState = JSON.parse(host.readText(casePath));
                if (caseState.set !== setId || caseState.boxes.length !== Tiers.CASE.boxes) caseState = null;
            } catch (e) {
                caseState = null;
            }
        }
        if (!caseState) newCase();
        var done = caseState.opened.length === Tiers.CASE.packsPerBox && caseState.opened.every(o => o);
        if (done) {
            caseState.box++;
            caseState.opened = [];
            if (caseState.box >= Tiers.CASE.boxes) newCase();
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
        pack = Tiers.makePack(db.cards, forceHit);
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
            opacity: !stage.cardsIn || stage.phase === "binder" || stage.inBoxScreen ? 0
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
                    + (stage.mode === "box" ? "box " + (stage.boxIndex + 1) + " of 12, " + stage.boxOpened.filter(o => o).length + " / 24 packs opened"
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
            error: "Esc to close",
            pack: stage.mode === "box" ? "Click or Space to tear it open   ·   Esc: back to the box"
                  : "Click or Space to tear it open   ·   X: open a box   ·   B: binder   ·   Esc to close",
            binder: "",
            boxSealed: "",
            boxGrid: "",
            boxSummary: "",
            reveal: "Space / click: next card   ·   Tab: reveal all   ·   Esc: close",
            summary: stage.inspectIndex >= 0 ? "Move the mouse to tilt   ·   click or Esc to go back"
                     : stage.mode === "box" ? "Hover to tilt   ·   click a card to inspect   ·   Space: back to the box   ·   B: binder   ·   Esc: close"
                     : "Hover to tilt   ·   click a card to inspect   ·   Space: open another pack   ·   X: open a box   ·   B: binder   ·   Esc: close"
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

import QtQuick
import Quickshell
import Quickshell.Io
import "tiers.js" as Tiers

// Full-screen overlay: sealed pack -> tear -> reveal one by one -> summary.
Item {
    id: stage

    property string setId: "OP-17"
    readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/optcg"
    readonly property string cacheDir: cacheRoot + "/" + setId
    // official images built by fetch_cards.py; each falls back to a drawn version
    readonly property string packImage: packProbe.status === Image.Ready ? packProbe.source : ""
    readonly property real packAspect: packImage ? packProbe.implicitWidth / packProbe.implicitHeight : 0.625
    readonly property string deckBack: "file://" + cacheRoot + "/assets/back.png"
    readonly property string leaderBack: "file://" + cacheRoot + "/assets/back_leader.png"

    Image {
        id: packProbe
        source: "file://" + stage.cacheDir + "/pack.png"
        visible: false
    }

    property var db: null
    property string error: ""
    property string phase: "loading"   // loading | error | pack | reveal | summary
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

    focus: true
    opacity: 0
    NumberAnimation on opacity { id: fadeIn; to: 1; duration: 250 }

    // scriptable: qs ipc -p ~/.config/quickshell/optcg call optcg advance
    IpcHandler {
        target: "optcg"
        function advance(): void { stage.advance(); }
        function revealAll(): void { stage.revealAll(); }
        function newPack(): void { if (stage.db) stage.newPack(); }
        function close(): void { stage.close(); }
        function inspect(index: int): void { if (stage.phase === "summary") stage.inspectIndex = index; }
    }

    FileView {
        path: stage.cacheDir + "/cards.json"
        onLoaded: {
            try {
                stage.db = JSON.parse(text());
                stage.newPack();
            } catch (e) {
                stage.error = "cards.json is unreadable: " + e;
                stage.phase = "error";
            }
        }
        onLoadFailed: {
            stage.error = "No card data yet. Run ~/.config/quickshell/optcg/fetch_cards.py";
            stage.phase = "error";
        }
    }

    function newPack() {
        var leaders = db.cards.filter(c => c.tier === "L");
        packArt = leaders.length ? "file://" + leaders[Math.floor(Math.random() * leaders.length)].image : "";
        pack = Tiers.makePack(db.cards, Quickshell.env("OPTCG_FORCE_HIT"));
        revealed = 0;
        cardsIn = false;
        inspectIndex = -1;
        phase = "pack";
        packsOpened++;
    }

    function advance() {
        if (charging) return;
        if (phase === "pack") {
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
            else newPack();
        }
    }

    function revealAll() {
        if (phase === "reveal" && !charging) {
            revealed = pack.length;
            phase = "summary";
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
            var d = i - revealed;
            return { x: cx + d * 1.2, y: cy + d * 1.5 + (cardsIn ? 0 : height * 0.35), s: 1, z: i === revealed ? 90 : 50 - i };
        }
        if (i === revealed - 1)
            return { x: cx, y: cy, s: 1, z: 100 };
        var gap = 12;
        var s2 = Math.min(0.3, (width * 0.92 - 11 * gap) / 12 / W);
        var w2 = W * s2, h2 = H * s2, tot = 12 * w2 + 11 * gap;
        return { x: cx - tot / 2 + i * (w2 + gap) + w2 / 2, y: height - 28 - h2 / 2, s: s2, z: 10 + i };
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
            if (inspectIndex >= 0) inspectIndex = -1;
            else close();
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
            if (phase === "summary") newPack();
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
            onTorn: stage.phase = "reveal"
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
            backSource: modelData.type === "Leader" ? stage.leaderBack : stage.deckBack
            width: stage.cw
            time: stage.t
            x: slot.x - width / 2 + (chargingMe ? stage.shake : 0)
            y: slot.y - height / 2
            z: slot.z
            scale: slot.s
            faceUp: stage.phase !== "pack" && index < stage.revealed
            sway: stage.phase === "reveal" && index === stage.revealed - 1
            hoverTilt: stage.phase === "summary"
            opacity: !stage.cardsIn ? 0 : (stage.inspectIndex >= 0 && stage.inspectIndex !== index ? 0.25 : 1)
            onClicked: stage.inspectIndex = stage.inspectIndex === index ? -1 : index

            Behavior on x { enabled: !cardItem.chargingMe; NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }

            // rarity tag under each summary card
            Text {
                visible: stage.phase === "summary" && stage.inspectIndex < 0
                anchors.top: parent.bottom
                anchors.topMargin: 6 / Math.max(0.01, cardItem.scale)
                anchors.horizontalCenter: parent.horizontalCenter
                text: cardItem.tier.label
                color: cardItem.tier.color
                font { pixelSize: 15 / Math.max(0.01, cardItem.scale); weight: Font.Bold }
            }
        }
    }

    // ---- text ------------------------------------------------------------

    Column {
        id: banner
        z: 150
        visible: stage.phase === "reveal" && stage.revealed > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.height / 2 - 40 + stage.cw / 0.716 / 2 + 14
        spacing: 2
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
            text: best ? "Best pull: " + Tiers.displayName(best) + " (" + Tiers.tierOf(best).label + ")   ·   packs opened: " + stage.packsOpened : ""
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
            pack: "Click or Space to tear it open   ·   Esc to close",
            reveal: "Space / click: next card   ·   Tab: reveal all   ·   Esc: close",
            summary: stage.inspectIndex >= 0 ? "Move the mouse to tilt   ·   click or Esc to go back"
                     : "Hover to tilt   ·   click a card to inspect   ·   Space: open another pack   ·   Esc: close"
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

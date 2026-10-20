import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The Vault (G): your graded cards. Tabs (← →): your slabs (filter by set and
// grade; click one to see it big, sell it or put it on the desktop), what's out
// for grading, the set registry (best grade of each card, Gem Mint progress), and
// the fakes you bought at card shows (worth nothing; keep them or destroy them).
// Cards are sent for grading from the binder: click a card you own, "Grade / pre-grade".
Item {
    id: vault

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var tabs: [["slabs", "Slabs"], ["sets", "Sets"], ["out", "Out for grading"], ["registry", "Set registry"]]
                                .concat(fakes.length ? [["fakes", "Fakes"]] : [])
    property string tab: "slabs"
    property string setFilter: ""
    property int gradeFilter: 0          // 0: every grade, 7: 7 or lower
    property var inspected: null         // a slab shown big
    property real now: Date.now()

    function step(d) {
        var ids = tabs.map(t => t[0]);
        tab = ids[(ids.indexOf(tab) + d + ids.length) % ids.length];
        inspected = null;
    }

    function back() {
        if (inspected) inspected = null;
        else if (tab === "sets" && setsView.opened) setsView.opened = "";
        else stage.toggleVault();
    }

    onVisibleChanged: if (visible) { inspected = null; now = Date.now(); }

    Timer {   // countdowns
        interval: 1000
        running: vault.visible && vault.tab === "out"
        repeat: true
        onTriggered: vault.now = Date.now()
    }

    readonly property var allSlabs: {
        var g = (stage && stage.collection.graded) || {};
        return Object.keys(g).map(id => Object.assign({ slabId: id }, stage.localCard(g[id])))
                     .sort((a, b) => b.grade - a.grade || Tiers.tierOf(b).rank - Tiers.tierOf(a).rank
                                     || (b.gradedAt || 0) - (a.gradedAt || 0));
    }
    readonly property var slabs: allSlabs.filter(s => (!setFilter || s.set === setFilter)
        && (!gradeFilter || (gradeFilter === 7 ? s.grade <= 7 : s.grade === gradeFilter)))
    readonly property var slabSets: {
        var seen = {};
        allSlabs.forEach(s => seen[s.set] = true);
        return stage ? Object.keys(stage.sets).filter(id => seen[id]) : [];
    }
    readonly property var orders: Object.keys(p.grading || {}).map(id => Object.assign({ id: id }, p.grading[id]))
                                        .sort((a, b) => a.readyAt - b.readyAt)
    readonly property int gems: allSlabs.filter(s => s.grade === 10).length
    // counterfeits bought at card shows: { fakeId, card, grade, paid, day, vendor }
    readonly property var fakes: {
        var f = (stage && stage.collection.fakes) || {};
        return Object.keys(f).map(id => Object.assign({ fakeId: id }, f[id])).sort((a, b) => (b.day || "").localeCompare(a.day || ""));
    }
    property string confirmDestroy: ""
    readonly property real worth: allSlabs.reduce((n, s) => n + (stage ? stage.slabValue(s) : 0), 0)

    function timeLeft(ms) {
        var m = Math.max(0, Math.ceil(ms / 60000));
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.96
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    // ---- header ------------------------------------------------------------------------
    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: vault.height * 0.04
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The Vault"
            color: "#ffd56b"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: vault.allSlabs.length + " slab" + (vault.allSlabs.length === 1 ? "" : "s")
                  + "   ·   " + vault.gems + " Gem Mint 10" + (vault.gems === 1 ? "" : "s")
                  + "   ·   worth " + Progress.format(vault.worth)
                  + "   ·   registry score " + Progress.registryTotal(vault.p).toLocaleString(Qt.locale("en_US"), "f", 0)
                  + (vault.orders.length ? "   ·   " + vault.orders.length + " out for grading" : "")
            color: "#fff6e0"
            font { pixelSize: 16; weight: Font.Bold }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: vault.tabs
                PillButton {
                    required property var modelData
                    text: modelData[1] + (modelData[0] === "out" && vault.orders.length ? "  " + vault.orders.length : "")
                    fontSize: 13
                    accent: vault.tab === modelData[0] ? "#ffd56b" : "#7a8090"
                    onClicked: {
                        vault.tab = modelData[0];
                        vault.inspected = null;
                    }
                }
            }
        }
        Flow {   // slab filters: set and grade
            visible: vault.tab === "slabs" && vault.allSlabs.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(vault.width * 0.9, 1100)
            spacing: 6
            PillButton {
                text: "every set"
                fontSize: 11
                accent: vault.setFilter === "" ? "#ffd56b" : "#7a8090"
                onClicked: vault.setFilter = ""
            }
            Repeater {
                model: vault.slabSets
                PillButton {
                    required property string modelData
                    text: modelData
                    fontSize: 11
                    accent: vault.setFilter === modelData ? "#ffd56b" : "#7a8090"
                    onClicked: vault.setFilter = vault.setFilter === modelData ? "" : modelData
                }
            }
            Item { width: 18; height: 1 }
            Repeater {
                model: [[0, "every grade"], [10, "10"], [9, "9"], [8, "8"], [7, "7 or lower"]]
                PillButton {
                    required property var modelData
                    text: modelData[1]
                    fontSize: 11
                    accent: vault.gradeFilter === modelData[0] ? (modelData[0] === 10 ? "#ffd700" : "#ffd56b") : "#7a8090"
                    onClicked: vault.gradeFilter = modelData[0]
                }
            }
        }
    }

    component Panel: Rectangle {
        radius: 10
        color: "#151b2c"
        border.color: "#2c3550"
    }
    component Note: Text {
        color: "#9aa0ad"
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }

    // ---- slabs ------------------------------------------------------------------------
    GridView {
        id: grid
        visible: vault.tab === "slabs"
        anchors {
            top: header.bottom; topMargin: 20
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        readonly property real slabW: 168
        cellWidth: slabW + 28
        cellHeight: slabW * 1.62 + 64
        width: Math.max(cellWidth, Math.floor(vault.width * 0.92 / cellWidth) * cellWidth)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: vault.slabs
        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Slab {
                id: slabView
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: grid.slabW
                card: cell.modelData
                labelStyle: Progress.slabStyle(vault.p)
                time: vault.stage ? vault.stage.t : 0
                onClicked: vault.inspected = cell.modelData
            }
            Text {
                anchors { top: slabView.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                text: Progress.format(vault.stage.slabValue(cell.modelData))
                      + (vault.stage.lockedSlabs[cell.modelData.slabId] ? "   ·   in a case"
                         : cell.modelData.gradedAt && vault.now - cell.modelData.gradedAt < 86400000 ? "   ·   NEW" : "")
                color: cell.modelData.diamond ? "#7ae8ff" : cell.modelData.grade === 10 ? "#ffd700" : "#c8ccd6"
                font { pixelSize: 13; weight: Font.Bold }
            }
        }
    }
    Note {
        visible: vault.tab === "slabs" && vault.slabs.length === 0
        anchors.centerIn: parent
        width: Math.min(560, vault.width * 0.8)
        horizontalAlignment: Text.AlignHCenter
        text: vault.allSlabs.length ? "No slabs match these filters."
              : "No graded cards yet. Open the binder (B), click a card you own and choose \"Grade / pre-grade\". "
                + "It comes back in a slab with a grade from 1 to 10."
    }

    // ---- out for grading ---------------------------------------------------------------
    Flickable {
        visible: vault.tab === "out"
        anchors {
            top: header.bottom; topMargin: 20
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(vault.width * 0.9, 900)
        contentHeight: outCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: outCol
            width: parent.width
            spacing: 10
            Note {
                width: parent.width
                visible: !vault.orders.length
                text: "Nothing out for grading. Send a card from the binder (B): click a card you own, \"Grade / pre-grade\"."
            }
            Repeater {
                model: vault.orders
                Panel {
                    required property var modelData
                    readonly property bool back: modelData.readyAt <= vault.now
                    readonly property real done: Math.max(0, Math.min(1, (vault.now - modelData.sentAt) / Math.max(1, modelData.readyAt - modelData.sentAt)))
                    width: outCol.width
                    height: 96
                    Card {
                        x: 12; y: 8
                        width: 57
                        card: vault.stage.localCard(modelData.card)
                        faceUp: true
                        time: vault.stage ? vault.stage.t : 0
                    }
                    Column {
                        x: 84; y: 12
                        width: parent.width - 100
                        spacing: 6
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Tiers.displayName(modelData.card) + "  ·  " + modelData.card.set + "  ·  " + Tiers.tierOf(modelData.card).label
                            color: "#e8e8ee"
                            font { pixelSize: 15; weight: Font.Bold }
                        }
                        Text {
                            text: (Progress.GRADING.filter(g => g.id === modelData.service)[0] || {}).name + " service  ·  paid "
                                  + Progress.format(modelData.fee || 0)
                                  + "  ·  " + (parent.parent.back ? "back! it's on its way to the vault" : "back in " + vault.timeLeft(modelData.readyAt - vault.now))
                            color: parent.parent.back ? "#7fd1b9" : "#9aa0ad"
                            font.pixelSize: 13
                        }
                        Rectangle {
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#22283a"
                            Rectangle {
                                width: parent.width * parent.parent.parent.done
                                height: parent.height
                                radius: 4
                                color: parent.parent.parent.back ? "#7fd1b9" : "#c8a0ff"
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- fakes: counterfeits from card shows ------------------------------------------------
    Flickable {
        visible: vault.tab === "fakes"
        anchors {
            top: header.bottom; topMargin: 20
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(vault.width * 0.9, 900)
        contentHeight: fakeCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: fakeCol
            width: parent.width
            spacing: 10
            Note {
                width: parent.width
                text: "Counterfeits you bought at card shows. They're worth nothing and don't count as owned. "
                      + "Keep them as a lesson (see how the foil doesn't shimmer?) or destroy them."
            }
            Repeater {
                model: vault.fakes
                Panel {
                    required property var modelData
                    width: fakeCol.width
                    height: modelData.grade ? 150 : 104
                    Loader {
                        x: 12; y: 8
                        sourceComponent: modelData.grade ? fakeSlab : fakeCard
                        readonly property var c: Object.assign({ fake: true, grade: modelData.grade }, vault.stage.localCard(modelData.card))
                        Component {
                            id: fakeCard
                            Card { width: 64; card: parent.c; faceUp: true; time: vault.stage ? vault.stage.t : 0 }
                        }
                        Component {
                            id: fakeSlab
                            Slab { width: 80; card: parent.c; time: vault.stage ? vault.stage.t : 0; hoverTilt: false }
                        }
                    }
                    Column {
                        x: modelData.grade ? 104 : 90; y: 12
                        width: parent.width - x - 16
                        spacing: 6
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "FAKE  ·  " + Tiers.displayName(modelData.card) + "  ·  " + modelData.card.set
                                  + (modelData.grade ? "  ·  a fake " + modelData.grade + " slab" : "")
                            color: "#ff8a7a"
                            font { pixelSize: 15; weight: Font.Bold }
                        }
                        Text {
                            text: "Bought at the " + modelData.day + " card show from " + modelData.vendor + " for " + Progress.format(modelData.paid || 0)
                            color: "#9aa0ad"
                            font.pixelSize: 13
                        }
                        PillButton {
                            text: vault.confirmDestroy === modelData.fakeId ? "Destroy it? Yes" : "Destroy"
                            fontSize: 12
                            accent: "#ff8a7a"
                            onClicked: {
                                if (vault.confirmDestroy !== modelData.fakeId) { vault.confirmDestroy = modelData.fakeId; return; }
                                vault.stage.destroyFake(modelData.fakeId);
                                vault.confirmDestroy = "";
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- sets: collections and their display cases (SetsView.qml) --------------------------
    SetsView {
        id: setsView
        visible: vault.tab === "sets"
        anchors {
            top: header.bottom; topMargin: 16
            bottom: parent.bottom; bottomMargin: 40
            left: parent.left; right: parent.right
        }
        stage: vault.stage
        onInspect: slab => vault.inspected = slab
    }

    // ---- the set registry ----------------------------------------------------------------
    Flickable {
        visible: vault.tab === "registry"
        anchors {
            top: header.bottom; topMargin: 20
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(vault.width * 0.9, 1000)
        contentHeight: regCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: regCol
            width: parent.width
            spacing: 10
            readonly property var rows: {
                var b = vault.p.stats.bySet || {};
                return Object.keys(b).filter(k => b[k].graded > 0).sort((x, y) => b[y].registry - b[x].registry)
                             .map(k => Object.assign({ set: k }, b[k]));
            }
            Note {
                width: parent.width
                text: "Each set scores your best grade of each of its cards, worth more for rarer cards (a 10 of a Manga Rare counts far "
                      + "more than a 10 of a common). Every card of a set graded 10 is a Gem Mint Master Set, the hardest wanted poster there is."
            }
            Note {
                visible: !regCol.rows.length
                text: "Nothing in the registry yet."
            }
            Repeater {
                model: regCol.rows
                Panel {
                    required property var modelData
                    width: regCol.width
                    height: 74
                    Text {
                        x: 16; y: 12
                        text: modelData.set + "  ·  " + ((vault.stage.sets[modelData.set] || {}).name || "")
                        color: "#e8e8ee"
                        font { pixelSize: 16; weight: Font.Black }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 16 }
                        y: 12
                        text: "score " + modelData.registry.toLocaleString(Qt.locale("en_US"), "f", 0)
                        color: "#ffd56b"
                        font { pixelSize: 16; weight: Font.Black }
                    }
                    Text {
                        x: 16; y: 38
                        text: modelData.graded + " of " + modelData.total + " cards graded   ·   " + modelData.gem + " Gem Mint 10"
                              + (modelData.gem === 1 ? "" : "s")
                        color: "#9aa0ad"
                        font.pixelSize: 13
                    }
                    Rectangle {   // graded (purple) and 10s (gold), out of the set
                        x: 16; y: 58
                        width: parent.width - 32
                        height: 6
                        radius: 3
                        color: "#22283a"
                        Rectangle {
                            width: parent.width * (modelData.total ? modelData.graded / modelData.total : 0)
                            height: parent.height
                            radius: 3
                            color: "#6a5a9a"
                        }
                        Rectangle {
                            width: parent.width * (modelData.total ? modelData.gem / modelData.total : 0)
                            height: parent.height
                            radius: 3
                            color: "#ffd700"
                        }
                    }
                }
            }
        }
    }

    // ---- a slab, big ------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: vault.inspected ? 0.8 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: vault.inspected = null
        }
    }
    Slab {
        id: big
        visible: !!vault.inspected
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(20, (vault.height - height) / 2 - 30)
        width: Math.min(380, (vault.height - 210) / 1.62)
        card: vault.inspected
        labelStyle: Progress.slabStyle(vault.p)
        time: vault.stage ? vault.stage.t : 0
        onClicked: vault.inspected = null
    }
    property bool confirmCrack: false
    onInspectedChanged: confirmCrack = false
    Row {
        id: slabActions
        visible: !!vault.inspected
        anchors { horizontalCenter: parent.horizontalCenter; top: big.bottom; topMargin: 16 }
        spacing: 12
        readonly property var s: vault.inspected
        readonly property real chance: s ? Progress.reviewChance(s) : 0
        readonly property int reviewFee: s ? Progress.reviewFee(vault.stage.slabValue(s)) : 0
        readonly property string inCase: s ? vault.stage.lockedSlabs[s.slabId] || "" : ""   // in a display case: hands off
        PillButton {
            visible: !slabActions.inCase
            text: vault.inspected ? "Sell (+" + Progress.format(vault.stage.slabValue(vault.inspected)) + ")" : ""
            accent: "#7fd1b9"
            onClicked: {
                vault.stage.sellSlab(vault.inspected.slabId);
                vault.inspected = null;
            }
        }
        PillButton {
            text: "Show on desktop"
            onClicked: vault.stage.showcase(vault.inspected)
        }
        PillButton {   // up a grade or stays, never down; once per slab
            visible: !!slabActions.s && !vault.stage.offTheRecord && slabActions.chance > 0 && !slabActions.inCase
            text: "Review (" + Progress.format(slabActions.reviewFee) + ", " + Math.round(slabActions.chance * 100) + "% it goes up to "
                  + (slabActions.s ? slabActions.s.grade + 1 : "") + ")"
            accent: "#c8a0ff"
            enabledLook: vault.p.berries >= slabActions.reviewFee
            onClicked: {
                var id = slabActions.s.slabId;
                vault.stage.reviewSlab(id);
                vault.inspected = vault.allSlabs.filter(x => x.slabId === id)[0] || null;
            }
        }
        PillButton {   // back to a raw copy in the binder, to grade again
            visible: !!slabActions.s && !vault.stage.offTheRecord && !slabActions.inCase
            text: vault.confirmCrack ? "Crack it open? Yes" : "Crack it open"
            accent: "#ff8a7a"
            onClicked: {
                if (!vault.confirmCrack) {
                    vault.confirmCrack = true;
                    return;
                }
                vault.stage.crackSlab(slabActions.s.slabId);
                vault.inspected = null;
            }
        }
    }
    Text {   // what cracking or a review would do
        visible: !!slabActions.s
        anchors { horizontalCenter: parent.horizontalCenter; top: slabActions.bottom; topMargin: 10 }
        width: Math.min(760, vault.width - 40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        readonly property var s: slabActions.s
        readonly property var cond: s ? Progress.CONDITION[s.cond] : null
        text: !s ? ""
              : slabActions.inCase ? "In the " + (vault.stage.savedSets[slabActions.inCase] || {}).title
                                     + " display case (the Sets tab): break the set to sell, review or crack it."
              : (cond ? "Graded from a " + cond.name + " copy." : s.cond === "unchecked" ? "Graded from an unchecked copy." : "Graded before conditions.")
                + (s.reviewed ? "  Reviewed already." : s.grade >= 10 ? "" : "  A review lifts it a grade or leaves it, never lower.")
                + "  Cracking it puts the card back in the binder raw"
                + (cond ? " (" + cond.name + ", or a level worse " + Math.round(Progress.CRACK_WEAR * 100) + "% of the time)"
                   : s.cond === "unchecked" || s.grade <= 7 ? " (unchecked, a fresh chance)"
                   : " (" + (s.grade >= 10 ? "Pristine" : s.grade === 9 ? "Clean" : "Decent") + ", or a level worse " + Math.round(Progress.CRACK_WEAR * 100) + "% of the time)")
                + ", to grade again."
                + (s.diamond ? "  The Diamond Label goes with the slab: cracked, it's gone." : "")
        color: "#9aa0ad"
        font.pixelSize: 13
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: vault.inspected ? "Move the mouse to tilt   ·   click or Esc to go back"
              : vault.tab === "sets" ? "← →: switch tabs   ·   save a complete collection in a display case   ·   G or Esc: back"
              : "← →: switch tabs   ·   click a slab to see it big   ·   G or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

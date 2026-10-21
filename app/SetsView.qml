import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress
import "collections.js" as Collections

// The vault's Sets tab: collections to complete with graded cards
// (collections.js), and the display cases of the ones you've saved. Saving
// locks a set's slabs in its case, pays a one-off reward (more for a Gem Set,
// every slab a 10) and makes the set worth more than its slabs toward your
// passive income. A saved set is a collectable: it can't be sold, only broken
// to get its slabs back.
Item {
    id: view

    property Item stage
    property string mode: "cases"          // "cases" | "collections"
    property string kind: ""               // collections: "" = every kind, else Collections.KINDS
    property bool startedOnly: true
    property string opened: ""             // the saved set shown big
    property bool confirmBreak: false
    signal inspect(var slab)

    onOpenedChanged: confirmBreak = false
    onVisibleChanged: {
        if (!visible) { opened = ""; return; }
        if (stage && !stage.allCards) Qt.callLater(stage.loadAllCards);   // once; a frame to show "loading"
        if (savedIds.length === 0) mode = "collections";
    }

    readonly property var savedIds: stage ? Object.keys(stage.savedSets).sort((a, b) =>
        (stage.savedSets[b].savedAt || "").localeCompare(stage.savedSets[a].savedAt || "")) : []

    // every collection with how far along you are: complete ones to save first, then the closest
    readonly property var rows: {
        if (!stage) return [];
        var out = stage.collectionDefs.filter(d => !kind || d.kind === kind).map(d => {
            var saved = !!stage.savedSets[d.id];
            var f = saved ? { filled: d.slots.length, total: d.slots.length, complete: true, slabs: [] } : Collections.fill(d, stage.freeSlabs);
            return { def: d, f: f, saved: saved };
        });
        if (startedOnly) out = out.filter(r => r.f.filled > 0 || r.saved);
        return out.sort((a, b) => (b.f.complete && !b.saved) - (a.f.complete && !a.saved) || a.saved - b.saved
                                  || b.f.filled / b.f.total - a.f.filled / a.f.total || a.f.total - b.f.total);
    }
    readonly property int readyCount: rows.filter(r => r.f.complete && !r.saved).length

    // ---- the switch: cases / collections --------------------------------------------
    Row {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        PillButton {
            text: "Display cases  " + view.savedIds.length
            fontSize: 13
            accent: view.mode === "cases" ? "#ffd56b" : "#7a8090"
            onClicked: view.mode = "cases"
        }
        PillButton {
            text: "Collections" + (view.readyCount ? "  ·  " + view.readyCount + " ready to save" : "")
            fontSize: 13
            accent: view.mode === "collections" ? "#ffd56b" : view.readyCount ? "#7fd1b9" : "#7a8090"
            onClicked: view.mode = "collections"
        }
    }
    Row {   // collections: by kind, started or all
        id: filters
        visible: view.mode === "collections"
        anchors { top: bar.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
        spacing: 6
        Repeater {
            model: [["", "Every kind"]].concat(Collections.KINDS)
            PillButton {
                required property var modelData
                text: modelData[1]
                fontSize: 12
                accent: view.kind === modelData[0] ? "#c8a0ff" : "#7a8090"
                onClicked: view.kind = modelData[0]
            }
        }
        PillButton {
            text: view.startedOnly ? "Started ones" : "All of them"
            fontSize: 12
            accent: "#7fd1b9"
            onClicked: view.startedOnly = !view.startedOnly
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !!view.stage && !view.stage.allCards
        text: "Laying out the collections…"
        color: "#9aa0ad"
        font.pixelSize: 18
    }

    // ---- display cases ------------------------------------------------------------
    GridView {
        id: cases
        visible: view.mode === "cases" && view.savedIds.length > 0
        anchors { top: bar.bottom; topMargin: 18; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        readonly property int cols: Math.max(1, Math.min(view.savedIds.length, Math.floor(view.width / 400)))
        width: cols * cellWidth
        cellWidth: Math.min(400, view.width / cols)
        cellHeight: cellWidth * 0.8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: view.savedIds
        delegate: Item {
            required property string modelData
            width: cases.cellWidth
            height: cases.cellHeight
            DisplayCase {
                anchors.fill: parent
                anchors.margins: 16
                saved: view.stage.savedSets[parent.modelData] || {}
                slabs: view.stage.savedSlabs(parent.modelData)
                worth: view.stage.savedWorth(parent.modelData)
                time: view.stage.t
                onClicked: view.opened = parent.modelData
            }
        }
    }
    Text {
        visible: view.mode === "cases" && view.savedIds.length === 0
        anchors.centerIn: parent
        width: Math.min(640, view.width - 40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "No display cases yet. Complete a collection with graded cards (any grade) and save it: "
              + "its slabs go in a case, you get a reward, and the set is worth "
              + Math.round(Progress.SET_BONUS * 100) + "% more than its slabs (" + Math.round(Progress.GEM_SET_BONUS * 100)
              + "% for a Gem Set, every slab a 10)."
        color: "#9aa0ad"
        font.pixelSize: 16
    }

    // ---- collections ----------------------------------------------------------------
    ListView {
        id: list
        visible: view.mode === "collections" && !!view.stage && !!view.stage.allCards
        anchors { top: filters.bottom; topMargin: 14; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: Math.min(view.width - 40, 1100)
        spacing: 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: view.rows
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var d: modelData.def
            readonly property var f: modelData.f
            readonly property bool ready: f.complete && !modelData.saved
            width: list.width
            height: 112
            radius: 10
            color: ready ? "#14261e" : "#10141f"
            border.color: ready ? "#7fd1b9" : modelData.saved ? "#c49a4a" : "#2a3142"

            Column {
                x: 16; y: 12
                width: 300
                spacing: 3
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.d.title
                    color: "#fff6e0"
                    font { pixelSize: 17; weight: Font.Black }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.d.text
                    color: "#9aa0ad"
                    font.pixelSize: 12
                }
                Item { width: 1; height: 6 }
                Rectangle {   // progress
                    width: parent.width; height: 8; radius: 4
                    color: "#232a3c"
                    Rectangle {
                        width: parent.width * row.f.filled / row.f.total
                        height: parent.height; radius: 4
                        color: row.modelData.saved ? "#c49a4a" : row.ready ? "#7fd1b9" : "#c8a0ff"
                    }
                }
                Text {
                    text: row.modelData.saved ? "In a display case"
                          : row.f.filled + " / " + row.f.total + " graded" + (row.ready ? "  ·  ready to save" : "")
                    color: row.ready ? "#7fd1b9" : row.modelData.saved ? "#e2bd63" : "#c8ccd6"
                    font { pixelSize: 13; weight: Font.Bold }
                }
            }

            Row {   // the slots: the card, dimmed till you have it graded
                id: strip
                x: 330
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                readonly property int fits: Math.max(1, Math.floor((row.width - x - 190) / 50))
                Repeater {
                    model: row.d.slots.slice(0, strip.fits)
                    Item {
                        id: slot
                        required property var modelData
                        required property int index
                        readonly property var slab: row.modelData.saved ? null : row.f.slabs[index]
                        readonly property bool have: row.modelData.saved || !!slab
                        width: 46; height: 84
                        Image {
                            anchors.fill: parent
                            anchors.topMargin: 14
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 120
                            source: "file://" + slot.modelData.card.image
                            opacity: slot.have ? 1 : 0.22
                        }
                        Rectangle {   // the grade it's got, or the slot's name
                            width: parent.width; height: 13; radius: 3
                            color: slot.slab ? (slot.slab.grade === 10 ? "#ffd700" : "#f4f1ea") : "transparent"
                            Text {
                                anchors.centerIn: parent
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: slot.slab ? (slot.slab.diamond ? "◆" : "") + slot.slab.grade : slot.modelData.any ? slot.modelData.label : ""
                                color: slot.slab ? "#14171f" : "#9aa0ad"
                                font { pixelSize: 9; weight: Font.Black }
                            }
                        }
                    }
                }
                Text {
                    visible: row.d.slots.length > strip.fits
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + (row.d.slots.length - strip.fits)
                    color: "#9aa0ad"
                    font { pixelSize: 13; weight: Font.Bold }
                }
            }

            PillButton {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                visible: row.ready && !view.stage.offTheRecord
                text: "Save set"
                fontSize: 15
                accent: "#7fd1b9"
                onClicked: {
                    var id = row.d.id;
                    view.stage.saveCollectionSet(id);
                    if (view.stage.savedSets[id]) {
                        view.mode = "cases";
                        view.opened = id;
                    }
                }
            }
            PillButton {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                visible: row.modelData.saved
                text: "See its case"
                fontSize: 13
                accent: "#e2bd63"
                onClicked: {
                    view.mode = "cases";
                    view.opened = row.d.id;
                }
            }
        }
    }
    Text {
        visible: view.mode === "collections" && !!view.stage && !!view.stage.allCards && view.rows.length === 0
        anchors.centerIn: parent
        text: view.startedOnly ? "None started yet: grade a card from one (see \"All of them\")." : "No collections of this kind in your downloaded sets."
        color: "#9aa0ad"
        font.pixelSize: 16
    }

    // ---- one case, opened -------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: !!view.opened
        color: "#e605070d"
        MouseArea {
            anchors.fill: parent
            onClicked: view.opened = ""
        }
        readonly property var saved: view.opened ? view.stage.savedSets[view.opened] : null
        DisplayCase {
            id: big
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            width: Math.min(parent.width * 0.86, (parent.height - 110) / 0.8)
            height: width * 0.8
            saved: parent.saved || {}
            slabs: view.opened ? view.stage.savedSlabs(view.opened) : []
            worth: view.opened ? view.stage.savedWorth(view.opened) : 0
            time: view.stage ? view.stage.t : 0
            slabsClickable: true
            onSlabClicked: slab => view.inspect(slab)
        }
        Row {
            anchors { top: big.bottom; topMargin: 18; horizontalCenter: parent.horizontalCenter }
            spacing: 12
            PillButton {
                visible: !view.stage.offTheRecord
                text: view.confirmBreak ? "Take them out? The bonus goes. Yes" : "Break the set"
                accent: "#ff8a7a"
                onClicked: {
                    if (!view.confirmBreak) { view.confirmBreak = true; return; }
                    view.stage.breakCollectionSet(view.opened);
                    view.opened = "";
                }
            }
            PillButton {
                text: "Close"
                onClicked: view.opened = ""
            }
        }
        Text {
            anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
            text: parent.saved ? "Saved " + String(parent.saved.savedAt || "").slice(0, 10)
                                 + "   ·   worth " + Math.round(Progress.setBonus(parent.saved.gem) * 100) + "% more than its slabs toward your passive income while it's in the case (it can't be sold)"
                                 + "   ·   click a slab to see it" : ""
            color: "#9aa0ad"
            font.pixelSize: 13
        }
    }
}

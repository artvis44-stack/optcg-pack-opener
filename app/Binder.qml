import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Collection binder: the whole set, owned cards first (in colour, with a
// count), then the missing ones faded; best cards first within each.
Item {
    id: binder

    property Item stage
    property bool ownedOnly: false
    property var inspected: null
    property var hoveredCard: null   // an owned card under the mouse (D shows it on the desktop)

    function back() {
        if (inspected) inspected = null;
        else stage.toggleBinder();
    }

    readonly property var entries: {
        if (!stage || !stage.db) return [];
        var seen = {}, list = [];
        stage.db.cards.forEach(c => {
            var k = stage.cardKey(c);
            if (seen[k]) return;
            seen[k] = true;
            var e = stage.collection.cards[k];
            if (ownedOnly && !e) return;
            list.push({ card: c, count: e ? e.count : 0 });
        });
        // owned first, then missing; best cards first within each
        return list.sort((a, b) => (b.count > 0) - (a.count > 0)
                                   || Tiers.tierOf(b.card).rank - Tiers.tierOf(a.card).rank
                                   || a.card.id.localeCompare(b.card.id));
    }

    readonly property var stats: {
        var res = { owned: 0, total: 0, pulled: 0, packs: 0 };
        if (!stage || !stage.db) return res;
        var inSet = {};
        stage.db.cards.forEach(c => inSet[stage.cardKey(c)] = true);
        res.total = Object.keys(inSet).length;
        var cards = stage.collection.cards;
        Object.keys(cards).forEach(k => {
            res.pulled += cards[k].count;
            if (inSet[k]) res.owned++;
        });
        res.packs = stage.collection.packs || 0;
        return res;
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.94
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from the pack underneath
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: binder.height * 0.04
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: binder.stage && binder.stage.db ? "Binder  ·  " + binder.stage.db.set + "  " + binder.stage.db.set_name : "Binder"
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: binder.stats.owned + " / " + binder.stats.total + " collected   ·   "
                  + binder.stats.pulled + " cards pulled   ·   " + binder.stats.packs + " packs opened"
                  + (binder.ownedOnly ? "   ·   showing owned only" : "")
            color: "#d0d4dc"
            font.pixelSize: 16
        }
        // completion bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420; height: 6; radius: 3
            color: "#22283a"
            Rectangle {
                width: parent.width * (binder.stats.total ? binder.stats.owned / binder.stats.total : 0)
                height: parent.height; radius: 3
                color: "#ffd56b"
            }
        }
        PillButton {   // sell the spare copies of cheap cards; valuable ones are sold one by one
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !binder.stage.offTheRecord && binder.stage.bulkDuplicates.length > 0
            text: "Sell bulk duplicates (" + binder.stage.bulkDuplicates.reduce((a, it) => a + it.count, 0)
                  + " cards, +" + Progress.format(binder.stage.bulkValue) + ")"
            accent: "#7fd1b9"
            fontSize: 13
            onClicked: binder.stage.sell(binder.stage.bulkDuplicates)
        }
    }

    GridView {
        id: grid
        readonly property real cardW: Math.min(150, binder.height * 0.19 * 0.716)
        anchors {
            top: header.bottom; topMargin: 22
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        cellWidth: cardW + 26
        cellHeight: cardW / 0.716 + 40
        width: Math.max(cellWidth, Math.floor(binder.width * 0.92 / cellWidth) * cellWidth)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: binder.entries

        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool owned: modelData.count > 0
            width: grid.cellWidth
            height: grid.cellHeight

            Card {
                id: cardView
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: grid.cardW
                card: cell.modelData.card
                faceUp: true
                time: binder.stage.t
                hoverTilt: cell.owned
                opacity: cell.owned ? 1 : 0.14
                onClicked: binder.inspected = cell.modelData.card
                onHoveredChanged: {
                    if (hovered && cell.owned) binder.hoveredCard = cell.modelData.card;
                    else if (binder.hoveredCard === cell.modelData.card) binder.hoveredCard = null;
                }
            }

            Rectangle {
                visible: cell.modelData.count > 1
                anchors { right: cardView.right; top: cardView.top; margins: -6 }
                width: countText.width + 12
                height: countText.height + 4
                radius: height / 2
                color: "#ffd56b"
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: "×" + cell.modelData.count
                    color: "#2a0a10"
                    font { pixelSize: 13; weight: Font.Black }
                }
            }

            Text {
                anchors { top: cardView.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                text: Tiers.tierOf(cell.modelData.card).label
                color: Tiers.tierOf(cell.modelData.card).color
                opacity: cell.owned ? 1 : 0.35
                font { pixelSize: 12; weight: Font.Bold }
            }
        }
    }

    Text {
        anchors.centerIn: grid
        visible: binder.ownedOnly && binder.entries.length === 0
        text: "Nothing pulled yet. Open a pack!"
        color: "#9aa0ad"
        font.pixelSize: 20
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: binder.inspected ? "Move the mouse to tilt   ·   D: show on desktop   ·   click or Esc to go back"
              : "Scroll to browse   ·   hover to tilt   ·   click a card to inspect   ·   D: show the hovered card on your desktop   ·   O: owned only / all   ·   B or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }

    // ---- inspect a single card ------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: binder.inspected ? 0.75 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: binder.inspected = null
        }
    }

    Row {   // under the inspected card: show it on the desktop, or sell a copy
        visible: !!binder.inspected
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 46
        spacing: 14
        readonly property var entry: binder.inspected ? binder.stage.collection.cards[binder.stage.cardKey(binder.inspected)] : null
        PillButton {
            text: "Show on desktop (D)"
            visible: !!parent.entry
            onClicked: binder.stage.showcase(binder.inspected)
        }
        PillButton {
            visible: !!parent.entry && !binder.stage.offTheRecord
            text: !binder.inspected ? ""
                  : (parent.entry && parent.entry.count === 1 ? "Sell your only copy" : "Sell one")
                    + " (+" + Progress.format(binder.stage.cardValue(binder.inspected)) + ")"
            accent: parent.entry && parent.entry.count === 1 ? "#ff8a7a" : "#7fd1b9"
            onClicked: {
                var c = binder.inspected;
                binder.stage.sell([{ card: c, count: 1 }]);
                if (!binder.stage.collection.cards[binder.stage.cardKey(c)]) binder.inspected = null;
            }
        }
    }

    Card {
        anchors.centerIn: parent
        visible: !!binder.inspected
        width: Math.min(420, binder.height * 0.8 * 0.716)
        card: binder.inspected
        faceUp: true
        time: binder.stage.t
        hoverTilt: true
        onClicked: binder.inspected = null
    }

    Text {
        visible: !!binder.inspected
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        readonly property var c: binder.inspected
        readonly property var owned: c ? binder.stage.collection.cards[binder.stage.cardKey(c)] : null
        text: c ? Tiers.displayName(c) + "  ·  " + c.id + "  ·  " + Tiers.tierOf(c).label
                  + (owned ? "  ·  ×" + owned.count + "  ·  first pulled " + owned.first.slice(0, 10) : "") : ""
        color: c ? Tiers.tierOf(c).color : "white"
        style: Text.Outline; styleColor: "#000000"
        font { pixelSize: 20; weight: Font.Bold }
    }
}

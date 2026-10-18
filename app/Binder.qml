import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Collection binder. "This set": the whole set, owned cards first (in colour,
// with a count), then the missing ones faded; best cards first within each.
// "All sets" (Tab): everything you own from every set, best pulls first, with
// set filter chips and an estimated value.
Item {
    id: binder

    property Item stage
    property bool ownedOnly: false
    property bool allSets: false
    property string setFilter: ""    // all sets: just this set ("" = every set)

    onAllSetsChanged: {
        inspected = null;
        hoveredCard = null;
        if (allSets) stage.loadAllMarkets();
    }

    // the sets you own cards from, in release order
    readonly property var ownedSets: {
        if (!stage) return [];
        var seen = {};
        stage.allOwned.forEach(it => seen[it.card.set] = true);
        return Object.keys(stage.sets).filter(id => seen[id]);
    }
    property var inspected: null
    property var hoveredCard: null   // an owned card under the mouse (D shows it on the desktop)

    function back() {
        if (inspected) inspected = null;
        else stage.toggleBinder();
    }

    readonly property var entries: {
        if (!stage) return [];
        if (allSets) {
            var order = Object.keys(stage.sets);
            return stage.allOwned.filter(it => !setFilter || it.card.set === setFilter)
                .sort((a, b) => Tiers.tierOf(b.card).rank - Tiers.tierOf(a.card).rank
                                || order.indexOf(a.card.set) - order.indexOf(b.card.set)
                                || a.card.id.localeCompare(b.card.id));
        }
        if (!stage.db) return [];
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
        var res = { owned: 0, total: 0, pulled: 0, packs: 0, value: 0 };
        if (!stage) return res;
        res.packs = stage.collection.packs || 0;
        if (allSets) {
            entries.forEach(it => {
                res.owned++;
                res.pulled += it.count;
                res.value += it.count * stage.cardValue(it.card);
            });
            return res;
        }
        if (!stage.db) return res;
        var inSet = {};
        stage.db.cards.forEach(c => inSet[stage.cardKey(c)] = true);
        res.total = Object.keys(inSet).length;
        var cards = stage.collection.cards;
        Object.keys(cards).forEach(k => {
            if (!inSet[k]) return;
            res.pulled += cards[k].count;
            res.owned++;
        });
        return res;
    }

    readonly property var bulk: !stage ? [] : allSets
        ? stage.allBulkDuplicates.filter(it => !setFilter || it.card.set === setFilter)
        : stage.bulkDuplicates
    readonly property int bulkValue: bulk.reduce((a, it) => a + it.count * stage.cardValue(it.card), 0)

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
            text: binder.allSets ? "Binder  ·  all sets" + (binder.setFilter ? "  ·  " + binder.setFilter : "")
                  : binder.stage && binder.stage.db ? "Binder  ·  " + binder.stage.db.set + "  " + binder.stage.db.set_name : "Binder"
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Row {   // this set / all sets
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            PillButton {
                text: "This set"
                fontSize: 13
                accent: binder.allSets ? "#7a8090" : "#ffd56b"
                onClicked: binder.allSets = false
            }
            PillButton {
                text: "All sets"
                fontSize: 13
                accent: binder.allSets ? "#ffd56b" : "#7a8090"
                onClicked: binder.allSets = true
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: binder.allSets
                  ? binder.stats.owned + " different cards   ·   " + binder.stats.pulled + " cards   ·   "
                    + (binder.setFilter ? binder.setFilter : binder.ownedSets.length + " sets")
                    + "   ·   worth about " + Progress.format(binder.stats.value)
                  : binder.stats.owned + " / " + binder.stats.total + " collected   ·   "
                    + binder.stats.pulled + " cards pulled   ·   " + binder.stats.packs + " packs opened"
                    + (binder.ownedOnly ? "   ·   showing owned only" : "")
            color: "#d0d4dc"
            font.pixelSize: 16
        }
        Flow {   // all sets: filter by set
            visible: binder.allSets && binder.ownedSets.length > 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(binder.width * 0.85, (binder.ownedSets.length + 1) * 70)
            spacing: 6
            PillButton {
                text: "every set"
                fontSize: 11
                accent: binder.setFilter === "" ? "#ffd56b" : "#7a8090"
                onClicked: binder.setFilter = ""
            }
            Repeater {
                model: binder.ownedSets
                PillButton {
                    required property string modelData
                    text: modelData
                    fontSize: 11
                    accent: binder.setFilter === modelData ? "#ffd56b" : "#7a8090"
                    onClicked: binder.setFilter = binder.setFilter === modelData ? "" : modelData
                }
            }
        }
        // completion bar
        Rectangle {
            visible: !binder.allSets
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
            visible: !binder.stage.offTheRecord && binder.bulk.length > 0
            text: "Sell bulk duplicates (" + binder.bulk.reduce((a, it) => a + it.count, 0)
                  + " cards, +" + Progress.format(binder.bulkValue) + ")"
            accent: "#7fd1b9"
            fontSize: 13
            onClicked: binder.stage.sell(binder.bulk)
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
                width: grid.cardW + 20
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: (binder.allSets ? cell.modelData.card.set + " · " : "") + Tiers.tierOf(cell.modelData.card).label
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
              : "Scroll to browse   ·   click a card to inspect   ·   D: show the hovered card on your desktop   ·   Tab: this set / all sets"
                + (binder.allSets ? "" : "   ·   O: owned only / all") + "   ·   B or Esc: back"
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
                    + " (+" + Progress.format(binder.stage.sellPrice(binder.inspected)) + ")"
            accent: parent.entry && parent.entry.count === 1 ? "#ff8a7a" : "#7fd1b9"
            onClicked: {
                var c = binder.inspected;
                binder.stage.sell([{ card: c, count: 1 }]);
                if (!binder.stage.collection.cards[binder.stage.cardKey(c)]) binder.inspected = null;
            }
        }
        PillButton {   // the card shop: order any card, at a markup
            visible: !!binder.inspected && !binder.stage.offTheRecord
            readonly property int price: binder.inspected ? Math.round(binder.stage.cardValue(binder.inspected) * Progress.ORDER_MARKUP) : 0
            text: "Buy one (" + Progress.format(price) + ")"
            accent: "#ffd56b"
            enabledLook: binder.stage.progress.berries >= price
            onClicked: binder.stage.buyCard(binder.inspected, price, false)
        }
    }

    Row {   // send a copy for grading (it comes back in a slab: see the Port, P)
        visible: !!binder.inspected && !binder.stage.offTheRecord
                 && !!binder.stage.collection.cards[binder.stage.cardKey(binder.inspected)]
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 92
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Grade a copy:"
            color: "#c8ccd6"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Repeater {
            model: Progress.GRADING
            PillButton {
                required property var modelData
                readonly property int fee: binder.inspected ? Progress.gradingFee(modelData.id, binder.stage.cardValue(binder.inspected), binder.stage.progress) : 0
                text: modelData.name + " · " + (modelData.hours < 1 ? modelData.hours * 60 + "m" : modelData.hours + "h")
                      + " · " + Progress.format(fee)
                fontSize: 12
                accent: "#c8a0ff"
                enabledLook: binder.stage.progress.berries >= fee
                onClicked: {
                    var c = binder.inspected;
                    binder.stage.gradeCard(c, modelData.id);
                    if (!binder.stage.collection.cards[binder.stage.cardKey(c)]) binder.inspected = null;
                }
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

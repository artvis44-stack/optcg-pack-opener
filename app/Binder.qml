import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Collection binder. "This set": the whole set, owned cards first (in colour,
// with a count), then the missing ones faded; best cards first within each.
// "All sets" (Tab): everything you own from every set, best pulls first, with
// set filter chips and an estimated value. Both can be searched, filtered (F:
// rarity, card type, colour, owned / missing / duplicates / graded) and sorted.
Item {
    id: binder

    property Item stage
    property bool allSets: false

    // ---- search, filters, sort ----
    property string search: ""
    property string rarity: ""        // a RARITIES id
    property string cardType: ""      // Leader, Character, Event, Stage, DON!!
    property string cardColor: ""     // Red, Green, Blue, Purple, Black, Yellow
    property string show: ""          // "" | owned | missing | dupes | graded
    property string sortBy: "rarity"  // rarity | number | value | count
    property bool filtersOpen: false
    readonly property int activeFilters: (search ? 1 : 0) + (rarity ? 1 : 0) + (cardType ? 1 : 0) + (cardColor ? 1 : 0) + (show ? 1 : 0)
    readonly property var rarities: [
        ["common", "Common", ["C"]], ["uncommon", "Uncommon", ["UC"]], ["rare", "Rare", ["R", "FOIL"]],
        ["leader", "Leader", ["L"]], ["sr", "Super Rare", ["SR"]], ["sec", "Secret Rare", ["SEC"]],
        ["alt", "Alt Art", ["AA", "L_AA", "TEX", "SEC_AA"]], ["sp", "SP", ["SP", "SP_GOLD"]],
        ["chase", "Chase (TR, Manga, Super)", ["TR", "MANGA", "SUPER", "SUPER_L", "SIGNED"]],
        ["special", "Pandaman / topper", ["PANDA", "TOPPER"]], ["don", "DON!!", ["DON", "DON_GOLD", "DON_SP"]]
    ]
    readonly property var types: ["Leader", "Character", "Event", "Stage", "DON!!"]
    readonly property var colors: ["Red", "Green", "Blue", "Purple", "Black", "Yellow"]
    function clearFilters() {
        searchInput.text = "";
        search = ""; rarity = ""; cardType = ""; cardColor = ""; show = "";
    }
    function toggleOwned() {   // O
        show = show === "owned" ? "" : "owned";
    }

    // card type and colour for every card of your sets (cards.json); the
    // collection itself only keeps id, name and rarity
    property var meta: ({})
    function loadMeta() {
        var m = Object.assign({}, meta), changed = false;
        Object.keys(stage.sets).forEach(id => {
            if (m["set:" + id]) return;
            var db = null;
            try { db = JSON.parse(stage.host.readText(stage.cacheRoot + "/" + id + "/cards.json") || "null"); } catch (e) {}
            if (!db) return;
            m["set:" + id] = true;
            changed = true;
            (db.cards || []).forEach(c => m[id + ":" + c.image.split("/").pop()] = { type: c.type || "", color: c.color || "" });
        });
        if (changed) meta = m;
    }
    function infoOf(card) {
        return meta[(card.set || stage.setId) + ":" + card.image.split("/").pop()] || { type: card.type || "", color: card.color || "" };
    }
    function matches(it) {
        var c = it.card, owned = it.count > 0 || it.slabs.length > 0;
        if (search) {
            var q = search.toLowerCase();
            if (Tiers.displayName(c).toLowerCase().indexOf(q) < 0 && c.id.toLowerCase().indexOf(q) < 0) return false;
        }
        if (rarity) {
            var g = rarities.filter(r => r[0] === rarity)[0];
            if (g && g[2].indexOf(c.tier) < 0) return false;
        }
        if (cardType || cardColor) {
            var info = infoOf(c);
            if (cardType && info.type !== cardType) return false;
            if (cardColor && info.color.indexOf(cardColor) < 0) return false;
        }
        if (show === "owned" && !owned) return false;
        if (show === "missing" && owned) return false;
        if (show === "dupes" && it.count < 2) return false;
        if (show === "graded" && !it.slabs.length) return false;
        return true;
    }

    // keep the scroll position across a change to the collection (selling,
    // buying, grading rebuild the list, which would jump back to the top)
    function keepScroll(fn) {
        // the grid re-anchors to its rows after a rebuild, so remember the card at the top and how far into its row
        var i = Math.max(0, grid.indexAt(grid.width / 2, grid.contentY + 1));
        var item = grid.itemAtIndex(i);
        restoreScroll.index = i;
        restoreScroll.offset = item ? grid.contentY - item.y : 0;
        restoreScroll.atEnd = grid.atYEnd && grid.contentY > grid.originY;
        fn();
        restoreScroll.restart();
    }
    Timer {   // once the grid has rebuilt
        id: restoreScroll
        property int index: 0
        property real offset: 0
        property bool atEnd: false
        interval: 60
        onTriggered: {
            grid.forceLayout();
            if (atEnd) {
                grid.positionViewAtEnd();
            } else {
                grid.positionViewAtIndex(Math.min(index, grid.count - 1), GridView.Beginning);
                grid.contentY = Math.min(grid.contentY + offset, grid.originY + Math.max(0, grid.contentHeight - grid.height));
            }
        }
    }

    // a row of filter chips: label, then "all" and the options
    component Chips: Row {
        id: chips
        property string label
        property var options: []      // [value, text]
        property string value
        signal picked(string v)
        spacing: 5
        Text {
            width: 62
            anchors.verticalCenter: parent.verticalCenter
            text: chips.label
            color: "#7a8090"
            font { pixelSize: 12; weight: Font.Bold }
        }
        Repeater {
            model: [["", "all"]].concat(chips.options)
            PillButton {
                required property var modelData
                text: modelData[1]
                fontSize: 11
                accent: chips.value === modelData[0] ? "#ffd56b" : "#7a8090"
                onClicked: chips.picked(chips.value === modelData[0] ? "" : modelData[0])
            }
        }
    }

    property int sellCount: 1           // how many copies of the inspected card to sell
    onInspectedChanged: sellCount = 1
    property string setFilter: ""    // all sets: just this set ("" = every set)

    onAllSetsChanged: {
        inspected = null;
        hoveredCard = null;
        if (allSets) {
            stage.loadAllMarkets();
            loadMeta();
        }
    }
    onCardTypeChanged: loadMeta()
    onCardColorChanged: loadMeta()
    onSortByChanged: if (sortBy === "value") stage.loadAllMarkets()

    // the sets you own cards from, in release order
    readonly property var ownedSets: {
        if (!stage) return [];
        var seen = {};
        stage.allOwned.forEach(it => seen[it.card.set] = true);
        return Object.keys(stage.sets).filter(id => seen[id]);
    }
    property var inspected: null
    property var grading: null          // the card in the grading dialog
    property var hoveredCard: null   // an owned card under the mouse (D shows it on the desktop)

    function back() {
        if (grading) grading = null;
        else if (inspected) inspected = null;
        else stage.toggleBinder();
    }

    // everything this view holds, before search / filters
    readonly property var all: {
        if (!stage) return [];
        if (allSets) return stage.allOwned.filter(it => !setFilter || it.card.set === setFilter);
        if (!stage.db) return [];
        var seen = {}, list = [];
        stage.db.cards.forEach(c => {
            var k = stage.cardKey(c);
            if (seen[k]) return;
            seen[k] = true;
            var e = stage.collection.cards[k], slabs = stage.slabsByKey[k] || [];
            list.push({ card: c, count: e ? e.count : 0, slabs: slabs });
        });
        return list;
    }

    readonly property var entries: {
        var meta = binder.meta;   // re-filter once card types / colours are loaded
        var list = all.filter(it => matches(it)), order = stage ? Object.keys(stage.sets) : [];
        var has = it => it.count > 0 || it.slabs.length > 0;
        var byRarity = (a, b) => Tiers.tierOf(b.card).rank - Tiers.tierOf(a.card).rank;
        var byNumber = (a, b) => order.indexOf(a.card.set) - order.indexOf(b.card.set) || a.card.id.localeCompare(b.card.id);
        if (sortBy === "number") return list.sort((a, b) => byNumber(a, b) || byRarity(a, b));
        if (sortBy === "value") return list.sort((a, b) => stage.cardValue(b.card) - stage.cardValue(a.card) || byRarity(a, b));
        if (sortBy === "count") return list.sort((a, b) => (b.count + b.slabs.length) - (a.count + a.slabs.length) || byRarity(a, b));
        // by rarity: in a set, owned (raw or graded) first, then missing; best cards first within each
        return list.sort((a, b) => (allSets ? 0 : has(b) - has(a))
                                   || byRarity(a, b)
                                   || (allSets ? order.indexOf(a.card.set) - order.indexOf(b.card.set) : 0)
                                   || a.card.id.localeCompare(b.card.id));
    }

    readonly property var stats: {
        var res = { owned: 0, total: 0, pulled: 0, packs: 0, value: 0 };
        if (!stage) return res;
        res.packs = stage.collection.packs || 0;
        if (allSets) {
            entries.forEach(it => {
                res.owned++;
                res.pulled += it.count + it.slabs.length;
                res.value += it.count * stage.cardValue(it.card) + it.slabs.reduce((n, s) => n + stage.slabValue(s), 0);
            });
            return res;
        }
        if (!stage.db) return res;
        var inSet = {};
        stage.db.cards.forEach(c => inSet[stage.cardKey(c)] = true);
        res.total = Object.keys(inSet).length;
        var cards = stage.ownedKeys();   // graded cards are still yours
        Object.keys(cards).forEach(k => {
            if (!inSet[k]) return;
            res.pulled += cards[k].count + (stage.slabsByKey[k] || []).length;
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
                    + (binder.activeFilters ? "   ·   showing " + binder.entries.length : "")
            color: "#d0d4dc"
            font.pixelSize: 16
        }
        Row {   // search, filters, sort
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Rectangle {
                width: 220
                height: 30
                radius: 15
                color: "#151b2c"
                border.color: searchInput.activeFocus ? "#ffd56b" : "#2c3550"
                TextInput {
                    id: searchInput
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#e8e8ee"
                    font.pixelSize: 13
                    clip: true
                    text: binder.search
                    onTextChanged: binder.search = text
                    Keys.onEscapePressed: event => {   // clear, then let go of the keyboard
                        if (text) text = "";
                        else binder.stage.forceActiveFocus();
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: binder.stage.forceActiveFocus()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !searchInput.text && !searchInput.activeFocus
                        text: "Search name or number"
                        color: "#4a5370"
                        font.pixelSize: 13
                    }
                }
            }
            PillButton {
                text: "Filters" + (binder.activeFilters - (binder.search ? 1 : 0) > 0 ? " (" + (binder.activeFilters - (binder.search ? 1 : 0)) + ")" : "") + "  F"
                fontSize: 12
                accent: binder.filtersOpen || binder.activeFilters ? "#ffd56b" : "#7a8090"
                onClicked: binder.filtersOpen = !binder.filtersOpen
            }
            PillButton {
                visible: binder.activeFilters > 0
                text: "clear"
                fontSize: 12
                accent: "#ff8a7a"
                onClicked: binder.clearFilters()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "   sort:"
                color: "#7a8090"
                font.pixelSize: 12
            }
            Repeater {
                model: [["rarity", "rarity"], ["number", "number"], ["value", "value"], ["count", "copies"]]
                PillButton {
                    required property var modelData
                    text: modelData[1]
                    fontSize: 12
                    accent: binder.sortBy === modelData[0] ? "#ffd56b" : "#7a8090"
                    onClicked: binder.sortBy = modelData[0]
                }
            }
        }
        Column {   // the filters (F)
            visible: binder.filtersOpen
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5
            Chips {
                label: "Rarity"
                // only the rarities this view has
                options: binder.rarities.filter(r => binder.all.some(it => r[2].indexOf(it.card.tier) >= 0)).map(r => [r[0], r[1]])
                value: binder.rarity
                onPicked: v => binder.rarity = v
            }
            Chips {
                label: "Type"
                options: binder.types.map(t => [t, t])
                value: binder.cardType
                onPicked: v => binder.cardType = v
            }
            Chips {
                label: "Colour"
                options: binder.colors.map(c => [c, c])
                value: binder.cardColor
                onPicked: v => binder.cardColor = v
            }
            Chips {
                label: "Show"
                options: [["owned", "owned"], ["missing", "missing"], ["dupes", "duplicates"], ["graded", "graded"]]
                value: binder.show
                onPicked: v => binder.show = v
            }
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
            onClicked: binder.keepScroll(() => binder.stage.sell(binder.bulk))
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
            readonly property bool owned: modelData.count > 0 || modelData.slabs.length > 0
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
                onClicked: {
                    binder.inspected = cell.modelData.card;
                    binder.stage.forceActiveFocus();   // keys work again after typing in the search
                }
                onHoveredChanged: {
                    if (hovered && cell.owned) binder.hoveredCard = cell.modelData.card;
                    else if (binder.hoveredCard === cell.modelData.card) binder.hoveredCard = null;
                }
            }

            Rectangle {   // graded: the best grade, like a slab label
                visible: cell.modelData.slabs.length > 0
                anchors { left: cardView.left; top: cardView.top; margins: -6 }
                width: gradeText.width + 12
                height: gradeText.height + 4
                radius: 3
                color: cell.modelData.slabs.length && cell.modelData.slabs[0].grade === 10 ? "#ffd700" : "#f4f1ea"
                border.color: "#14171f"
                Text {
                    id: gradeText
                    anchors.centerIn: parent
                    text: cell.modelData.slabs.length ? "GRADED " + cell.modelData.slabs[0].grade
                                                        + (cell.modelData.slabs.length > 1 ? " ×" + cell.modelData.slabs.length : "") : ""
                    color: "#14171f"
                    font { pixelSize: 11; weight: Font.Black }
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
        visible: binder.activeFilters > 0 && binder.entries.length === 0
        text: "No cards match these filters."
        color: "#9aa0ad"
        font.pixelSize: 20
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: binder.inspected ? "Move the mouse to tilt   ·   D: show on desktop   ·   click or Esc to go back"
              : "Scroll to browse   ·   click a card to inspect   ·   D: show the hovered card on your desktop   ·   Tab: this set / all sets"
                + "   ·   F: filters   ·   O: owned only / all   ·   B or Esc: back"
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
        PillButton {   // the card shop: order any card, at a markup
            visible: !!binder.inspected && !binder.stage.offTheRecord
            readonly property int price: binder.inspected ? Math.round(binder.stage.cardValue(binder.inspected) * Progress.ORDER_MARKUP) : 0
            text: "Buy one (" + Progress.format(price) + ")"
            accent: "#ffd56b"
            enabledLook: binder.stage.progress.berries >= price
            onClicked: binder.keepScroll(() => binder.stage.buyCard(binder.inspected, price, false))
        }
    }

    Row {   // sell: how many copies
        id: sellRow
        readonly property var entry: binder.inspected ? binder.stage.collection.cards[binder.stage.cardKey(binder.inspected)] : null
        readonly property int have: entry ? entry.count : 0
        readonly property int n: Math.max(1, Math.min(binder.sellCount, have))
        visible: have > 0 && !binder.stage.offTheRecord
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 92
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Sell"
            color: "#c8ccd6"
            font { pixelSize: 14; weight: Font.Bold }
        }
        PillButton {
            text: "−"
            fontSize: 14
            enabledLook: sellRow.n > 1
            onClicked: binder.sellCount = Math.max(1, sellRow.n - 1)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            horizontalAlignment: Text.AlignHCenter
            text: sellRow.n + " of " + sellRow.have
            color: "#fff6e0"
            font { pixelSize: 15; weight: Font.Black }
        }
        PillButton {
            text: "+"
            fontSize: 14
            enabledLook: sellRow.n < sellRow.have
            onClicked: binder.sellCount = Math.min(sellRow.have, sellRow.n + 1)
        }
        PillButton {
            visible: sellRow.have > 2
            text: "all but one"
            fontSize: 12
            onClicked: binder.sellCount = sellRow.have - 1
        }
        PillButton {
            readonly property string raw: binder.inspected && (binder.stage.slabsByKey[binder.stage.cardKey(binder.inspected)] || []).length ? " raw" : ""
            text: (sellRow.n === sellRow.have ? (sellRow.have === 1 ? "Sell your only" + raw + " copy" : "Sell every" + raw + " copy") : "Sell " + sellRow.n + raw)
                  + " (+" + Progress.format(sellRow.n * (binder.inspected ? binder.stage.sellPrice(binder.inspected) : 0)) + ")"
            accent: sellRow.n === sellRow.have ? "#ff8a7a" : "#7fd1b9"
            onClicked: {
                var c = binder.inspected, n = sellRow.n;
                binder.keepScroll(() => binder.stage.sell([{ card: c, count: n }]));
                binder.sellCount = 1;
                var k = binder.stage.cardKey(c);
                if (!binder.stage.collection.cards[k] && !(binder.stage.slabsByKey[k] || []).length) binder.inspected = null;
            }
        }
    }

    Row {   // grading: send a copy (the dialog below), or see the slabs in the vault
        visible: !!binder.inspected && !binder.stage.offTheRecord
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 138
        spacing: 12
        readonly property string key: binder.inspected ? binder.stage.cardKey(binder.inspected) : ""
        readonly property var slabs: binder.stage.slabsByKey[key] || []
        PillButton {
            visible: !!binder.stage.collection.cards[parent.key]
            text: "Grade / pre-grade…"
            accent: "#c8a0ff"
            onClicked: binder.grading = binder.inspected
        }
        PillButton {
            visible: parent.slabs.length > 0
            text: "Graded: " + parent.slabs.map(s => s.grade).join(", ") + "  ·  open the vault (G)"
            accent: "#ffd56b"
            onClicked: {
                binder.inspected = null;
                binder.stage.toggleVault();
            }
        }
        Repeater {   // sell a slab at its graded price, the most valuable first
            model: parent.slabs.filter(s => !binder.stage.lockedSlabs[s.slabId])   // not ones in a display case
                               .sort((a, b) => binder.stage.slabValue(b) - binder.stage.slabValue(a)).slice(0, 3)
            PillButton {
                required property var modelData
                text: "Sell the graded " + (modelData.diamond ? "◆" : "") + modelData.grade
                      + " (+" + Progress.format(binder.stage.slabValue(modelData)) + ")"
                accent: modelData.diamond ? "#7ae8ff" : "#7fd1b9"
                onClicked: {
                    var c = binder.inspected, id = modelData.slabId;
                    binder.keepScroll(() => binder.stage.sellSlab(id));
                    var k = binder.stage.cardKey(c);
                    if (!binder.stage.collection.cards[k] && !(binder.stage.slabsByKey[k] || []).length) binder.inspected = null;
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
        y: 56   // under the wallet line
        readonly property var c: binder.inspected
        readonly property var owned: c ? binder.stage.collection.cards[binder.stage.cardKey(c)] : null
        readonly property var conds: Progress.conditions(owned)
        readonly property var slabs: c ? binder.stage.slabsByKey[binder.stage.cardKey(c)] || [] : []
        text: c ? Tiers.displayName(c) + "  ·  " + c.id + "  ·  " + Tiers.tierOf(c).label
                  + (owned ? "  ·  ×" + owned.count + "  ·  first pulled " + (owned.first || "").slice(0, 10) : "")
                  + (owned && owned.cond ? "  ·  " + Progress.CONDITIONS.filter(x => conds[x.id] > 0).map(x => x.name + " " + conds[x.id]).join(", ") : "")
                  + "  ·  " + Progress.format(binder.stage.cardValue(c)) + " raw"
                  + (slabs.length ? "  ·  " + slabs.length + " graded, best " + Progress.format(Math.max.apply(null, slabs.map(s => binder.stage.slabValue(s)))) : "") : ""
        color: c ? Tiers.tierOf(c).color : "white"
        style: Text.Outline; styleColor: "#000000"
        font { pixelSize: 20; weight: Font.Bold }
    }

    // ---- the grading dialog: the three services, and the odds ---------------------------
    Rectangle {
        anchors.fill: parent
        z: 5
        visible: !!binder.grading
        color: "#cc000000"
        MouseArea {
            anchors.fill: parent
            onClicked: binder.grading = null
        }
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(820, parent.width - 60)
            height: dialogCol.height + 44
            radius: 14
            color: "#121828"
            border.color: "#c8a0ff"
            MouseArea { anchors.fill: parent }   // clicks inside don't close it
            readonly property var c: binder.grading
            readonly property int value: c ? binder.stage.cardValue(c) : 0
            readonly property bool rush: Progress.eventIs(binder.stage.progress, "grading")
            // which copy goes: "unchecked" or a condition; the best one there is unless you pick
            readonly property var counts: Progress.conditions(c ? binder.stage.collection.cards[binder.stage.cardKey(c)] : null)
            readonly property var have: ["unchecked"].concat(Progress.CONDITIONS.map(x => x.id)).filter(id => counts[id] > 0)
            property string pick: ""
            onCChanged: pick = ""
            readonly property string chosen: pick && counts[pick] > 0 ? pick
                                           : have.filter(id => id !== "unchecked")[0] || (have.length ? "unchecked" : "")
            readonly property var cond: Progress.CONDITION[chosen] || null
            readonly property var odds: Progress.serviceOdds(chosen, "value")

            Card {
                x: 22; y: 22
                width: 150
                card: dialog.c
                faceUp: true
                time: binder.stage.t
                hoverTilt: true
            }
            Column {
                id: dialogCol
                x: 194; y: 22
                width: dialog.width - 216
                spacing: 12
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: dialog.c ? "Grade " + Tiers.displayName(dialog.c) : ""
                    color: "#fff6e0"
                    font { pixelSize: 22; weight: Font.Black }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Worth " + Progress.format(dialog.value) + " raw. One copy goes off and comes back in a slab, graded 1 to 10: "
                          + "a 10 is worth ×" + Progress.GRADE_MULT[10] + ", a 9 ×" + Progress.GRADE_MULT[9] + ", an 8 ×" + Progress.GRADE_MULT[8]
                          + ", lower grades less. How it grades depends on the copy's condition: a pre-grade tells you, prep makes it better."
                          + (dialog.rush ? "  Grading Rush this week: every service at the Value price, back in half the time." : "")
                    color: "#c8ccd6"
                    font.pixelSize: 13
                }
                Flow {   // your copies, by condition: click one to send that one
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: dialog.have
                        Rectangle {
                            required property string modelData
                            readonly property bool on: dialog.chosen === modelData
                            readonly property color tint: Progress.CONDITION[modelData] ? Progress.CONDITION[modelData].color : "#9aa0ad"
                            width: chipText.width + 24
                            height: chipText.height + 12
                            radius: height / 2
                            color: on ? tint : "#1b2236"
                            border.color: tint
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: (Progress.CONDITION[modelData] ? Progress.CONDITION[modelData].name : "Unchecked") + "  ×" + dialog.counts[modelData]
                                color: parent.on ? "#14171f" : parent.tint
                                font { pixelSize: 13; weight: Font.Bold }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dialog.pick = parent.modelData
                            }
                        }
                    }
                    PillButton {   // look an unchecked copy over
                        visible: dialog.counts.unchecked > 0
                        readonly property int fee: Progress.preGradeFee(dialog.value)
                        text: "Pre-grade a copy (" + Progress.format(fee) + ")"
                        fontSize: 12
                        accent: "#7fd1b9"
                        enabledLook: binder.stage.progress.berries >= fee
                        onClicked: {
                            var got = binder.stage.preGradeCard(dialog.c);
                            if (got) dialog.pick = got;
                        }
                    }
                    PillButton {   // prep the chosen copy a level up
                        visible: !!dialog.cond && dialog.cond.rank > 0
                        readonly property int fee: Progress.prepFee(dialog.value)
                        text: dialog.cond ? "Prep it to " + Progress.CONDITIONS[Math.max(0, dialog.cond.rank - 1)].name
                                            + " (" + Progress.format(fee) + ", " + Math.round(Progress.PREP_SLIP * 100) + "% it slips)" : ""
                        fontSize: 12
                        accent: "#ffd56b"
                        enabledLook: binder.stage.progress.berries >= fee
                        onClicked: {
                            var from = dialog.chosen;
                            if (binder.stage.prepCard(dialog.c, from)) dialog.pick = "";
                        }
                    }
                }
                Row {   // the odds of the chosen copy, as a bar
                    width: parent.width
                    height: 34
                    Repeater {
                        model: dialog.odds.filter(g => g[0] >= 6 && g[1] > 0).concat([[5, dialog.odds.filter(g => g[0] <= 5).reduce((n, g) => n + g[1], 0)]]).filter(g => g[1] > 0)
                        Rectangle {
                            required property var modelData
                            width: dialogCol.width * modelData[1]
                            height: 34
                            color: modelData[0] === 10 ? "#ffd700" : modelData[0] === 9 ? "#c8a0ff" : modelData[0] === 8 ? "#7fa8ff"
                                 : modelData[0] === 7 ? "#5a7090" : modelData[0] === 6 ? "#46506a" : "#353b4e"
                            border.color: "#121828"
                            Text {
                                anchors.centerIn: parent
                                visible: parent.width > 34
                                text: (modelData[0] === 5 ? "≤5" : modelData[0]) + "\n" + Math.round(modelData[1] * 100) + "%"
                                horizontalAlignment: Text.AlignHCenter
                                color: modelData[0] >= 9 ? "#14171f" : "#e8e8ee"
                                font { pixelSize: 10; weight: Font.Black }
                                lineHeight: 0.9
                            }
                        }
                    }
                }
                Row {   // the services
                    spacing: 10
                    Repeater {
                        model: Progress.GRADING
                        Rectangle {
                            required property var modelData
                            readonly property int fee: dialog.c ? Progress.gradingFee(modelData.id, dialog.value, binder.stage.progress) : 0
                            readonly property real hours: modelData.hours * (dialog.rush ? 0.5 : 1)
                            readonly property bool afford: binder.stage.progress.berries >= fee
                            readonly property real ten: (Progress.serviceOdds(dialog.chosen, modelData.id).filter(g => g[0] === 10)[0] || [10, 0])[1]
                            width: (dialogCol.width - 30) / 4
                            height: 156
                            radius: 10
                            color: "#1a2136"
                            border.color: modelData.id === "elite" ? "#ffd700" : modelData.id === "express" ? "#ffd56b" : "#2c3550"
                            Column {
                                x: 12; y: 10
                                width: parent.width - 24
                                spacing: 4
                                Text {
                                    text: modelData.name
                                    color: "#e8e8ee"
                                    font { pixelSize: 16; weight: Font.Black }
                                }
                                Text {
                                    text: "back in " + (parent.parent.hours < 1 ? Math.round(parent.parent.hours * 60) + " minutes" : parent.parent.hours + " hours")
                                    color: "#9aa0ad"
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: (modelData.bestOf ? "graded twice, the best kept  ·  " : "") + Math.round(parent.parent.ten * 100) + "% a 10"
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    color: modelData.bestOf ? "#ffd700" : "#9aa0ad"
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: Progress.format(parent.parent.fee)
                                    color: parent.parent.afford ? "#ffd56b" : "#ff8a7a"
                                    font { pixelSize: 18; weight: Font.Black }
                                }
                                PillButton {
                                    text: "Send"
                                    fontSize: 12
                                    accent: "#c8a0ff"
                                    enabledLook: parent.parent.afford
                                    onClicked: {
                                        var c = binder.grading;
                                        var sent = false;
                                        binder.keepScroll(() => sent = binder.stage.gradeCard(c, modelData.id, dialog.chosen));
                                        if (!sent) return;
                                        binder.grading = null;
                                        if (!binder.stage.collection.cards[binder.stage.cardKey(c)] && !(binder.stage.slabsByKey[binder.stage.cardKey(c)] || []).length)
                                            binder.inspected = null;
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    text: "It shows up in the vault (G) when it's back."
                    color: "#7a8090"
                    font.pixelSize: 12
                }
            }
        }
    }
}

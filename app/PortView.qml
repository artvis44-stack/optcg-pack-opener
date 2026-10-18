import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The Port (P): where berries go. Tabs (← →): your ship and crew (perks), the
// card shop (today's deals; any card can also be ordered from the binder),
// grading (cards out for grading, your slabs), sealed products (buy, hold
// while they gain value, sell or open) and cosmetics (backdrops, slab labels).
Item {
    id: port

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var tabs: [["ship", "Ship & crew"], ["shop", "Card shop"], ["grading", "Grading"],
                                 ["sealed", "Sealed"], ["cosmetics", "Cosmetics"]]
    property string tab: "ship"
    property real now: Date.now()
    property var inspected: null     // a card or slab shown big

    function step(d) {
        var ids = tabs.map(t => t[0]);
        tab = ids[(ids.indexOf(tab) + d + ids.length) % ids.length];
        inspected = null;
    }

    function back() {
        if (inspected) inspected = null;
        else stage.togglePort();
    }

    onVisibleChanged: {
        if (!visible) return;
        inspected = null;
        now = Date.now();
        loadPool();
        if (tab === "cosmetics") fetchPlaymats();
    }
    onTabChanged: {
        loadPool();
        if (tab === "cosmetics") fetchPlaymats();
    }

    // portraits and ship pictures: art from cards in your downloaded sets
    readonly property var poolCards: pool.map(x => x.card)
    function art(name) {
        return name ? Progress.artFor(poolCards, name, c => Tiers.tierOf(c).rank) : null;
    }
    readonly property var crewArt: {
        var m = {};
        Progress.CREW.forEach(c => m[c.id] = art(c.card));
        return m;
    }
    function fetchPlaymats() {
        Progress.BACKDROPS.forEach(b => { if (b.playmat) stage.fetchPlaymat(b); });
    }

    Timer {   // countdowns
        interval: 1000
        running: port.visible
        repeat: true
        onTriggered: port.now = Date.now()
    }

    function timeLeft(ms) {
        var m = Math.max(0, Math.ceil(ms / 60000));
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    // ---- the card shop's stock: every card of your downloaded sets ----
    property var pool: []
    readonly property var deals: pool.length ? Progress.dailyDeals(Progress.dayOf(now), pool, c => Tiers.tierOf(c).rank) : []
    function loadPool() {
        if (!stage || pool.length) return;
        var out = [];
        stage.downloadedSets().forEach(s => {
            try {
                var db = JSON.parse(stage.host.readText(stage.cacheRoot + "/" + s.id + "/cards.json") || "{}"), seen = {};
                (db.cards || []).forEach(c => {
                    var key = s.id + ":" + c.image.split("/").pop();
                    if (seen[key] || c.tier === "DON") return;
                    seen[key] = true;
                    out.push({ key: key, card: Object.assign({}, c, { set: s.id }) });
                });
            } catch (e) {}
        });
        pool = out;
        Progress.dailyDeals(Progress.dayOf(now), out, c => Tiers.tierOf(c).rank).forEach(d => {
            if (!stage.markets[d.card.set]) stage.loadMarket(d.card.set);
        });
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.96
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    // ---- header -------------------------------------------------------------------
    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: port.height * 0.04
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The Port"
            color: "#ffd56b"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Progress.format(port.p.berries) + "   ·   " + Progress.ship(port.p).name
                  + "   ·   " + Progress.crewCount(port.p) + " / " + Progress.CREW.length + " crew"
                  + "   ·   +" + Progress.format(Progress.incomePerMinute(port.p)) + "/min while active"
            color: "#fff6e0"
            font { pixelSize: 16; weight: Font.Bold }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: port.tabs
                PillButton {
                    required property var modelData
                    text: modelData[1]
                    fontSize: 13
                    accent: port.tab === modelData[0] ? "#ffd56b" : "#7a8090"
                    onClicked: {
                        port.tab = modelData[0];
                        port.inspected = null;
                    }
                }
            }
        }
    }

    // card art, cropped to fill (from the top: faces and ships sit there); a
    // placeholder letter when there's no card for it
    component Art: Rectangle {
        id: artBox
        property var card: null
        property string fallback: ""
        property bool dim: false
        radius: 8
        color: "#0e1322"
        clip: true
        Image {
            anchors.fill: parent
            source: artBox.card ? "file://" + artBox.card.image : ""
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
            sourceSize.width: 400
            asynchronous: true
            opacity: artBox.dim ? 0.35 : 1
        }
        Text {
            anchors.centerIn: parent
            visible: !artBox.card
            text: artBox.fallback
            color: "#3a4258"
            font { pixelSize: parent.height * 0.4; weight: Font.Black }
        }
    }

    component Panel: Rectangle {
        radius: 10
        color: "#151b2c"
        border.color: "#2c3550"
    }
    component Heading: Text {
        color: "#ffd56b"
        font { pixelSize: 18; weight: Font.Black }
    }
    component Note: Text {
        color: "#9aa0ad"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    Flickable {
        id: body
        anchors {
            top: header.bottom; topMargin: 22
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(port.width * 0.92, 1180)
        contentHeight: content.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: body.width
            spacing: 14

            // ==== ship & crew ====================================================
            Column {
                visible: port.tab === "ship"
                width: parent.width
                spacing: 14

                Panel {
                    width: parent.width
                    height: Math.max(shipCol.height, shipArt.height) + 28
                    Art {
                        id: shipArt
                        x: 14; y: 14
                        width: 220
                        height: 150
                        card: port.art(shipCol.cur.card)
                        fallback: "⚓"
                    }
                    Column {
                        id: shipCol
                        x: shipArt.x + shipArt.width + 18; y: 14
                        width: parent.width - x - 16
                        spacing: 6
                        readonly property var cur: Progress.ship(port.p)
                        readonly property var next: Progress.nextShip(port.p)
                        Heading { text: "Your ship: " + shipCol.cur.name }
                        Note { width: parent.width; text: shipCol.cur.text }
                        Note {
                            width: parent.width
                            text: "Free pack every " + Progress.freePackHours(port.p) + " hours, holds " + Progress.freePackMax(port.p)
                                  + "  ·  passive income ×" + Progress.incomeBonus(port.p).toFixed(2).replace(/\.?0+$/, "")
                        }
                        Item { width: 1; height: 6 }
                        Text {
                            visible: !!shipCol.next
                            text: shipCol.next ? "Next: " + shipCol.next.name + "  ·  " + shipCol.next.text : ""
                            color: "#e8e8ee"
                            font { pixelSize: 15; weight: Font.Bold }
                        }
                        PillButton {
                            visible: !!shipCol.next
                            text: shipCol.next ? "Upgrade for " + Progress.format(shipCol.next.price) : ""
                            enabledLook: !!shipCol.next && port.p.berries >= shipCol.next.price
                            onClicked: {
                                if (port.stage.prog(p => Progress.upgradeShip(p))) {
                                    port.stage.sfx("legendary");
                                    port.stage.toast("Welcome aboard the " + Progress.ship(port.stage.progress).name + "!");
                                } else port.stage.toast("Not enough berries yet.");
                            }
                        }
                        Text {
                            visible: !shipCol.next
                            text: "The finest ship on the seas. Nothing left to upgrade."
                            color: "#7fd1b9"
                            font { pixelSize: 15; weight: Font.Bold }
                        }
                    }
                }

                Heading { text: "Your crew" }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: Progress.CREW
                        Panel {
                            required property var modelData
                            readonly property bool aboard: Progress.hasCrew(port.p, modelData.id)
                            width: (content.width - 24) / 3
                            height: 124
                            border.color: aboard ? "#7fd1b9" : "#2c3550"
                            Art {
                                x: 10; y: 10
                                width: 104
                                height: 104
                                card: port.crewArt[modelData.id]
                                fallback: modelData.name[0]
                                dim: !parent.aboard
                            }
                            Column {
                                x: 126; y: 12
                                width: parent.width - 138
                                spacing: 5
                                Text {
                                    text: modelData.name
                                    color: parent.parent.aboard ? "#7fd1b9" : "#e8e8ee"
                                    font { pixelSize: 15; weight: Font.Black }
                                }
                                Note { width: parent.width; text: modelData.perk }
                                PillButton {
                                    visible: !parent.parent.aboard
                                    text: "Recruit · " + Progress.format(modelData.price)
                                    fontSize: 12
                                    enabledLook: port.p.berries >= modelData.price
                                    onClicked: {
                                        if (port.stage.prog(p => Progress.recruit(p, modelData.id))) {
                                            port.stage.sfx("epic");
                                            port.stage.toast(modelData.name + " joined your crew!");
                                        } else port.stage.toast("Not enough berries yet.");
                                    }
                                }
                                Text {
                                    visible: parent.parent.aboard
                                    text: "Aboard since " + port.p.crew[modelData.id]
                                    color: "#7fd1b9"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            // ==== card shop =================================================
            Column {
                visible: port.tab === "shop"
                width: parent.width
                spacing: 12
                Heading { text: "Today's deals" }
                Note {
                    width: parent.width
                    text: "New stock every day from the sets you've downloaded, at market price + "
                          + Math.round((Progress.DEAL_MARKUP - 1) * 100) + "%. Looking for one card? Find it in the binder (B), "
                          + "click it and order it (+" + Math.round((Progress.ORDER_MARKUP - 1) * 100) + "%)."
                }
                Note {
                    visible: port.deals.length === 0
                    text: "Nothing in stock: download a set first (S)."
                }
                Flow {
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: port.deals
                        Column {
                            id: deal
                            required property var modelData
                            readonly property int price: Math.round(port.stage.cardValue(modelData.card) * Progress.DEAL_MARKUP)
                            readonly property bool sold: port.p.shop.day === Progress.dayOf(port.now) && !!port.p.shop.bought[modelData.key]
                            width: 130
                            spacing: 4
                            Card {
                                width: 130
                                card: deal.modelData.card
                                faceUp: true
                                time: port.stage.t
                                hoverTilt: true
                                opacity: deal.sold ? 0.3 : 1
                                onClicked: port.inspected = deal.modelData.card
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: deal.modelData.card.set + " · " + Tiers.tierOf(deal.modelData.card).label
                                color: Tiers.tierOf(deal.modelData.card).color
                                font { pixelSize: 11; weight: Font.Bold }
                            }
                            PillButton {
                                text: deal.sold ? "Bought" : Progress.format(deal.price)
                                fontSize: 12
                                enabledLook: !deal.sold && port.p.berries >= deal.price
                                onClicked: if (!deal.sold) port.stage.buyCard(deal.modelData.card, deal.price, true)
                            }
                        }
                    }
                }
            }

            // ==== grading =================================================
            Column {
                visible: port.tab === "grading"
                width: parent.width
                spacing: 12
                readonly property var orders: Object.keys(port.p.grading || {}).map(id => Object.assign({ id: id }, port.p.grading[id]))
                                                    .sort((a, b) => a.readyAt - b.readyAt)
                readonly property var slabs: {
                    var g = (port.stage && port.stage.collection.graded) || {};
                    return Object.keys(g).map(id => Object.assign({ slabId: id }, g[id]))
                                 .sort((a, b) => b.grade - a.grade || Tiers.tierOf(b).rank - Tiers.tierOf(a).rank);
                }
                Heading { text: "Out for grading" }
                Note {
                    width: parent.width
                    text: parent.orders.length ? "" : "Nothing out. To grade a card, find it in the binder (B), click it and pick a service. "
                          + "It comes back in a slab with a grade from 1 to 10: a 10 is worth 4× the card, a 9 1.6×."
                    visible: text !== ""
                }
                Repeater {
                    model: parent.orders
                    Panel {
                        required property var modelData
                        width: content.width
                        height: 44
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: Tiers.displayName(modelData.card) + "  ·  " + modelData.card.set + "  ·  "
                                  + (Progress.GRADING.filter(g => g.id === modelData.service)[0] || {}).name + " service"
                            color: "#e8e8ee"
                            font { pixelSize: 14; weight: Font.Bold }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: modelData.readyAt <= port.now ? "back!" : "back in " + port.timeLeft(modelData.readyAt - port.now)
                            color: modelData.readyAt <= port.now ? "#7fd1b9" : "#ffd56b"
                            font { pixelSize: 14; weight: Font.Bold }
                        }
                    }
                }

                Heading { text: "Your slabs" + (parent.slabs.length ? "  (" + parent.slabs.length + ")" : "") }
                Note { visible: !parent.slabs.length; text: "No graded cards yet." }
                Flow {
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: parent.parent.slabs
                        Column {
                            id: slab
                            required property var modelData
                            width: 130
                            spacing: 4
                            Rectangle {   // the slab: card in an acrylic case with the grade on top
                                width: 130
                                height: 130 / 0.716 + 30
                                radius: 6
                                color: "#22d8e4ff"
                                border.color: slab.modelData.grade === 10 ? "#ffd700" : "#55ffffff"
                                border.width: slab.modelData.grade === 10 ? 2 : 1
                                Rectangle {
                                    x: 5; y: 4
                                    width: parent.width - 10
                                    height: 20
                                    radius: 3
                                    color: Progress.slabStyle(port.p).top
                                    Text {
                                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                        text: Progress.GRADE_NAME[slab.modelData.grade]
                                        color: Progress.slabStyle(port.p).sub
                                        font { pixelSize: 9; weight: Font.Black }
                                    }
                                    Text {
                                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        text: slab.modelData.grade
                                        color: slab.modelData.grade === 10 ? "#b8860b" : Progress.slabStyle(port.p).text
                                        font { pixelSize: 15; weight: Font.Black }
                                    }
                                }
                                Card {
                                    x: 6; y: 28
                                    width: parent.width - 12
                                    card: slab.modelData
                                    faceUp: true
                                    time: port.stage.t
                                    hoverTilt: true
                                    dropShadow: false
                                    onClicked: port.inspected = slab.modelData
                                }
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: Tiers.displayName(slab.modelData)
                                color: Tiers.tierOf(slab.modelData).color
                                font { pixelSize: 11; weight: Font.Bold }
                            }
                            Column {
                                spacing: 4
                                PillButton {
                                    text: "Sell " + Progress.format(port.stage.slabValue(slab.modelData))
                                    fontSize: 11
                                    accent: "#7fd1b9"
                                    onClicked: port.stage.sellSlab(slab.modelData.slabId)
                                }
                                PillButton {
                                    text: "Show on desktop"
                                    fontSize: 11
                                    onClicked: port.stage.showcase(slab.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ==== sealed ====================================================
            Column {
                visible: port.tab === "sealed"
                width: parent.width
                spacing: 12
                readonly property var held: Object.keys(port.p.sealed || {}).map(id => Object.assign({ id: id }, port.p.sealed[id]))
                                                  .sort((a, b) => a.at - b.at)
                Heading { text: "Your sealed products" }
                Note {
                    width: parent.width
                    text: "Sealed boxes and cases gain value while you hold them (older sets faster), and count toward your "
                          + "collection's value. Sell them for what they're worth now, or open them: the boxes wait for you in box mode."
                }
                Note { visible: !parent.held.length; text: "Nothing sealed yet." }
                Repeater {
                    model: parent.held
                    Panel {
                        required property var modelData
                        readonly property int worth: Progress.sealedValue(modelData, port.now)
                        width: content.width
                        height: 50
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.set + " " + modelData.kind + "  ·  " + modelData.setName
                                  + "  ·  paid " + Progress.format(modelData.paid) + "  ·  now " + Progress.format(parent.worth)
                                  + "  (" + (parent.worth >= modelData.paid ? "+" : "") + ((parent.worth / modelData.paid - 1) * 100).toFixed(1) + "%)"
                            color: "#e8e8ee"
                            font { pixelSize: 14; weight: Font.Bold }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            PillButton { text: "Open"; fontSize: 12; onClicked: port.stage.openSealed(modelData.id) }
                            PillButton { text: "Sell"; fontSize: 12; accent: "#7fd1b9"; onClicked: port.stage.sellSealed(modelData.id) }
                        }
                    }
                }
                Heading { text: "Buy sealed" }
                Repeater {
                    model: port.stage ? Object.keys(port.stage.sets) : []
                    Panel {
                        id: product
                        required property string modelData
                        readonly property var info: port.stage.sets[modelData] || {}
                        readonly property var c: Tiers.setConfig(info)
                        readonly property int box: Progress.boxPrice(c.family, c.packsPerBox, port.p)
                        readonly property int wholeCase: Progress.casePrice(c.family, c.packsPerBox, c.boxes, port.p)
                        width: content.width
                        height: 46
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - buyRow.width - 40
                            elide: Text.ElideRight
                            text: product.modelData + "  ·  " + (product.info.name || "")
                            color: "#e8e8ee"
                            font { pixelSize: 14; weight: Font.Bold }
                        }
                        Row {
                            id: buyRow
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            PillButton {
                                text: "Box " + Progress.format(product.box)
                                fontSize: 12
                                enabledLook: port.p.berries >= product.box
                                onClicked: port.stage.buySealed(product.modelData, "box")
                            }
                            PillButton {
                                text: "Case (" + product.c.boxes + ") " + Progress.format(product.wholeCase)
                                fontSize: 12
                                enabledLook: port.p.berries >= product.wholeCase
                                onClicked: port.stage.buySealed(product.modelData, "case")
                            }
                        }
                    }
                }
            }

            // ==== cosmetics ===================================================
            Column {
                visible: port.tab === "cosmetics"
                width: parent.width
                spacing: 12
                Heading { text: "Playmats" }
                Note {
                    width: parent.width
                    text: "Real One Piece Card Game playmats behind the pack opener: the official Limited Editions, "
                          + "and the prize mats from Regionals and the Flame-Flame Fruit Coliseum. Pictures download the first time you look."
                }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: Progress.BACKDROPS.filter(b => !!b.playmat)
                        Panel {
                            id: pm
                            required property var modelData
                            readonly property bool owned: Progress.ownsCosmetic(port.p, modelData.id)
                            readonly property bool worn: Progress.backdrop(port.p).id === modelData.id
                            width: (content.width - 24) / 3
                            height: width * 0.54 + 74
                            border.color: worn ? "#ffd56b" : "#2c3550"
                            Rectangle {   // the mat
                                x: 10; y: 10
                                width: parent.width - 20
                                height: width * 0.54
                                radius: 6
                                color: "#0e1322"
                                clip: true
                                Image {
                                    id: mat
                                    anchors.fill: parent
                                    source: port.stage ? port.stage.playmatUrl(pm.modelData) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 600
                                    asynchronous: true
                                    cache: false
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: mat.status !== Image.Ready
                                    text: mat.status === Image.Loading ? "loading…" : "downloading the picture…"
                                    color: "#4a5370"
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                x: 12
                                y: parent.height - 60
                                width: parent.width - 24
                                elide: Text.ElideRight
                                text: pm.modelData.name
                                color: "#e8e8ee"
                                font { pixelSize: 13; weight: Font.Black }
                            }
                            PillButton {
                                x: 10
                                y: parent.height - 38
                                fontSize: 11
                                text: pm.worn ? "In use" : pm.owned ? "Use" : "Buy · " + Progress.format(pm.modelData.price)
                                enabledLook: !pm.worn && (pm.owned || port.p.berries >= pm.modelData.price)
                                onClicked: if (!pm.worn && !port.stage.prog(p => Progress.equipCosmetic(p, "backdrop", pm.modelData.id)))
                                               port.stage.toast("Not enough berries yet.")
                            }
                        }
                    }
                }

                Heading { text: "Colours" }
                Note { text: "Behind the pack opener." }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: Progress.BACKDROPS.filter(b => !b.playmat)
                        Panel {
                            id: bd
                            required property var modelData
                            readonly property bool owned: Progress.ownsCosmetic(port.p, modelData.id)
                            readonly property bool worn: Progress.backdrop(port.p).id === modelData.id
                            width: 180
                            height: 150
                            border.color: worn ? "#ffd56b" : "#2c3550"
                            Rectangle {   // preview
                                x: 10; y: 10
                                width: parent.width - 20
                                height: 70
                                radius: 6
                                color: bd.modelData.base
                                clip: true
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 1.2
                                    height: width
                                    radius: width / 2
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#00000000" }
                                        GradientStop { position: 0.5; color: bd.modelData.glow }
                                        GradientStop { position: 1.0; color: "#00000000" }
                                    }
                                }
                            }
                            Text {
                                x: 12; y: 88
                                text: bd.modelData.name
                                color: "#e8e8ee"
                                font { pixelSize: 14; weight: Font.Black }
                            }
                            PillButton {
                                x: 10; y: 112
                                fontSize: 11
                                text: bd.worn ? "In use" : bd.owned ? "Use" : "Buy · " + Progress.format(bd.modelData.price)
                                enabledLook: !bd.worn && (bd.owned || port.p.berries >= bd.modelData.price)
                                onClicked: if (!bd.worn && !port.stage.prog(p => Progress.equipCosmetic(p, "backdrop", bd.modelData.id)))
                                               port.stage.toast("Not enough berries yet.")
                            }
                        }
                    }
                }
                Heading { text: "Slab labels" }
                Note { text: "The label on your desktop showcase and on your graded slabs." }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: Progress.SLABS
                        Panel {
                            id: sl
                            required property var modelData
                            readonly property bool owned: Progress.ownsCosmetic(port.p, modelData.id)
                            readonly property bool worn: Progress.slabStyle(port.p).id === modelData.id
                            width: 180
                            height: 130
                            border.color: worn ? "#ffd56b" : "#2c3550"
                            Rectangle {   // preview
                                x: 10; y: 10
                                width: parent.width - 20
                                height: 50
                                radius: 4
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: sl.modelData.top }
                                    GradientStop { position: 1.0; color: sl.modelData.bottom }
                                }
                                Column {
                                    x: 8; y: 7
                                    Text { text: "Monkey.D.Luffy"; color: sl.modelData.text; font { pixelSize: 13; weight: Font.Black } }
                                    Text { text: "OP-01  ·  ROMANCE DAWN"; color: sl.modelData.sub; font { pixelSize: 9; weight: Font.Bold } }
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    text: "10"
                                    color: sl.modelData.text
                                    font { pixelSize: 20; weight: Font.Black }
                                }
                            }
                            Text {
                                x: 12; y: 68
                                text: sl.modelData.name
                                color: "#e8e8ee"
                                font { pixelSize: 14; weight: Font.Black }
                            }
                            PillButton {
                                x: 10; y: 92
                                fontSize: 11
                                text: sl.worn ? "In use" : sl.owned ? "Use" : "Buy · " + Progress.format(sl.modelData.price)
                                enabledLook: !sl.worn && (sl.owned || port.p.berries >= sl.modelData.price)
                                onClicked: if (!sl.worn && !port.stage.prog(p => Progress.equipCosmetic(p, "slab", sl.modelData.id)))
                                               port.stage.toast("Not enough berries yet.")
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- a card or slab, big ----------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: port.inspected ? 0.8 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: port.inspected = null
        }
    }
    Card {
        anchors.centerIn: parent
        visible: !!port.inspected
        width: Math.min(420, port.height * 0.8 * 0.716)
        card: port.inspected
        faceUp: true
        time: port.stage ? port.stage.t : 0
        hoverTilt: true
        onClicked: port.inspected = null
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: "← →: switch tabs   ·   P or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

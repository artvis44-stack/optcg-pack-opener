pragma ComponentBehavior: Bound
import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Your show binder at the card show (the "Your binder" button): the cards you brought. Like
// everything in the hall they show no market price (that's what your notes are for). At a
// vendor's table it's how you deal with them: pick cards and ask what they'd pay (cash) or
// give for them (trade credit), one check for the lot, then sell them, or trade them (plus
// berries if you're short) for something on their table or under it (cards they only
// trade, not on display).
Rectangle {
    id: view

    property Item stage
    property Item hall                   // CardShow: cardOf(), bought()
    property var vendor: null            // the stall you're at (null: the hall)
    property string target: ""           // the listing you'd trade for
    property var picked: ({})            // binder card id -> true
    signal close()
    signal inspect(string listingId)

    color: "#ee05070d"

    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var items: stage ? stage.showBinderItems : []
    readonly property var pickedItems: items.filter(it => !!picked[it.id])
    readonly property var under: vendor ? Progress.tradeStock(p, vendor.id) : []
    readonly property string closed: vendor ? Progress.tableClosed(p, vendor.id) : ""
    readonly property var targetListing: target ? Progress.showListing(p, target) : null
    readonly property bool targetHere: !!targetListing && !!vendor && target.split("-")[0] === vendor.id && !hall.bought(target) && !hall.taken(target)
    function asked(it) { return !!vendor && Progress.offerAsked(p, vendor.id, it); }
    function offer(it) { return asked(it) ? Progress.showOffer(p, vendor, it) : null; }
    readonly property var unasked: pickedItems.filter(it => !asked(it))
    readonly property var wanted: pickedItems.filter(it => offer(it))
    // "I've got a stack of those": the sets they're overstocked on, of the cards you've picked
    readonly property var overstocked: {
        var seen = {};
        wanted.forEach(it => { if (offer(it).overstock) seen[hall.fromText(it.card)] = true; });
        return Object.keys(seen);
    }
    readonly property int cashTotal: wanted.reduce((n, it) => n + offer(it).cash, 0)
    readonly property var quote: targetHere && wanted.length ? Progress.tradeQuote(p, vendor, targetListing, wanted) : null

    onVisibleChanged: if (visible && stage) stage.loadShowBinderMarkets()
    // a new table starts over (not every progress reload: that makes a new vendor object
    // every few seconds)
    readonly property string vendorId: vendor ? vendor.id : ""
    onVendorIdChanged: { picked = {}; target = ""; }

    function toggle(id) {
        var m = Object.assign({}, picked);
        if (m[id]) delete m[id];
        else m[id] = true;
        picked = m;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: view.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(view.width * 0.96, 1500)
        height: view.height * 0.92
        radius: 16
        color: "#151b2c"
        border.color: "#7fd1b9"
        border.width: 2
        MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

        Column {
            id: head
            x: 24; y: 18
            width: parent.width - 48
            spacing: 4
            Text {
                text: "Your binder"
                color: "#7fd1b9"
                font { pixelSize: 28; weight: Font.Black; italic: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: view.items.length + " / " + Progress.SHOW_BINDER_SIZE + " cards"
                      + (view.vendor ? "   ·   pick cards, then ask what " + view.vendor.name + " would give for them"
                                     : "   ·   walk up to a table to sell or trade")
                color: "#c8ccd6"
                font { pixelSize: 14; weight: Font.Bold }
            }
        }

        // ---- the binder: 5 × 3 pockets ----
        Rectangle {
            id: binder
            readonly property int cols: 5
            readonly property int rows: Math.ceil(Progress.SHOW_BINDER_SIZE / cols)
            readonly property real labelH: view.vendor ? 66 : 34
            readonly property real pocketW: Math.min((width - 24 - (cols - 1) * 10) / cols, ((height - 24 - (rows - 1) * 10) / rows - labelH) * 0.716)
            anchors {
                top: head.bottom; topMargin: 14
                bottom: parent.bottom; bottomMargin: 18
                left: parent.left; leftMargin: 18
            }
            width: view.vendor ? parent.width * 0.6 : parent.width - 36
            radius: 10
            color: "#1b2a4a"
            border.color: "#0a0a0a"
            border.width: 2

            Grid {
                anchors.centerIn: parent
                columns: binder.cols
                spacing: 10
                Repeater {
                    model: Progress.SHOW_BINDER_SIZE
                    Item {
                        id: pocket
                        required property int index
                        readonly property var it: view.items[index] || null
                        readonly property bool known: !!it && view.asked(it)
                        readonly property var o: it ? view.offer(it) : null
                        readonly property bool on: !!it && !!view.picked[it.id]
                        width: binder.pocketW
                        height: binder.pocketW / 0.716 + binder.labelH

                        Rectangle {   // the plastic pocket
                            width: parent.width
                            height: parent.width / 0.716
                            radius: 4
                            color: "#22ffffff"
                            border.color: pocket.on ? "#7fd1b9" : pocketMouse.containsMouse && pocket.it && view.vendor ? "#ffd56b" : "#40ffffff"
                            border.width: pocket.on ? 3 : 1
                            Card {
                                visible: !!pocket.it && !pocket.it.grade
                                anchors.centerIn: parent
                                width: parent.width - 6
                                card: pocket.it && !pocket.it.grade ? pocket.it.card : null
                                faceUp: true
                                dropShadow: false
                                time: view.stage ? view.stage.t : 0
                            }
                            Slab {
                                visible: !!pocket.it && !!pocket.it.grade
                                anchors.centerIn: parent
                                width: (parent.height - 6) / 1.64
                                card: pocket.it && pocket.it.grade ? pocket.it.card : null
                                time: view.stage ? view.stage.t : 0
                                hoverTilt: false
                            }
                            Text {
                                visible: !pocket.it
                                anchors.centerIn: parent
                                text: "empty"
                                color: "#40ffffff"
                                font { pixelSize: 12; italic: true }
                            }
                            Rectangle {   // picked
                                visible: pocket.on
                                anchors { right: parent.right; top: parent.top; margins: 4 }
                                width: 22; height: 22; radius: 11
                                color: "#7fd1b9"
                                Text { anchors.centerIn: parent; text: "✓"; color: "#0e1322"; font { pixelSize: 14; weight: Font.Black } }
                            }
                        }
                        Column {
                            y: parent.width / 0.716 + 4
                            width: parent.width
                            spacing: 2
                            visible: !!pocket.it
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: pocket.it ? (pocket.it.grade ? "Graded " + pocket.it.grade : "Raw") : ""
                                color: "#ffd56b"
                                font { pixelSize: 13; weight: Font.Black }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: pocket.it ? Tiers.displayName(pocket.it.card) : ""
                                color: "#c8ccd6"
                                font.pixelSize: 11
                            }
                            Text {   // what this vendor offers for it
                                visible: !!view.vendor
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: !pocket.known ? "no offer yet" : !pocket.o ? "not interested"
                                      : "cash " + Progress.format(pocket.o.cash) + "\ntrade " + Progress.format(pocket.o.credit)
                                color: !pocket.o ? "#7a8090" : "#9ad8ff"
                                font { pixelSize: 11; weight: Font.Bold }
                            }
                        }
                        MouseArea {
                            id: pocketMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !!pocket.it && !!view.vendor
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.toggle(pocket.it.id)
                        }
                    }
                }
            }
            Text {
                visible: !view.items.length
                anchors.centerIn: parent
                width: parent.width * 0.7
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "You didn't bring any cards. Fill your show binder in the Port (the card shop tab) before the next show."
                color: "#c8ccd6"
                font { pixelSize: 16; italic: true }
            }
        }

        // ---- dealing with the vendor ----
        Text {   // a table you can't deal with
            visible: !!view.vendor && !!view.closed
            anchors { top: binder.top; left: binder.right; leftMargin: 20; right: parent.right; rightMargin: 20 }
            wrapMode: Text.WordWrap
            text: view.closed === "removed" ? "Security took this table down. There's nobody here to deal with."
                                            : "\"After what you pulled? Not today.\" They won't buy or trade with you for the rest of the show."
            color: "#ff8a7a"
            font { pixelSize: 16; weight: Font.Bold }
        }
        Flickable {
            id: deal
            visible: !!view.vendor && !view.closed
            anchors {
                top: binder.top; bottom: binder.bottom
                left: binder.right; leftMargin: 20
                right: parent.right; rightMargin: 20
            }
            contentHeight: dealCol.height + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: dealCol
                width: deal.width
                spacing: 10

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: view.vendor ? view.vendor.name : ""
                    color: "#fff6e0"
                    font { pixelSize: 22; weight: Font.Black }
                }

                // sell
                Text { text: "Sell"; color: "#ffd56b"; font { pixelSize: 18; weight: Font.Black } }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !view.pickedItems.length ? "Pick cards in your binder, then ask what they'd give for them."
                          : view.unasked.length && !view.wanted.length ? "Ask what they'd give for " + (view.unasked.length > 1 ? "these" : "it") + ": one check."
                          : !view.wanted.length ? "\"Not really what I buy.\""
                          : "They'd pay " + Progress.format(view.cashTotal) + " for " + view.wanted.length + " card" + (view.wanted.length > 1 ? "s" : "")
                            + (view.unasked.length ? " (you haven't asked about the rest)"
                               : view.wanted.length < view.pickedItems.length ? " (not interested in the rest)" : "") + "."
                            + (view.overstocked.length ? "  \"I've got a stack of " + view.overstocked.join(" and ") + " already.\"" : "")
                    color: "#e8e8ee"
                    font.pixelSize: 14
                }
                PillButton {
                    visible: view.unasked.length > 0
                    text: "Ask what they'd give  (1 check, " + view.hall.checksLeft + " left)"
                    accent: "#ffd56b"
                    enabledLook: view.hall.checksLeft > 0
                    onClicked: view.stage.askOffers(view.vendor.id, view.unasked.map(it => it.id))
                }
                PillButton {
                    visible: view.wanted.length > 0
                    text: "Sell for " + Progress.format(view.cashTotal)
                    accent: "#7fd1b9"
                    onClicked: {
                        if (view.stage.sellAtShow(view.vendor.id, view.wanted.map(it => it.id))) view.picked = {};
                    }
                }

                Item { width: 1; height: 6 }

                // trade
                Text { text: "Trade"; color: "#ffd56b"; font { pixelSize: 18; weight: Font.Black } }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: view.under.length ? "Under the table: cards they only trade, not for sale. Or pick something off their table and choose \"Trade for it\"."
                                            : "Pick something off their table and choose \"Trade for it\"."
                    color: "#9aa0ad"
                    font.pixelSize: 13
                }
                Flow {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: view.under
                        Column {
                            id: hidden
                            required property var modelData
                            readonly property bool gone: view.hall.bought(modelData.id)
                            readonly property bool chosen: view.target === modelData.id
                            spacing: 4
                            opacity: gone ? 0.4 : 1
                            Item {
                                width: 96
                                height: hidden.modelData.grade ? 96 * 1.64 : 96 / 0.716
                                Loader {
                                    anchors.bottom: parent.bottom
                                    sourceComponent: hidden.modelData.grade ? hiddenSlab : hiddenCard
                                }
                                Component {
                                    id: hiddenCard
                                    Card { width: 96; card: view.hall.cardOf(hidden.modelData); faceUp: true; time: view.stage ? view.stage.t : 0 }
                                }
                                Component {
                                    id: hiddenSlab
                                    Slab { width: 96; card: view.hall.cardOf(hidden.modelData); time: view.stage ? view.stage.t : 0; hoverTilt: false }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    radius: 6
                                    color: "transparent"
                                    border.color: hidden.chosen ? "#7fd1b9" : "transparent"
                                    border.width: 2
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !hidden.gone
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.target = hidden.chosen ? "" : hidden.modelData.id
                                }
                            }
                            Text {
                                width: 96
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: hidden.gone ? "TRADED" : Progress.format(hidden.modelData.ask)
                                color: hidden.gone ? "#ff8a7a" : "#fff6d8"
                                font { pixelSize: 13; weight: Font.Black }
                            }
                            Text {
                                width: 96
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: "Look closer"
                                color: "#c8a0ff"
                                font { pixelSize: 11; weight: Font.Bold; underline: true }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.inspect(hidden.modelData.id)
                                }
                            }
                        }
                    }
                }

                Rectangle {   // the trade on the table
                    width: parent.width
                    height: tradeCol.height + 24
                    radius: 10
                    color: "#0e1322"
                    border.color: view.quote ? "#7fd1b9" : "#2c3550"
                    Column {
                        id: tradeCol
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 6
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: view.targetHere ? "For: " + Tiers.displayName(view.targetListing.card)
                                                    + (view.targetListing.grade ? " (graded " + view.targetListing.grade + ")" : "")
                                                    + (view.targetListing.tradeOnly ? "  ·  under the table" : "")
                                                  : "Choose what you want: a card under the table, or \"Trade for it\" on one from their table."
                            color: view.targetHere ? "#fff6e0" : "#9aa0ad"
                            font { pixelSize: 15; weight: Font.Bold }
                        }
                        Text {
                            width: parent.width
                            visible: view.targetHere
                            wrapMode: Text.WordWrap
                            text: !view.targetHere ? ""
                                  : view.unasked.length && !view.wanted.length ? "Ask what they'd give for the cards you've picked first (under Sell)."
                                  : !view.pickedItems.length ? "Their price: " + Progress.format(view.targetListing.tradeOnly ? view.targetListing.ask : Progress.showPrice(view.p, view.targetListing))
                                                               + ". Now pick the cards you'd give."
                                  : !view.quote ? "\"Not really what I'm after.\" They don't want any of those."
                                  : "Your cards count for " + Progress.format(view.quote.credit) + " against their " + Progress.format(view.quote.price) + ".  "
                                    + (view.quote.pay ? "You'd add " + Progress.format(view.quote.pay) + "."
                                       : view.quote.change ? "They'd give you " + Progress.format(view.quote.change) + " back."
                                       : view.quote.credit > view.quote.price ? "\"No change, take it or leave it.\" They keep the difference."
                                       : "Even.")
                            color: view.quote && view.quote.credit > view.quote.price && !view.quote.change ? "#ff9a7a" : "#e8e8ee"
                            font.pixelSize: 14
                        }
                        PillButton {
                            visible: !!view.quote
                            text: view.quote ? "Trade" + (view.quote.pay ? " + " + Progress.format(view.quote.pay) : "") : ""
                            accent: "#7fd1b9"
                            enabledLook: !!view.quote && view.quote.ok
                            onClicked: {
                                if (view.quote && view.quote.ok && view.stage.tradeAtShow(view.vendor.id, view.target, view.wanted.map(it => it.id))) {
                                    view.picked = {};
                                    view.target = "";
                                }
                            }
                        }
                    }
                }
            }
        }

        PillButton {
            anchors { right: parent.right; rightMargin: 20; top: parent.top; topMargin: 20 }
            text: "Close"
            fontSize: 13
            accent: "#9aa0ad"
            onClicked: view.close()
        }
    }
}

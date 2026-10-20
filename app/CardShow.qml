import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The card show (K, on show days): vendor tables of mostly chase cards, raw and
// graded (Progress.makeShowStock). No market prices anywhere while you're here:
// you have to know what things are worth. Click a card to look at it (tilt it:
// a real foil shimmers), look closer with the loupe (a few a visit), haggle once,
// buy. Some vendors are scammers; you find out who when you leave (Esc), and the
// recap shows what you really came home with.
Item {
    id: show

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var s: Progress.showState(p)
    readonly property var stock: s.stock || []
    readonly property var recap: stage ? stage.showRecap : null
    property string inspected: ""        // the listing shown big
    property bool confirmLeave: false
    property string note: ""             // the last close look or haggle, for the inspected card

    readonly property var listing: inspected ? Progress.showListing(p, inspected) : null
    readonly property var vendor: inspected ? Progress.showVendor(p, inspected) : null

    function back() {
        if (recap) stage.closeShow();
        else if (inspected) inspected = "";
        else if (!confirmLeave) confirmLeave = true;
        else leave();
    }

    function leave() {
        confirmLeave = false;
        inspected = "";
        stage.leaveShow();
    }

    function open(id) {
        inspected = id;
        note = (s.looked || {})[id] ? Progress.showListing(p, id).look : "";
    }

    onVisibleChanged: if (visible) { inspected = ""; confirmLeave = false; note = ""; }

    // a listing as a card the Card / Slab components draw (a fake looks a little off)
    function cardOf(x) {
        if (!x || !stage) return null;
        return Object.assign({}, stage.localCard(Object.assign({ key: x.key }, x.card)), { grade: x.grade, fake: x.fake });
    }

    function priceText(x) {
        var now = Progress.showPrice(p, x);
        return now !== x.ask ? Progress.format(now) + "  (was " + Progress.format(x.ask) + ")" : Progress.format(x.ask);
    }

    readonly property var kindName: ({ honest: "an honest dealer", bargain: "a bargain table", premium: "a premium dealer", scammer: "a SCAMMER" })
    readonly property var kindColor: ({ honest: "#7fd1b9", bargain: "#ffd56b", premium: "#c8a0ff", scammer: "#ff8a7a" })

    Rectangle {
        anchors.fill: parent
        color: "#0a0612"
        opacity: 0.97
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    component Note: Text {
        color: "#9aa0ad"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    // ---- header ---------------------------------------------------------------------
    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: 52   // under the wallet bar
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The Card Show"
            color: "#ff9ad5"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Progress.format(show.p.berries) + "   ·   " + show.stock.length + " tables   ·   close looks left: "
                  + Math.max(0, Progress.SHOW_LOOKS - (show.s.looks || 0)) + " / " + Progress.SHOW_LOOKS
                  + "   ·   bought " + Object.keys(show.s.bought || {}).length
            color: "#fff6e0"
            font { pixelSize: 16; weight: Font.Bold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No prices to look up in here: know your market. Some vendors are honest, some aren't."
            color: "#9aa0ad"
            font.pixelSize: 13
        }
        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !show.recap
            text: show.confirmLeave ? "Leave? You can't come back until the next show. Yes, leave" : "Leave the show (Esc)"
            fontSize: 13
            accent: show.confirmLeave ? "#ff8a7a" : "#9aa0ad"
            onClicked: show.confirmLeave ? show.leave() : show.confirmLeave = true
        }
    }

    // ---- the tables -----------------------------------------------------------------
    Flickable {
        id: body
        visible: !show.recap
        anchors {
            top: header.bottom; topMargin: 16
            bottom: parent.bottom; bottomMargin: 36
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(show.width * 0.94, 1240)
        contentHeight: tables.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: tables
            width: body.width
            spacing: 14
            Repeater {
                model: show.stock
                Rectangle {
                    id: table
                    required property var modelData
                    width: tables.width
                    height: tableCol.height + 24
                    radius: 10
                    color: "#161020"
                    border.color: "#3a2c4a"
                    Column {
                        id: tableCol
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 10
                        Text {
                            text: table.modelData.name + (table.modelData.blurb ? "   ·   \"" + table.modelData.blurb + "\"" : "")
                            color: "#ffd56b"
                            font { pixelSize: 16; weight: Font.Black }
                        }
                        Flow {
                            width: parent.width
                            spacing: 14
                            Repeater {
                                model: table.modelData.listings
                                Column {
                                    id: lot
                                    required property var modelData
                                    readonly property bool sold: !!(show.s.bought || {})[modelData.id]
                                    width: 118
                                    spacing: 3
                                    opacity: sold ? 0.35 : 1
                                    Loader {
                                        width: 118
                                        readonly property var c: show.cardOf(lot.modelData)
                                        sourceComponent: lot.modelData.grade ? smallSlab : smallCard
                                        Component {
                                            id: smallCard
                                            Card { width: 118; card: parent.c; faceUp: true; time: show.stage ? show.stage.t : 0; hoverTilt: true
                                                   onClicked: show.open(lot.modelData.id) }
                                        }
                                        Component {
                                            id: smallSlab
                                            Slab { width: 118; card: parent.c; time: show.stage ? show.stage.t : 0
                                                   onClicked: show.open(lot.modelData.id) }
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: lot.modelData.card.set + " · " + Tiers.tierOf(lot.modelData.card).label
                                        color: Tiers.tierOf(lot.modelData.card).color
                                        font { pixelSize: 11; weight: Font.Bold }
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: lot.modelData.grade ? "Graded " + lot.modelData.grade : lot.modelData.claim
                                        color: "#c8ccd6"
                                        font.pixelSize: 11
                                    }
                                    PillButton {
                                        text: lot.sold ? "Bought" : Progress.format(Progress.showPrice(show.p, lot.modelData))
                                        fontSize: 12
                                        enabledLook: !lot.sold
                                        onClicked: if (!lot.sold) show.open(lot.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- one card, close up -----------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: !!show.listing && !show.recap
        color: "#ee05070d"
        MouseArea {
            anchors.fill: parent
            onClicked: show.inspected = ""
        }
        Row {
            anchors.centerIn: parent
            spacing: 40
            Loader {
                anchors.verticalCenter: parent.verticalCenter
                readonly property var c: show.cardOf(show.listing)
                sourceComponent: show.listing && show.listing.grade ? bigSlab : bigCard
                Component {
                    id: bigCard
                    Card { width: Math.min(360, show.height * 0.62 * 0.716); card: parent.c; faceUp: true; hoverTilt: true
                           time: show.stage ? show.stage.t : 0 }
                }
                Component {
                    id: bigSlab
                    Slab { width: Math.min(330, show.height * 0.55 * 0.716); card: parent.c; time: show.stage ? show.stage.t : 0 }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: 420
                spacing: 12
                readonly property var lst: show.listing
                readonly property bool sold: !!lst && !!(show.s.bought || {})[lst.id]
                readonly property var haggled: lst ? (show.s.haggled || {})[lst.id] : null
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: parent.lst ? Tiers.displayName(parent.lst.card) : ""
                    color: "#fff6e0"
                    font { pixelSize: 24; weight: Font.Black; italic: true }
                }
                Text {
                    text: parent.lst ? parent.lst.card.set + "  ·  " + parent.lst.card.id + "  ·  " + Tiers.tierOf(parent.lst.card).label : ""
                    color: parent.lst ? Tiers.tierOf(parent.lst.card).color : "white"
                    font { pixelSize: 15; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !parent.lst ? "" : parent.lst.grade ? "In a slab, graded " + parent.lst.grade + "."
                          : "Raw. The vendor says: \"" + parent.lst.claim + "\""
                    color: "#c8ccd6"
                    font.pixelSize: 14
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: show.vendor ? "At " + show.vendor.name + "'s table" : ""
                    color: "#9aa0ad"
                    font.pixelSize: 13
                }
                Text {
                    text: parent.lst ? (parent.sold ? "Bought for " + Progress.format(show.s.bought[parent.lst.id].price) : "Asking " + show.priceText(parent.lst)) : ""
                    color: "#ffd56b"
                    font { pixelSize: 22; weight: Font.Black }
                }
                Note {
                    width: parent.width
                    visible: show.note !== ""
                    text: show.note
                    color: "#e6d6ff"
                    font.italic: true
                }
                Note {
                    width: parent.width
                    visible: !parent.sold
                    text: "Tilt the card with the mouse: a real foil catches the light. The loupe tells you more."
                }
                Row {
                    spacing: 10
                    visible: !parent.sold
                    PillButton {
                        text: "Buy  " + (show.listing ? Progress.format(Progress.showPrice(show.p, show.listing)) : "")
                        enabledLook: !!show.listing && show.p.berries >= Progress.showPrice(show.p, show.listing)
                        onClicked: if (show.stage.buyAtShow(show.inspected)) show.note = ""
                    }
                    PillButton {
                        readonly property bool looked: !!show.listing && !!(show.s.looked || {})[show.listing.id]
                        text: looked ? "Looked closer" : "Look closer (" + Math.max(0, Progress.SHOW_LOOKS - (show.s.looks || 0)) + " left)"
                        accent: "#c8a0ff"
                        enabledLook: !looked && (show.s.looks || 0) < Progress.SHOW_LOOKS
                        onClicked: {
                            if (looked) return;
                            var id = show.inspected, t = "";
                            show.stage.prog(q => { t = Progress.lookCloser(q, id, Date.now()); return []; });
                            show.note = t ? "Under the loupe: " + t : "You've had all the close looks the vendors will put up with.";
                        }
                    }
                }
                Row {
                    spacing: 8
                    visible: !parent.sold && !parent.haggled
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Make an offer (once):"
                        color: "#c8ccd6"
                        font.pixelSize: 13
                    }
                    Repeater {
                        model: Progress.SHOW_HAGGLE
                        PillButton {
                            required property real modelData
                            text: Math.round(modelData * 100) + "% off"
                            fontSize: 12
                            accent: "#7fd1b9"
                            onClicked: {
                                var id = show.inspected, pct = modelData, ok = null;
                                show.stage.prog(q => { ok = Progress.haggle(q, id, pct, Date.now()); return []; });
                                if (ok === null) return;
                                show.stage.sfx(ok ? "coin" : "flip");
                                show.note = ok ? "\"Deal.\" It's yours for " + Progress.format(Progress.showPrice(show.stage.progress, Progress.showListing(show.stage.progress, id))) + " if you want it."
                                               : "\"No, that's my price.\" It stays at " + Progress.format(Progress.showListing(show.stage.progress, id).ask) + ".";
                            }
                        }
                    }
                }
                Text {
                    visible: !!parent.haggled && !parent.sold
                    text: parent.haggled ? (parent.haggled.ok ? "Your offer of " + Math.round(parent.haggled.pct * 100) + "% off was taken."
                                                              : "Your offer was turned down.") : ""
                    color: "#9aa0ad"
                    font.pixelSize: 13
                }
                PillButton {
                    text: "Back to the tables"
                    accent: "#9aa0ad"
                    onClicked: show.inspected = ""
                }
            }
        }
    }

    // ---- the recap: home again ------------------------------------------------------------
    Flickable {
        visible: !!show.recap
        anchors {
            top: header.bottom; topMargin: 4
            bottom: parent.bottom; bottomMargin: 36
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(show.width * 0.9, 900)
        contentHeight: recapCol.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: recapCol
            width: parent.width
            spacing: 10
            readonly property var r: show.recap
            Text {
                text: "Home from the show"
                color: "#ffd56b"
                font { pixelSize: 22; weight: Font.Black }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !!recapCol.r
                readonly property int net: recapCol.r ? recapCol.r.worth - recapCol.r.paid : 0
                text: !recapCol.r ? "" : !recapCol.r.items.length ? "You didn't buy anything this time."
                      : "You paid " + Progress.format(recapCol.r.paid) + " for cards worth " + Progress.format(recapCol.r.worth)
                        + " at market:  " + (net >= 0 ? "+" : "−") + Progress.format(Math.abs(net)).slice(1) + " ฿"
                        + (recapCol.r.fakes ? "   ·   " + recapCol.r.fakes + " fake" + (recapCol.r.fakes > 1 ? "s" : "") + " (they're in the vault)" : "")
                        + (recapCol.r.steals ? "   ·   " + recapCol.r.steals + " steal" + (recapCol.r.steals > 1 ? "s" : "") : "")
                color: net >= 0 ? "#7fd1b9" : "#ff8a7a"
                font { pixelSize: 16; weight: Font.Bold }
            }
            Repeater {
                model: recapCol.r ? recapCol.r.items : []
                Rectangle {
                    required property var modelData
                    width: recapCol.width
                    height: 46
                    radius: 8
                    color: "#161020"
                    border.color: modelData.listing.fake ? "#ff8a7a" : "#3a2c4a"
                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.5
                        elide: Text.ElideRight
                        text: Tiers.displayName(modelData.listing.card) + "  ·  " + modelData.listing.card.set
                              + (modelData.listing.grade ? "  ·  graded " + modelData.listing.grade : "")
                              + "  ·  from " + (modelData.vendor ? modelData.vendor.name : "")
                        color: "#e8e8ee"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "paid " + Progress.format(modelData.paid) + "   ·   "
                              + (modelData.listing.fake ? "FAKE: worth nothing"
                                 : "worth " + Progress.format(modelData.listing.value)
                                   + (!modelData.listing.grade && modelData.listing.cond && modelData.listing.claim === Progress.SHOW_CLAIM.pristine
                                      && modelData.listing.cond !== "pristine" ? "  (really " + Progress.CONDITION[modelData.listing.cond].name + ")" : ""))
                        color: modelData.listing.fake ? "#ff8a7a" : modelData.paid <= modelData.listing.value ? "#7fd1b9" : "#ffb347"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                }
            }
            Text {
                text: "Who was who"
                color: "#ffd56b"
                font { pixelSize: 18; weight: Font.Black }
                topPadding: 8
            }
            Repeater {
                model: recapCol.r ? recapCol.r.vendors : []
                Text {
                    required property var modelData
                    text: modelData.name + ": " + show.kindName[modelData.kind]
                    color: show.kindColor[modelData.kind]
                    font { pixelSize: 14; weight: Font.Bold }
                }
            }
            PillButton {
                text: "Done"
                onClicked: show.stage.closeShow()
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
        text: show.recap ? "Esc or Done: back"
              : show.inspected ? "Move the mouse to tilt   ·   click outside or Esc: back to the tables"
              : "Click a card to look at it   ·   Esc: leave the show"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// A table's binder at the card show (Progress.tableBinder): the cheap singles they keep under the
// table, nine to a page, two pages open at a time. Flip through (‹ ›, the arrow keys or the
// wheel), click a card to look at it, buy it. "Missing only" leaves out what you already have.
// No market prices here either, but you do know your own collection. A bargain table's binder
// can have a chase card in it at a common's price: nothing marks it, you have to spot it.
Rectangle {
    id: view

    property Item stage
    property Item hall                    // CardShow: fromText(), binderPool
    property var vendor: null             // the table
    property bool missingOnly: false
    property int spread: 0                // which two pages are open (0: pages 1 and 2)
    property string selectedId: ""
    property var entries: []
    signal close()

    color: "#ee05070d"

    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var mine: Progress.binderBought(p)
    readonly property var cards: stage ? stage.collection.cards || {} : ({})
    function owned(e) { return !!cards[e.key] && (cards[e.key].count || 0) > 0; }
    readonly property var shown: missingOnly ? entries.filter(e => !owned(e) || !!mine[e.id]) : entries
    readonly property int perPage: Progress.TABLE_BINDER.perPage
    readonly property int pages: Math.max(1, Math.ceil(shown.length / perPage))
    readonly property int spreads: Math.ceil(pages / 2)
    readonly property var selected: selectedId ? entries.filter(e => e.id === selectedId)[0] || null : null
    readonly property string closed: vendor ? Progress.tableClosed(p, vendor.id) : ""

    // deal the binder when it's opened (the pool's read once a visit, by the hall)
    readonly property string dealKey: visible && vendor ? Progress.showState(p).day + " " + vendor.id + " " + vendor.name : ""
    onDealKeyChanged: refresh()
    function refresh() {
        if (!dealKey) return;
        if (!hall.binderPool) hall.binderPool = stage.showPool();
        entries = Progress.tableBinder(p, vendor.id, hall.binderPool);
        spread = 0;
        selectedId = "";
    }
    onMissingOnlyChanged: spread = 0

    function step(d) {
        spread = Math.max(0, Math.min(spreads - 1, spread + d));
    }

    function localCard(e) {
        return stage ? stage.localCard(Object.assign({ key: e.key }, e.card)) : e.card;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: view.close()
        onWheel: wheel => view.step(wheel.angleDelta.y < 0 ? 1 : -1)
    }

    Column {
        id: head
        anchors { top: parent.top; topMargin: 56; horizontalCenter: parent.horizontalCenter }
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.vendor ? view.vendor.name + "'s binder" : ""
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !view.entries.length ? "Nothing in it today."
                  : view.shown.length + (view.missingOnly ? " you're missing, of " + view.entries.length : "") + " cards   ·   pages "
                    + (view.spread * 2 + 1) + (view.spread * 2 + 2 <= view.pages ? "–" + (view.spread * 2 + 2) : "") + " of " + view.pages
                    + "   ·   " + Progress.format(view.p.berries)
            color: "#e8e8ee"
            font { pixelSize: 15; weight: Font.Bold }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            PillButton {
                text: view.missingOnly ? "Missing only: on" : "Missing only: off"
                fontSize: 13
                accent: view.missingOnly ? "#7fd1b9" : "#9aa0ad"
                onClicked: view.missingOnly = !view.missingOnly
            }
            PillButton {
                text: "Close"
                fontSize: 13
                accent: "#9aa0ad"
                onClicked: view.close()
            }
        }
    }

    // ---- the binder, open: two pages of 3 × 3 pockets, the rings down the middle ----
    Rectangle {
        id: book
        readonly property real sideW: Math.min(360, parent.width * 0.26)
        readonly property real pocketW: Math.min((parent.width - sideW - 160) / 6 - 10, (height - 60) / 3 / 1.4 * 0.716)
        anchors { top: head.bottom; topMargin: 16; bottom: parent.bottom; bottomMargin: 44 }
        x: (parent.width - width - sideW - 24) / 2
        width: pocketW * 6 + 10 * 4 + 40 * 2 + 50
        radius: 14
        color: "#3a2418"
        border.color: "#1a0e08"
        border.width: 3
        MouseArea { anchors.fill: parent; onWheel: wheel => view.step(wheel.angleDelta.y < 0 ? 1 : -1) }

        Row {
            anchors.centerIn: parent
            spacing: 50
            Repeater {
                model: 2
                Rectangle {   // a page
                    id: page
                    required property int index
                    readonly property int number: view.spread * 2 + index          // 0-based
                    readonly property int first: number * view.perPage
                    width: book.pocketW * 3 + 10 * 2 + 30
                    height: book.pocketW / 0.716 * 3 + 32 * 3 + 10 * 2 + 30
                    radius: 6
                    color: "#1c1c22"
                    border.color: "#0a0a0a"
                    opacity: number < view.pages ? 1 : 0.35
                    Grid {
                        anchors.centerIn: parent
                        columns: 3
                        spacing: 10
                        Repeater {
                            model: view.perPage
                            Item {
                                id: pocket
                                required property int index
                                readonly property var e: view.shown[page.first + index] || null
                                readonly property bool yours: !!e && !!view.mine[e.id]
                                readonly property bool have: !!e && view.owned(e)
                                width: book.pocketW
                                height: book.pocketW / 0.716 + 32
                                Rectangle {   // the sleeve
                                    width: parent.width
                                    height: parent.width / 0.716
                                    radius: 3
                                    color: "#18ffffff"
                                    border.color: pocket.e && view.selectedId === pocket.e.id ? "#ffd56b"
                                                  : pocketMouse.containsMouse && pocket.e ? "#c8a060" : "#30ffffff"
                                    border.width: pocket.e && view.selectedId === pocket.e.id ? 3 : 1
                                    Card {
                                        visible: !!pocket.e
                                        anchors.centerIn: parent
                                        width: parent.width - 6
                                        card: pocket.e ? view.localCard(pocket.e) : null
                                        faceUp: true
                                        dropShadow: false
                                        time: 0
                                        opacity: pocket.yours ? 0.35 : 1
                                    }
                                    Rectangle {   // you've got one already
                                        visible: !!pocket.e && pocket.have && !pocket.yours
                                        anchors { left: parent.left; top: parent.top; margins: 4 }
                                        width: haveText.implicitWidth + 10; height: 18; radius: 9
                                        color: "#cc14171f"
                                        Text { id: haveText; anchors.centerIn: parent; text: "have"; color: "#9aa0ad"; font { pixelSize: 10; weight: Font.Bold } }
                                    }
                                }
                                Rectangle {   // the sticker on the sleeve
                                    visible: !!pocket.e
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                                    width: tag.implicitWidth + 12
                                    height: 20
                                    radius: 3
                                    rotation: (pocket.index % 3 - 1) * 2
                                    color: pocket.yours ? "#2f6b46" : "#f4f1ea"
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        text: pocket.yours ? "YOURS" : pocket.e ? Progress.format(pocket.e.ask) : ""
                                        color: pocket.yours ? "white" : "#1a1a1a"
                                        font { pixelSize: 12; weight: Font.Black }
                                    }
                                }
                                MouseArea {
                                    id: pocketMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !!pocket.e
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.selectedId = pocket.e.id
                                }
                            }
                        }
                    }
                    Text {
                        anchors { bottom: parent.bottom; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                        text: page.number < view.pages ? String(page.number + 1) : ""
                        color: "#5a5a6a"
                        font.pixelSize: 11
                    }
                }
            }
        }
        Column {   // the rings
            anchors.centerIn: parent
            spacing: (parent.height - 3 * 26) / 4
            Repeater {
                model: 3
                Rectangle { width: 26; height: 26; radius: 13; color: "transparent"; border.color: "#c8ccd6"; border.width: 4 }
            }
        }
        PillButton {
            anchors { verticalCenter: parent.verticalCenter; right: parent.left; rightMargin: 8 }
            visible: view.spread > 0
            text: "‹"
            onClicked: view.step(-1)
        }
        PillButton {
            anchors { verticalCenter: parent.verticalCenter; left: parent.right; leftMargin: 8 }
            visible: view.spread < view.spreads - 1
            text: "›"
            onClicked: view.step(1)
        }
    }

    // ---- the card you're looking at ----
    Rectangle {
        anchors { top: book.top; bottom: book.bottom; left: book.right; leftMargin: 56 }
        width: book.sideW - 32
        radius: 12
        color: "#151b2c"
        border.color: "#3a2c4a"
        MouseArea { anchors.fill: parent }
        Text {
            visible: !view.selected
            anchors.centerIn: parent
            width: parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: view.closed ? "This table won't deal with you any more today."
                  : "Click a card to take it out of its sleeve. Everything in here is cheap: look for what you're missing."
            color: "#9aa0ad"
            font { pixelSize: 14; italic: true }
        }
        Flickable {
            visible: !!view.selected
            anchors { fill: parent; margins: 16 }
            contentHeight: side.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: side
                width: parent.width
                spacing: 8
                readonly property var e: view.selected
                readonly property bool yours: !!e && !!view.mine[e.id]
                Card {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width * 0.8, 220)
                    card: side.e ? view.localCard(side.e) : null
                    faceUp: true
                    hoverTilt: true
                    time: view.stage ? view.stage.t : 0
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: side.e ? Tiers.displayName(side.e.card) : ""
                    color: "#fff6e0"
                    font { pixelSize: 20; weight: Font.Black; italic: true }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: side.e ? view.hall.fromText(side.e.card) + "  ·  " + side.e.card.id + "  ·  " + Tiers.tierOf(side.e.card).label : ""
                    color: side.e ? Tiers.tierOf(side.e.card).color : "white"
                    font { pixelSize: 13; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: side.e ? "Raw. The sticker says: \"" + side.e.claim + "\"" : ""
                    color: "#c8ccd6"
                    font.pixelSize: 13
                }
                Text {
                    readonly property var c: side.e ? view.cards[side.e.key] : null
                    text: !side.e ? "" : c && c.count ? "You have " + c.count + " already." : "You don't have this one."
                    color: c && c.count ? "#9aa0ad" : "#7fd1b9"
                    font { pixelSize: 14; weight: Font.Bold }
                }
                Text {
                    text: !side.e ? "" : side.yours ? "Yours: paid " + Progress.format(view.mine[side.e.id].price) : Progress.format(side.e.ask)
                    color: "#ffd56b"
                    font { pixelSize: 24; weight: Font.Black }
                }
                PillButton {
                    visible: !!side.e && !side.yours && !view.closed
                    text: side.e ? "Buy  " + Progress.format(side.e.ask) : ""
                    enabledLook: !!side.e && view.p.berries >= side.e.ask
                    onClicked: view.stage.buyFromBinder(side.e)
                }
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: "‹ › or the wheel: turn the page   ·   click a card: take it out   ·   Esc: close the binder"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

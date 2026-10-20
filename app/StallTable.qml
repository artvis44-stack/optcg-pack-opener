pragma ComponentBehavior: Bound
import QtQuick
import "progress.js" as Progress

// One vendor's table at the card show, from above: a glass display case of slabs at the
// back, sealed product stacked beside it, open binders of raw cards (nine-pocket pages)
// at the front, and the usual clutter. Click anything to pick it up.
Item {
    id: stall

    property Item owner                // CardShow: cardOf(), bought(), the stage
    property var vendor                // the stall: { name, blurb, kind, vintage, listings }
    property color cloth: "#7a2230"
    signal picked(string id)

    readonly property var items: vendor ? vendor.listings : []
    readonly property var slabs: items.filter(x => x.grade && !x.sealed)
    readonly property var raws: items.filter(x => !x.grade && !x.sealed)
    readonly property var sealedItems: items.filter(x => x.sealed)
    readonly property real time: owner && owner.stage ? owner.stage.t : 0

    readonly property real tableW: width
    readonly property real tableH: height
    readonly property real m: tableW * 0.025

    function price(x) { return Progress.format(Progress.showPrice(owner.p, x)); }

    // a small price sticker (SOLD once it's gone)
    component Sticker: Rectangle {
        id: sticker
        property var listing
        readonly property bool sold: !!listing && stall.owner.bought(listing.id)
        width: stickerText.implicitWidth + 8
        height: stickerText.implicitHeight + 3
        radius: 2
        color: sold ? "#c8433a" : "#fff6d8"
        border.color: "#40000000"
        Text {
            id: stickerText
            anchors.centerIn: parent
            text: sticker.sold ? "SOLD" : sticker.listing ? stall.price(sticker.listing) : ""
            color: sticker.sold ? "white" : "#1a1a1a"
            font { pixelSize: Math.max(8, stall.tableW * 0.0085); weight: Font.Black }
        }
    }

    // ---- the table ------------------------------------------------------------------------
    Item {
        id: table
        width: stall.tableW
        height: stall.tableH
        y: stall.height - height

        Rectangle {   // the cloth
            anchors.fill: parent
            radius: 6
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.darker(stall.cloth, 1.35) }
                GradientStop { position: 1; color: Qt.lighter(stall.cloth, 1.15) }
            }
            Repeater {   // folds in the cloth
                model: 7
                Rectangle {
                    required property int index
                    x: (index + 0.5) * table.width / 7
                    width: 2
                    height: table.height
                    color: "#000000"
                    opacity: 0.06
                }
            }
        }

        // the glass display case: slabs laid flat in rows
        Rectangle {
            id: glassCase
            readonly property int n: stall.slabs.length
            readonly property int rows: n > 13 ? 2 : 1
            readonly property int cols: Math.max(1, Math.ceil(n / rows))
            readonly property real pad: stall.m * 0.6
            readonly property real slabW: Math.min(120, (width - pad * (cols + 1)) / cols, (height - pad * (rows + 1)) / rows * 0.62)
            x: stall.m
            y: stall.m
            width: stall.tableW * (stall.sealedItems.length ? 0.66 : 0.95)
            height: stall.tableH * 0.27
            radius: 6
            color: "#15171d"
            border.color: "#b8c0cc"
            border.width: 3
            visible: n > 0
            Grid {
                anchors.centerIn: parent
                columns: glassCase.cols
                spacing: glassCase.pad
                Repeater {
                    model: stall.slabs
                    Item {
                        id: lying
                        required property var modelData
                        width: glassCase.slabW
                        height: glassCase.slabW / 0.62
                        opacity: stall.owner.bought(modelData.id) ? 0.45 : 1
                        Slab {
                            width: parent.width
                            card: stall.owner.cardOf(lying.modelData)
                            time: stall.time
                            hoverTilt: false
                        }
                        MouseArea {   // (a slab without its hover tilt doesn't take clicks itself)
                            id: slabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stall.picked(lying.modelData.id)
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: 6
                            color: "transparent"
                            border.color: "#ffd56b"
                            border.width: 2
                            visible: slabMouse.containsMouse
                        }
                        Sticker {
                            listing: lying.modelData
                            anchors { right: parent.right; bottom: parent.bottom; rightMargin: -4; bottomMargin: 4 }
                            rotation: -6
                        }
                    }
                }
            }
            Rectangle {   // the glass: a sheen across the top
                anchors.fill: parent
                radius: 6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#00ffffff" }
                    GradientStop { position: 0.35; color: "#16ffffff" }
                    GradientStop { position: 0.5; color: "#00ffffff" }
                    GradientStop { position: 0.75; color: "#0cffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                }
            }
        }

        // sealed product, stacked beside the case
        Item {
            id: sealedArea
            visible: stall.sealedItems.length > 0
            x: glassCase.x + glassCase.width + stall.m
            y: stall.m
            width: stall.tableW - x - stall.m
            height: glassCase.height
            Row {
                anchors.centerIn: parent
                spacing: stall.m
                Repeater {
                    model: stall.sealedItems
                    Column {
                        id: product
                        required property var modelData
                        spacing: 4
                        opacity: stall.owner.bought(modelData.id) ? 0.45 : 1
                        Card {
                            width: Math.min(sealedArea.height * 0.72 * 0.716, product.modelData.sealed.kind === "box" ? 150 : 110)
                            card: stall.owner.cardOf(product.modelData)
                            faceUp: true
                            time: stall.time
                            hoverTilt: true
                            onClicked: stall.picked(product.modelData.id)
                        }
                        Sticker {
                            anchors.horizontalCenter: parent.horizontalCenter
                            listing: product.modelData
                        }
                    }
                }
            }
        }

        // open binders: nine-pocket pages, two to a spread
        Row {
            id: binders
            readonly property int spreads: Math.max(1, Math.ceil(stall.raws.length / 18))
            readonly property int pages: stall.raws.length <= 9 ? 1 : 2   // a few cards: just the one page
            // as big as the space in front of the case allows (the clutter along the front edge apart)
            readonly property real roomH: stall.tableH - y - stall.m * 2.6
            readonly property real pocketW: Math.min((Math.min(stall.tableW * (spreads > 1 ? 0.47 : 0.62),
                                                               (stall.tableW - stall.m * (spreads + 1)) / spreads) / 2 - stall.m) / 3,
                                                     (roomH - stall.m * 1.6) / 3 * 0.716)
            readonly property real spreadW: (pocketW * 3 + stall.m) * pages
            anchors.horizontalCenter: parent.horizontalCenter
            y: glassCase.y + (glassCase.visible || sealedArea.visible ? glassCase.height + stall.m : 0)
            spacing: stall.m * 1.4
            visible: stall.raws.length > 0
            Repeater {
                model: binders.spreads
                Rectangle {   // the binder's cover, open
                    id: spread
                    required property int index
                    readonly property var cards: stall.raws.slice(index * 18, index * 18 + 18)
                    width: binders.spreadW
                    height: binders.pocketW / 0.716 * 3 + stall.m * 1.6
                    radius: 8
                    color: ["#1b2a4a", "#3a1b2a", "#1e3a2a", "#2a2a2a"][index % 4]
                    border.color: "#0a0a0a"
                    border.width: 2
                    Rectangle {   // the spine and rings
                        visible: binders.pages > 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: stall.m * 0.6
                        height: parent.height
                        color: "#0a0a0a"
                        opacity: 0.5
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: stall.m
                        Repeater {
                            model: binders.pages   // left page, right page
                            Grid {
                                id: page
                                required property int index
                                columns: 3
                                spacing: 2
                                Repeater {
                                    model: 9
                                    Rectangle {   // a pocket: clear plastic, a card in it (or not)
                                        id: pocket
                                        required property int index
                                        readonly property var listing: spread.cards[page.index * 9 + index] || null
                                        width: binders.pocketW - 2
                                        height: width / 0.716
                                        radius: 2
                                        color: "#26ffffff"
                                        border.color: pocketMouse.containsMouse && listing ? "#ffd56b" : "#40ffffff"
                                        border.width: pocketMouse.containsMouse && listing ? 2 : 1
                                        Card {
                                            visible: !!pocket.listing
                                            anchors.centerIn: parent
                                            width: parent.width - 4
                                            card: pocket.listing ? stall.owner.cardOf(pocket.listing) : null
                                            faceUp: true
                                            dropShadow: false
                                            time: stall.time
                                            opacity: pocket.listing && stall.owner.bought(pocket.listing.id) ? 0.45 : 1
                                        }
                                        Sticker {
                                            visible: !!pocket.listing
                                            listing: pocket.listing
                                            anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 2 }
                                        }
                                        MouseArea {
                                            id: pocketMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !!pocket.listing
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: stall.picked(pocket.listing.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // the clutter: sleeve boxes and deck boxes along the front edge
        Row {
            anchors { right: parent.right; rightMargin: stall.m; bottom: parent.bottom; bottomMargin: stall.m * 0.6 }
            spacing: 4
            Repeater {
                model: [["#3a3a8a", "SLEEVES"], ["#7a2a8a", "SLEEVES"], ["#2a6a5a", "DECK BOX"], ["#8a6a2a", "TOPLOADERS"]]
                Rectangle {
                    required property var modelData
                    width: stall.tableW * 0.055
                    height: width * 0.7
                    radius: 3
                    color: modelData[0]
                    border.color: Qt.lighter(modelData[0], 1.5)
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData[1]
                        color: "#e8e8ee"
                        font { pixelSize: Math.max(6, stall.tableW * 0.0065); weight: Font.Black }
                    }
                }
            }
        }
        Rectangle {   // the vendor's sign at the front: their pitch
            anchors { left: parent.left; leftMargin: stall.m; bottom: parent.bottom; bottomMargin: stall.m * 0.6 }
            width: pitch.implicitWidth + 16
            height: pitch.implicitHeight + 10
            radius: 3
            color: "#fff6d8"
            rotation: -2
            Text {
                id: pitch
                anchors.centerIn: parent
                text: stall.vendor ? stall.vendor.blurb : ""
                color: "#2b1a0c"
                font { pixelSize: Math.max(9, stall.tableW * 0.011); weight: Font.Black; italic: true }
            }
        }
    }
}

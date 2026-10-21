pragma ComponentBehavior: Bound
import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// One vendor's table at the card show: everything they brought (slabs, raw cards, sealed
// product) laid out in one big grid on the cloth, each with its price sticker and name
// under it, as big as the table allows (it scrolls when a vendor has a lot). Click
// anything to pick it up.
Item {
    id: stall

    property Item owner                // CardShow: cardOf(), bought(), the stage
    property var vendor                // the stall: { name, blurb, kind, vintage, listings }
    property color cloth: "#7a2230"
    signal picked(string id)

    // sealed product first, then slabs, then raw cards: the eye-catchers up top
    readonly property var items: !vendor ? [] : vendor.listings.filter(x => x.sealed)
                                            .concat(vendor.listings.filter(x => x.grade && !x.sealed))
                                            .concat(vendor.listings.filter(x => !x.grade && !x.sealed))
    readonly property real time: owner && owner.stage ? owner.stage.t : 0

    function price(x) { return Progress.format(Progress.showPrice(owner.p, x)); }

    Rectangle {   // the cloth
        anchors.fill: parent
        radius: 10
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(stall.cloth, 1.5) }
            GradientStop { position: 1; color: Qt.darker(stall.cloth, 1.15) }
        }
        border.color: Qt.darker(stall.cloth, 2)
        border.width: 2
    }

    Rectangle {   // the vendor's sign: their pitch
        id: sign
        x: 16; y: 12
        width: Math.min(pitch.implicitWidth + 20, stall.width * 0.55)
        height: pitch.implicitHeight + 12
        radius: 4
        color: "#fff6d8"
        rotation: -1
        Text {
            id: pitch
            anchors.centerIn: parent
            width: Math.min(implicitWidth, stall.width * 0.55 - 20)
            elide: Text.ElideRight
            text: stall.vendor ? stall.vendor.blurb : ""
            color: "#2b1a0c"
            font { pixelSize: 14; weight: Font.Black; italic: true }
        }
    }

    // ---- the grid ---------------------------------------------------------------------
    GridView {
        id: grid
        // centred down the table when it all fits
        anchors { fill: parent; topMargin: 64 + Math.max(0, (availH - Math.ceil(n / cols) * cellHeight) / 2)
                  leftMargin: 12; rightMargin: 12; bottomMargin: 8 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: stall.items

        readonly property real gap: 18
        readonly property real labelH: 46                  // the sticker and the name under each one
        readonly property real aspect: 1.64                // a slab's height / width (a card is shorter)
        readonly property int n: Math.max(1, stall.items.length)
        readonly property real availW: stall.width - 24
        readonly property real availH: stall.height - 72
        // the biggest size where everything fits; when even 120 px won't, it scrolls
        readonly property real itemW: {
            var best = 0;
            for (var cols = 1; cols <= n; cols++) {
                var rows = Math.ceil(n / cols);
                var w = Math.min(availW / cols - gap, ((availH / rows) - gap - labelH) / aspect);
                if (w > best) best = w;
            }
            return Math.max(120, Math.min(230, best));
        }
        readonly property int cols: Math.max(1, Math.floor(availW / (itemW + gap)))
        cellWidth: Math.floor(availW / cols)
        cellHeight: itemW * aspect + labelH + gap

        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool mine: stall.owner.bought(modelData.id)
            readonly property var gone: mine ? null : stall.owner.taken(modelData.id)   // another buyer's
            readonly property bool sold: mine || !!gone
            readonly property bool slab: !!modelData.grade && !modelData.sealed
            width: grid.cellWidth
            height: grid.cellHeight

            Item {   // the card / slab / product, standing on the bottom of its box
                id: shown
                anchors.horizontalCenter: parent.horizontalCenter
                y: grid.gap / 2
                width: grid.itemW
                height: grid.itemW * grid.aspect
                scale: hover.containsMouse && !cell.sold ? 1.05 : 1
                z: hover.containsMouse ? 2 : 1
                opacity: cell.sold ? 0.4 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }

                Loader {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    sourceComponent: cell.slab ? slabView : cardView
                }
                Component {
                    id: slabView
                    Slab {
                        width: grid.itemW
                        card: stall.owner.cardOf(cell.modelData)
                        time: stall.time
                        hoverTilt: false
                    }
                }
                Component {
                    id: cardView
                    Card {
                        width: Math.min(grid.itemW * 0.92, grid.itemW * grid.aspect * 0.716)
                        card: stall.owner.cardOf(cell.modelData)
                        faceUp: true
                        time: stall.time
                    }
                }
            }
            Rectangle {   // hovered: a gold outline
                anchors.fill: shown
                anchors.margins: -4
                radius: 8
                color: "transparent"
                border.color: "#ffd56b"
                border.width: 2
                visible: hover.containsMouse && !cell.sold
                scale: shown.scale
            }

            Column {
                anchors { top: shown.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                width: grid.itemW + grid.gap * 0.6
                spacing: 3
                Rectangle {   // the price sticker (SOLD once it's gone)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: tag.implicitWidth + 14
                    height: tag.implicitHeight + 4
                    radius: 3
                    color: cell.mine ? "#2f6b46" : cell.sold ? "#c8433a" : "#fff6d8"
                    border.color: "#40000000"
                    Text {
                        id: tag
                        anchors.centerIn: parent
                        text: cell.mine ? "YOURS" : cell.sold ? "SOLD" : stall.price(cell.modelData)
                        color: cell.sold ? "white" : "#1a1a1a"
                        font { pixelSize: 14; weight: Font.Black }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: Tiers.displayName(cell.modelData.card) + (cell.slab ? "  ·  graded " + cell.modelData.grade : "")
                    color: "#f4ead8"
                    font { pixelSize: 12; weight: Font.Bold }
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: cell.gone ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!cell.gone) stall.picked(cell.modelData.id)
            }
        }
    }

    Rectangle {   // where you are in the table, when it scrolls
        visible: grid.contentHeight > grid.height
        anchors.right: parent.right
        anchors.rightMargin: 3
        y: grid.y + grid.visibleArea.yPosition * grid.height
        width: 6
        height: Math.max(30, grid.visibleArea.heightRatio * grid.height)
        radius: 3
        color: "#ffd56b"
        opacity: 0.6
    }
}

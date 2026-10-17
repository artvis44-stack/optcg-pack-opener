import QtQuick
import "tiers.js" as Tiers

// Box mode screens: the sealed display box, its packs, and the box summary.
Item {
    id: view

    property Item stage
    property var inspected: null
    readonly property string phase: stage ? stage.phase : ""
    readonly property int openedCount: stage ? stage.boxOpened.filter(o => o).length : 0

    // everything pulled from the opened packs of this box
    readonly property var pulled: {
        var out = [];
        if (!stage) return out;
        stage.boxPacks.forEach((p, i) => { if (stage.boxOpened[i]) out = out.concat(p); });
        if (stage.boxTopper && stage.topperTaken) out.push(stage.boxTopper);
        return out;
    }
    // count per tier, best tiers first; commons/uncommons left out
    readonly property var tally: {
        var counts = {};
        pulled.forEach(c => counts[c.tier] = (counts[c.tier] || 0) + 1);
        return Object.keys(counts)
            .filter(t => t !== "C" && t !== "UC")
            .sort((a, b) => Tiers.info[b].rank - Tiers.info[a].rank)
            .map(t => ({ tier: t, count: counts[t] }));
    }
    // the cards worth laying out: SR and up
    readonly property var hits: pulled.filter(c => Tiers.tierOf(c).rank >= 4)
                                      .sort((a, b) => Tiers.tierOf(b).rank - Tiers.tierOf(a).rank)

    onPhaseChanged: inspected = null

    // clicks on empty space: open the sealed box, otherwise nothing
    MouseArea {
        anchors.fill: parent
        onClicked: if (view.phase === "boxSealed") view.stage.advance()
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: view.height * 0.04
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.phase === "boxSummary" ? "Box " + (view.stage.boxIndex + 1) + " complete"
                  : view.stage && view.stage.db ? view.stage.db.set + "  ·  " + view.stage.db.set_name : ""
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Booster box " + (view.stage.boxIndex + 1) + " of " + view.stage.cfg.boxes + " in this case"
                  + (view.phase === "boxGrid" ? "   ·   " + view.openedCount + " / " + view.stage.boxPacks.length + " packs opened" : "")
            color: "#d0d4dc"
            font.pixelSize: 16
        }
    }

    // tier tally chips (grid + summary)
    Row {
        id: tallyRow
        visible: view.phase !== "boxSealed" && view.tally.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: 14
        spacing: 8
        Repeater {
            model: view.tally
            Rectangle {
                required property var modelData
                readonly property var tier: Tiers.info[modelData.tier]
                width: chip.width + 18
                height: chip.height + 8
                radius: height / 2
                color: "#161b2b"
                border.color: tier.color
                border.width: 1
                Text {
                    id: chip
                    anchors.centerIn: parent
                    text: parent.tier.label + "  ×" + parent.modelData.count
                    color: parent.tier.color
                    font { pixelSize: 13; weight: Font.Bold }
                }
            }
        }
    }

    // ---- sealed box --------------------------------------------------------

    Item {
        id: sealed
        anchors.fill: parent
        visible: view.phase === "boxSealed"

        readonly property real aspect: boxImg.status === Image.Ready ? boxImg.implicitWidth / boxImg.implicitHeight : 1
        property real tx: boxMouse.containsMouse ? (boxMouse.mouseX / boxArt.width - 0.5) * 2 : 0.3 * Math.sin(view.stage.t * 0.7)
        property real ty: boxMouse.containsMouse ? (boxMouse.mouseY / boxArt.height - 0.5) * 2 : 0.15 * Math.cos(view.stage.t * 0.5)
        property real stx: tx
        property real sty: ty
        Behavior on stx { SmoothedAnimation { velocity: 3 } }
        Behavior on sty { SmoothedAnimation { velocity: 3 } }

        Item {
            id: boxArt
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.sin(view.stage.t * 1.4) * 6
            height: view.height * 0.62
            width: height * sealed.aspect
            transform: [
                Rotation {
                    origin.x: boxArt.width / 2; origin.y: boxArt.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: sealed.stx * 12
                },
                Rotation {
                    origin.x: boxArt.width / 2; origin.y: boxArt.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: -sealed.sty * 8
                }
            ]
            Image {
                id: boxImg
                anchors.fill: parent
                source: view.stage ? view.stage.boxImage : ""
                smooth: true
                mipmap: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                visible: boxImg.status === Image.Ready
                property variant source: boxImg
                property vector2d tilt: Qt.vector2d(sealed.stx, sealed.sty)
                property real time: view.stage.t
                property real intensity: 0.25
                property real gold: 0.85
                property real aspect: width / Math.max(1, height)
                property real radius: 0
                fragmentShader: Qt.resolvedUrl("shaders/holo.frag.qsb")
            }
            // drawn fallback
            Rectangle {
                anchors.fill: parent
                visible: boxImg.status !== Image.Ready
                radius: 12
                color: "#b3122b"
                border.color: "#e2bd63"
                border.width: 4
                Text {
                    anchors.centerIn: parent
                    text: (view.stage && view.stage.db ? view.stage.db.set : "") + "\nBOOSTER BOX\n24 PACKS"
                    horizontalAlignment: Text.AlignHCenter
                    color: "#fff6e0"
                    font { pixelSize: 36; weight: Font.Black; italic: true }
                }
            }
            MouseArea {
                id: boxMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: view.stage.advance()
            }
        }
    }

    // ---- the packs ------------------------------------------------------------

    Item {
        id: gridScreen
        anchors.fill: parent
        visible: view.phase === "boxGrid"

        readonly property int cols: view.stage.boxPacks.length % 10 === 0 ? 10 : 8
        readonly property int rows: Math.ceil(view.stage.boxPacks.length / cols)
        readonly property real gap: 18
        readonly property real labelH: 24
        readonly property real tileH: Math.min((view.height * 0.66 - (rows - 1) * gap - rows * labelH) / rows,
                                               (view.width * 0.9 - (cols - 1) * gap) / cols / view.stage.packAspect)
        readonly property real tileW: tileH * view.stage.packAspect

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 30
            columns: gridScreen.cols
            columnSpacing: gridScreen.gap
            rowSpacing: gridScreen.gap

            Repeater {
                model: view.stage ? view.stage.boxPacks.length : 0
                delegate: Item {
                    id: tile
                    required property int index
                    readonly property bool opened: !!view.stage.boxOpened[index]
                    readonly property var best: opened ? Tiers.best(view.stage.boxPacks[index]) : null
                    width: gridScreen.tileW
                    height: gridScreen.tileH + gridScreen.labelH

                    // drop in, staggered, when the box is opened
                    opacity: 0
                    Component.onCompleted: dropIn.start()
                    SequentialAnimation {
                        id: dropIn
                        PauseAnimation { duration: tile.index * 25 }
                        NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 250 }
                    }

                    Item {
                        id: art
                        width: gridScreen.tileW
                        height: gridScreen.tileH
                        y: mouse.containsMouse && !tile.opened ? -10 : 0
                        Behavior on y { NumberAnimation { duration: 150 } }

                        Image {
                            anchors.fill: parent
                            visible: !tile.opened
                            source: view.stage.packImage
                            smooth: true
                            mipmap: true
                        }
                        Rectangle {   // drawn pack fallback
                            anchors.fill: parent
                            visible: !tile.opened && !view.stage.packImage
                            radius: 6
                            color: "#b3122b"
                            border.color: "#e2bd63"
                        }
                        Card {
                            anchors.centerIn: parent
                            visible: tile.opened
                            width: gridScreen.tileW
                            card: tile.best
                            faceUp: true
                            time: view.stage.t
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: tile.opened ? Tiers.tierOf(tile.best).label : "Pack " + (tile.index + 1)
                        color: tile.opened ? Tiers.tierOf(tile.best).color : "#7a8090"
                        font { pixelSize: 12; weight: Font.Bold }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: art
                        hoverEnabled: true
                        cursorShape: tile.opened ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: tile.opened ? view.inspected = tile.best : view.stage.openBoxPack(tile.index)
                    }
                }
            }
        }
    }

    // ---- box summary -----------------------------------------------------------

    Item {
        id: summary
        anchors.fill: parent
        visible: view.phase === "boxSummary"

        readonly property real cardW: Math.min(150, view.width * 0.9 / 8 - 16)

        Text {
            anchors.centerIn: parent
            visible: view.hits.length === 0
            text: "No Super Rares or better in this box. Ouch."
            color: "#9aa0ad"
            font.pixelSize: 22
        }

        Flow {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: tallyRow.y + tallyRow.height + 30
            width: Math.min(view.width * 0.9, view.hits.length * (summary.cardW + 16))
            spacing: 16

            Repeater {
                model: view.hits
                delegate: Item {
                    required property var modelData
                    width: summary.cardW
                    height: summary.cardW / 0.716 + 22
                    Card {
                        id: hitCard
                        width: summary.cardW
                        card: parent.modelData
                        faceUp: true
                        time: view.stage.t
                        hoverTilt: true
                        onClicked: view.inspected = parent.modelData
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: Tiers.tierOf(parent.modelData).label
                        color: Tiers.tierOf(parent.modelData).color
                        font { pixelSize: 12; weight: Font.Bold }
                    }
                }
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        color: "#9aa0ad"
        font.pixelSize: 14
        text: view.inspected ? "Move the mouse to tilt   ·   click or Esc to go back"
              : view.phase === "boxSealed" ? "Click or Space to open the box   ·   X: single packs   ·   S: sets   ·   B: binder   ·   Esc: close"
              : view.phase === "boxGrid" ? "Click a pack or Space: open the next one   ·   A: open all remaining   ·   X: single packs   ·   S: sets   ·   B: binder   ·   Esc: close"
              : view.stage.boxIndex + 1 < view.stage.cfg.boxes ? "Space: open box " + (view.stage.boxIndex + 2) + " of " + view.stage.cfg.boxes + "   ·   X: single packs   ·   S: sets   ·   B: binder   ·   Esc: close"
              : "Case finished!   ·   Space: start a new case   ·   X: single packs   ·   S: sets   ·   B: binder   ·   Esc: close"
    }

    // ---- inspect a card --------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: view.inspected ? 0.75 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: view.inspected = null
        }
    }
    Card {
        anchors.centerIn: parent
        visible: !!view.inspected
        width: Math.min(420, view.height * 0.8 * 0.716)
        card: view.inspected
        faceUp: true
        time: view.stage.t
        hoverTilt: true
        onClicked: view.inspected = null
    }
    Text {
        visible: !!view.inspected
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        text: !view.inspected ? ""
              : (view.inspected.tier === "TOPPER" ? "Box topper!  ·  " : "")
                + Tiers.displayName(view.inspected) + "  ·  " + view.inspected.id + "  ·  " + Tiers.tierOf(view.inspected).label
        color: view.inspected ? Tiers.tierOf(view.inspected).color : "white"
        style: Text.Outline; styleColor: "#000000"
        font { pixelSize: 20; weight: Font.Bold }
    }
}

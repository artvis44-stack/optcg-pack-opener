import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// A graded card in its case, like a real slab: the label on top (name, set,
// number, rarity, the grade big and its name) in the label style you chose in
// the Port, the card underneath in a clear acrylic case. A 10 gets a gold edge;
// a Diamond Label (Progress.DIAMOND_CHANCE) its own icy label, a rainbow edge and sparkles.
Item {
    id: slab

    property var card                  // a slab: a card plus { grade, diamond }
    property var labelStyle: Progress.SLABS[0]
    property real time: 0
    property bool hoverTilt: true
    signal clicked()

    readonly property real u: width / 100           // everything scales with the width
    readonly property bool gem: !!card && card.grade === 10
    readonly property bool diamond: !!card && !!card.diamond
    readonly property var style: diamond ? Progress.DIAMOND_LABEL : labelStyle
    readonly property color prism: Qt.hsla((time * 0.18) % 1, 0.9, 0.72, 1)   // the diamond's edge, round the rainbow
    readonly property var tier: Tiers.tierOf(card)
    readonly property real labelH: 24 * u
    implicitHeight: 5 * u + labelH + 4 * u + (width - 10 * u) / 0.716 + 5 * u
    height: implicitHeight

    Rectangle {   // soft shadow
        x: 1.5 * slab.u; y: 2.5 * slab.u
        width: parent.width; height: parent.height
        radius: 4 * slab.u
        color: "#000000"
        opacity: 0.45
    }
    Rectangle {   // the acrylic case
        anchors.fill: parent
        radius: 4 * slab.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#40e8f4ff" }
            GradientStop { position: 0.5; color: "#18ffffff" }
            GradientStop { position: 1.0; color: "#30e8f4ff" }
        }
        border.color: slab.diamond ? slab.prism : slab.gem ? "#ffd700" : "#8fffffff"
        border.width: slab.diamond ? Math.max(3, 1.8 * slab.u) : slab.gem ? Math.max(2, 1.2 * slab.u) : Math.max(1, 0.6 * slab.u)
    }
    Rectangle {   // a Diamond Label glows
        visible: slab.diamond
        anchors.fill: parent
        anchors.margins: -1.6 * slab.u
        radius: 5.5 * slab.u
        color: "transparent"
        border.color: slab.prism
        border.width: Math.max(1, 0.8 * slab.u)
        opacity: 0.35 + 0.25 * Math.sin(slab.time * 3)
    }

    Rectangle {   // the label
        id: label
        x: 5 * slab.u; y: 5 * slab.u
        width: parent.width - 10 * slab.u
        height: slab.labelH
        radius: 1.5 * slab.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: slab.style.top }
            GradientStop { position: 1.0; color: slab.style.bottom }
        }
        Rectangle {   // rarity stripe
            width: 1.4 * slab.u
            height: parent.height
            radius: width / 2
            color: slab.tier.color
        }
        Column {
            x: 4 * slab.u
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - gradeBox.width - 8 * slab.u
            spacing: 0.4 * slab.u
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: slab.card ? Tiers.displayName(slab.card) : ""
                color: slab.style.text
                font { pixelSize: Math.max(8, 6.6 * slab.u); weight: Font.Black }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: slab.card ? slab.card.set + "  ·  " + slab.card.id : ""
                color: slab.style.sub
                font { pixelSize: Math.max(6, 4.4 * slab.u); weight: Font.Bold }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: slab.tier.label.toUpperCase()
                color: slab.style.sub
                font { pixelSize: Math.max(6, 3.8 * slab.u); weight: Font.Bold; letterSpacing: 0.3 * slab.u }
            }
        }
        Item {   // a Diamond Label: a prism sweeping across, and sparkles
            visible: slab.diamond
            anchors.fill: parent
            clip: true
            Rectangle {
                readonly property real sweep: (slab.time * 0.45) % 1.6 - 0.3
                x: sweep * parent.width - width / 2
                y: -parent.height * 0.5
                width: parent.width * 0.32
                height: parent.height * 2
                rotation: 22
                opacity: 0.55
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.25; color: "#80ff7ad9" }
                    GradientStop { position: 0.45; color: "#a07ae8ff" }
                    GradientStop { position: 0.6; color: "#c0ffffff" }
                    GradientStop { position: 0.8; color: "#80b6ff7a" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            Repeater {
                model: [[0.12, 0.2, 0], [0.38, 0.75, 1.7], [0.55, 0.25, 3.1], [0.7, 0.8, 0.9], [0.9, 0.3, 2.3]]
                Text {
                    required property var modelData
                    x: modelData[0] * parent.width - width / 2
                    y: modelData[1] * parent.height - height / 2
                    text: "✦"
                    color: "#ffffff"
                    style: Text.Outline; styleColor: "#6fd3ff"
                    font.pixelSize: Math.max(6, 5 * slab.u)
                    readonly property real tw: Math.max(0, Math.sin(slab.time * 2.6 + modelData[2]))
                    opacity: tw
                    scale: 0.5 + tw
                    rotation: slab.time * 40 + modelData[2] * 30
                }
            }
        }
        Column {
            id: gradeBox
            anchors { right: parent.right; rightMargin: 3 * slab.u; verticalCenter: parent.verticalCenter }
            width: 24 * slab.u
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !slab.card ? "" : slab.diamond ? "◆10" : String(slab.card.grade)
                color: slab.diamond ? "#1a8fe0" : slab.gem ? "#b8860b" : slab.style.text
                style: slab.diamond ? Text.Outline : Text.Normal
                styleColor: "#ffffff"
                font { pixelSize: Math.max(12, (slab.diamond ? 10.5 : 12) * slab.u); weight: Font.Black }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: slab.card ? Progress.gradeName(slab.card) : ""
                color: slab.style.sub
                font { pixelSize: Math.max(5, 3.2 * slab.u); weight: Font.Black; letterSpacing: 0.2 * slab.u }
            }
        }
    }

    Rectangle {   // the well the card sits in
        x: 4 * slab.u; y: label.y + label.height + 3 * slab.u
        width: parent.width - 8 * slab.u
        height: (parent.width - 10 * slab.u) / 0.716 + 2 * slab.u
        radius: 2 * slab.u
        color: "#30000000"
        border.color: "#30ffffff"
    }
    Card {
        x: 5 * slab.u; y: label.y + label.height + 4 * slab.u
        width: parent.width - 10 * slab.u
        card: slab.card
        faceUp: true
        time: slab.time
        hoverTilt: slab.hoverTilt
        dropShadow: false
        onClicked: slab.clicked()
    }
    Rectangle {   // a glint across the case
        anchors.fill: parent
        radius: 4 * slab.u
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00ffffff" }
            GradientStop { position: 0.35; color: "#14ffffff" }
            GradientStop { position: 0.45; color: "#00ffffff" }
            GradientStop { position: 1.0; color: "#00ffffff" }
        }
    }
}

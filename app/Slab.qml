import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// A graded card in its case, like a real slab: the label on top (name, set,
// number, rarity, the grade big and its name) in the label style you chose in
// the Port, the card underneath in a clear acrylic case. A 10 gets a gold edge.
Item {
    id: slab

    property var card                  // a slab: a card plus { grade }
    property var labelStyle: Progress.SLABS[0]
    property real time: 0
    property bool hoverTilt: true
    signal clicked()

    readonly property real u: width / 100           // everything scales with the width
    readonly property bool gem: !!card && card.grade === 10
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
        border.color: slab.gem ? "#ffd700" : "#8fffffff"
        border.width: slab.gem ? Math.max(2, 1.2 * slab.u) : Math.max(1, 0.6 * slab.u)
    }

    Rectangle {   // the label
        id: label
        x: 5 * slab.u; y: 5 * slab.u
        width: parent.width - 10 * slab.u
        height: slab.labelH
        radius: 1.5 * slab.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: slab.labelStyle.top }
            GradientStop { position: 1.0; color: slab.labelStyle.bottom }
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
                color: slab.labelStyle.text
                font { pixelSize: Math.max(8, 6.6 * slab.u); weight: Font.Black }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: slab.card ? slab.card.set + "  ·  " + slab.card.id : ""
                color: slab.labelStyle.sub
                font { pixelSize: Math.max(6, 4.4 * slab.u); weight: Font.Bold }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: slab.tier.label.toUpperCase()
                color: slab.labelStyle.sub
                font { pixelSize: Math.max(6, 3.8 * slab.u); weight: Font.Bold; letterSpacing: 0.3 * slab.u }
            }
        }
        Column {
            id: gradeBox
            anchors { right: parent.right; rightMargin: 3 * slab.u; verticalCenter: parent.verticalCenter }
            width: 24 * slab.u
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: slab.card ? String(slab.card.grade) : ""
                color: slab.gem ? "#b8860b" : slab.labelStyle.text
                font { pixelSize: Math.max(12, 12 * slab.u); weight: Font.Black }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: slab.card ? Progress.GRADE_NAME[slab.card.grade] : ""
                color: slab.labelStyle.sub
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

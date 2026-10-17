import QtQuick
import "tiers.js" as Tiers

// One card: flips between back and face, tilts in 3D, holo shader on the face.
Item {
    id: root

    property var card
    property bool faceUp: false
    property real time: 0
    property bool sway: false        // gentle automatic tilt (showcase)
    property bool hoverTilt: false   // tilt toward the mouse
    readonly property var tier: card ? Tiers.tierOf(card) : Tiers.info.C
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    width: 360
    height: width / 0.716

    // target tilt, smoothed
    property real tiltX: hoverTilt && mouse.containsMouse ? (mouse.mouseX / width - 0.5) * 2
                       : sway ? 0.45 * Math.sin(time * 0.9) : 0
    property real tiltY: hoverTilt && mouse.containsMouse ? (mouse.mouseY / height - 0.5) * 2
                       : sway ? 0.25 * Math.cos(time * 0.7) : 0
    property real tx: tiltX
    property real ty: tiltY
    Behavior on tx { SmoothedAnimation { velocity: 4 } }
    Behavior on ty { SmoothedAnimation { velocity: 4 } }

    property real flipAngle: faceUp ? 0 : 180
    Behavior on flipAngle { NumberAnimation { duration: 650; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

    // drop shadow
    Rectangle {
        anchors.fill: flip
        anchors.margins: -root.width * 0.02
        anchors.topMargin: root.width * 0.04
        radius: root.width * 0.06
        color: "#000000"
        opacity: 0.35
        transform: Translate { x: -root.tx * 10; y: -root.ty * 10 + 6 }
    }

    Flipable {
        id: flip
        anchors.fill: parent

        front: Item {
            anchors.fill: parent
            Image {
                id: img
                anchors.fill: parent
                source: root.card ? "file://" + root.card.image : ""
                smooth: true
                mipmap: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                property variant source: img
                property vector2d tilt: Qt.vector2d(root.tx, root.ty)
                property real time: root.time
                property real intensity: root.tier.holo
                property real gold: root.tier.gold
                property real aspect: width / Math.max(1, height)
                property real radius: 0.035
                fragmentShader: Qt.resolvedUrl("shaders/holo.frag.qsb")
            }
        }

        back: CardBack { anchors.fill: parent }

        transform: [
            Rotation {
                origin.x: flip.width / 2; origin.y: flip.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.flipAngle + root.tx * 14
            },
            Rotation {
                origin.x: flip.width / 2; origin.y: flip.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: -root.ty * 14
            }
        ]
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.hoverTilt
        enabled: root.hoverTilt
        cursorShape: root.hoverTilt ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}

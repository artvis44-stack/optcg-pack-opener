import QtQuick
import "tiers.js" as Tiers

// One card: flips between back and face, tilts in 3D, holo shader on the face.
Item {
    id: root

    property var card
    property string backSource       // official back image, if cached
    property bool faceUp: false
    property real time: 0
    property bool sway: false        // gentle automatic tilt (showcase)
    property bool hoverTilt: false   // tilt toward the mouse
    property bool tiltRotates: true  // false: tilt only moves the foil (e.g. inside a slab that tilts)
    property bool dropShadow: true
    readonly property var tier: card ? Tiers.tierOf(card) : Tiers.info.C
    // a counterfeit (the card show): the foil barely shimmers and the print is a little washed out;
    // how much (0..1): a good fake (card.fakeLook, the show's listings) looks almost right
    readonly property real fakeness: !card || !card.fake ? 0 : card.fakeLook !== undefined ? card.fakeLook : 1
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
        visible: root.dropShadow
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
                source: root.card && root.card.image ? "file://" + root.card.image : ""
                smooth: true
                mipmap: true
                visible: false
            }
            // no picture (a vintage card nobody's photographed, a promo without an image): drawn instead
            Loader {
                id: drawn
                anchors.fill: parent
                active: !!root.card && (!root.card.image || img.status === Image.Error)
                sourceComponent: DrawnFace { card: root.card }
            }
            ShaderEffectSource {
                id: drawnTexture
                sourceItem: drawn.item as Item
                hideSource: true
                textureSize: Qt.size(drawn.width * 2, drawn.height * 2)
            }
            ShaderEffect {
                anchors.fill: parent
                property variant source: drawn.item ? drawnTexture : img
                property vector2d tilt: Qt.vector2d(root.tx, root.ty)
                property real time: root.time
                property real intensity: root.tier.holo * (1 - 0.88 * root.fakeness)
                property real gold: root.tier.gold * (1 - root.fakeness)
                property real aspect: width / Math.max(1, height)
                property real radius: 0.035
                fragmentShader: Qt.resolvedUrl("shaders/holo.frag.qsb")
            }
            Rectangle {   // a counterfeit's print: a faint yellowish wash
                visible: root.fakeness > 0
                opacity: root.fakeness
                anchors.fill: parent
                radius: root.width * 0.035
                color: "#33e6d38a"
            }
        }

        back: Item {
            anchors.fill: parent
            Image {
                id: backImg
                anchors.fill: parent
                source: root.backSource
                smooth: true
                mipmap: true
            }
            CardBack {
                anchors.fill: parent
                visible: backImg.status !== Image.Ready
            }
        }

        transform: [
            Rotation {
                origin.x: flip.width / 2; origin.y: flip.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.flipAngle + (root.tiltRotates ? root.tx * 14 : 0)
            },
            Rotation {
                origin.x: flip.width / 2; origin.y: flip.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: root.tiltRotates ? -root.ty * 14 : 0
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

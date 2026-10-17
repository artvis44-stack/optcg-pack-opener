import QtQuick

// Sealed booster. tear() shakes it, rips the top strip off and drops the body.
Item {
    id: pack

    property string artSource
    property string setCode
    property string setName
    property string packImage
    property real time: 0
    property bool tearing: false
    readonly property real seam: 0.09

    signal tearStarted()   // strip is off: cards can start rising
    signal torn()          // body is gone

    width: 400
    height: 640

    property real tiltX: mouse.containsMouse && !tearing ? (mouse.mouseX / width - 0.5) * 2 : 0.3 * Math.sin(time * 0.8)
    property real tiltY: mouse.containsMouse && !tearing ? (mouse.mouseY / height - 0.5) * 2 : 0.15 * Math.cos(time * 0.6)
    property real tx: tiltX
    property real ty: tiltY
    Behavior on tx { SmoothedAnimation { velocity: 3 } }
    Behavior on ty { SmoothedAnimation { velocity: 3 } }
    property real wiggle: 0
    property real bob: tearing ? 0 : Math.sin(time * 1.6) * 6

    function tear() {
        if (tearing) return;
        tearing = true;
        tearAnim.start();
    }

    Item {
        id: tilted
        anchors.fill: parent
        rotation: pack.wiggle
        transform: [
            Translate { y: pack.bob },
            Rotation {
                origin.x: tilted.width / 2; origin.y: tilted.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: pack.tx * 16
            },
            Rotation {
                origin.x: tilted.width / 2; origin.y: tilted.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: -pack.ty * 12
            }
        ]

        Item {
            id: body
            y: pack.height * pack.seam
            width: pack.width
            height: pack.height * (1 - pack.seam)
            clip: true
            PackFace {
                y: -pack.height * pack.seam
                width: pack.width; height: pack.height
                artSource: pack.artSource; setCode: pack.setCode; setName: pack.setName
                packImage: pack.packImage
                tilt: Qt.vector2d(pack.tx, pack.ty); time: pack.time
            }
        }

        Item {
            id: strip
            width: pack.width
            height: pack.height * pack.seam
            clip: true
            transformOrigin: Item.Left
            PackFace {
                width: pack.width; height: pack.height
                artSource: pack.artSource; setCode: pack.setCode; setName: pack.setName
                packImage: pack.packImage
                tilt: Qt.vector2d(pack.tx, pack.ty); time: pack.time
            }
        }

        // "tear here" perforation
        Row {
            y: pack.height * pack.seam - 1
            x: pack.width * 0.04
            spacing: pack.width * 0.02
            visible: pack.packImage === ""
            opacity: pack.tearing ? 0 : 0.55
            Repeater {
                model: 24
                Rectangle { width: pack.width * 0.02; height: 2; color: "#fff6e0" }
            }
        }

        Rectangle {
            id: seamFlash
            y: pack.height * pack.seam - 3
            width: pack.width; height: 6
            radius: 3
            color: "#ffffff"
            opacity: 0
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pack.tear()
    }

    SequentialAnimation {
        id: tearAnim
        SequentialAnimation {
            loops: 3
            NumberAnimation { target: pack; property: "wiggle"; to: 3; duration: 45 }
            NumberAnimation { target: pack; property: "wiggle"; to: -3; duration: 90 }
            NumberAnimation { target: pack; property: "wiggle"; to: 0; duration: 45 }
        }
        NumberAnimation { target: seamFlash; property: "opacity"; to: 1; duration: 70 }
        ParallelAnimation {
            NumberAnimation { target: strip; property: "x"; to: pack.width * 0.7; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: strip; property: "y"; to: -pack.height * 0.45; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: strip; property: "rotation"; to: -38; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: strip; property: "opacity"; to: 0; duration: 650; easing.type: Easing.InQuad }
            NumberAnimation { target: seamFlash; property: "opacity"; to: 0; duration: 350 }
        }
        ScriptAction { script: pack.tearStarted() }
        ParallelAnimation {
            NumberAnimation { target: body; property: "y"; to: pack.height * 1.8; duration: 650; easing.type: Easing.InBack }
            NumberAnimation { target: body; property: "opacity"; to: 0; duration: 650; easing.type: Easing.InQuad }
        }
        ScriptAction { script: pack.torn() }
    }
}

import QtQuick

// The booster wrapper: Bandai's pack photo when cached, else a drawn one. Drawn twice by Pack.qml
// (top strip + body) so the strip can tear off.
Item {
    id: face
    property string artSource
    property string setCode
    property string setName
    property vector2d tilt
    property real time
    property string packImage
    property int cardCount: 12
    readonly property bool photo: photoImg.status === Image.Ready

    Image {
        id: photoImg
        anchors.fill: parent
        source: face.packImage
        smooth: true
        mipmap: true
        visible: false
    }
    // foil sheen + glare over the photo (gold pack -> gold foil)
    ShaderEffect {
        anchors.fill: parent
        visible: face.photo
        property variant source: photoImg
        property vector2d tilt: face.tilt
        property real time: face.time
        property real intensity: 0.3
        property real gold: 0.85
        property real aspect: width / Math.max(1, height)
        property real radius: 0
        fragmentShader: Qt.resolvedUrl("shaders/holo.frag.qsb")
    }

    Item {
        anchors.fill: parent
        visible: !face.photo

        ShaderEffect {
            anchors.fill: parent
            property vector2d tilt: face.tilt
            property real time: face.time
            property real aspect: width / Math.max(1, height)
            property color colA: "#b3122b"
            property color colB: "#141c44"
            fragmentShader: Qt.resolvedUrl("shaders/pack.frag.qsb")
        }

        // logo
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.075
            spacing: -face.height * 0.012
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ONE PIECE"
                color: "#fff6e0"
                style: Text.Outline; styleColor: "#3a0610"
                font { pixelSize: face.height * 0.07; weight: Font.Black; italic: true; letterSpacing: 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CARD GAME"
                color: "#ffd56b"
                style: Text.Outline; styleColor: "#3a0610"
                font { pixelSize: face.height * 0.032; weight: Font.Bold; letterSpacing: 4 }
            }
        }

        // art window
        Item {
            id: win
            x: face.width * 0.08
            y: face.height * 0.2
            width: face.width * 0.84
            height: face.height * 0.32
            clip: true
            Image {
                anchors.fill: parent
                source: face.artSource
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: Image.AlignTop
                sourceClipRect: Qt.rect(60, 55, 480, 290)  // art only, above the SAMPLE stamp
                smooth: true
                mipmap: true
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.6; color: "transparent" }
                    GradientStop { position: 1.0; color: "#c0141c44" }
                }
            }
        }
        Rectangle {
            anchors.fill: win
            anchors.margins: -3
            color: "transparent"
            border.color: "#e2bd63"
            border.width: 3
        }

        // set ribbon
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.y + win.height - height * 0.5
            width: face.width * 0.66
            height: face.height * 0.065
            radius: height / 2
            color: "#e2bd63"
            border.color: "#fff1c4"
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: "BOOSTER PACK"
                color: "#2a0a10"
                font { pixelSize: parent.height * 0.48; weight: Font.Black; letterSpacing: 1 }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.58
            text: face.setCode
            color: "#ffd56b"
            style: Text.Outline; styleColor: "#3a0610"
            font { pixelSize: face.height * 0.1; weight: Font.Black; italic: true }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.72
            width: face.width * 0.86
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: face.setName.toUpperCase()
            color: "#fff6e0"
            style: Text.Outline; styleColor: "#0a0f28"
            font { pixelSize: face.height * 0.038; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height * 0.88
            text: "◆  " + face.cardCount + " CARDS  ◆"
            color: "#ffd56b"
            font { pixelSize: face.height * 0.026; weight: Font.Bold; letterSpacing: 3 }
        }
    }
}

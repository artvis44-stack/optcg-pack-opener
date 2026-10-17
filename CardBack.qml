import QtQuick

// Generic card back (drawn, not Bandai's artwork).
Rectangle {
    id: back
    radius: width * 0.05
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#1b2a4a" }
        GradientStop { position: 0.5; color: "#0e1730" }
        GradientStop { position: 1.0; color: "#1b2a4a" }
    }
    border.color: "#c9a14a"
    border.width: Math.max(2, width * 0.012)

    // diagonal pinstripes
    Item {
        anchors.fill: parent
        anchors.margins: back.width * 0.06
        clip: true
        Repeater {
            model: 28
            Rectangle {
                required property int index
                width: 2; height: back.height * 2
                x: index * back.width / 14 - back.width * 0.6
                y: -back.height * 0.5
                rotation: 30
                color: "#ffffff"
                opacity: 0.05
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: back.width * 0.06
        radius: back.radius * 0.7
        color: "transparent"
        border.color: "#c9a14a"
        border.width: 1
        opacity: 0.7
    }

    // compass rose
    Rectangle {
        id: medal
        anchors.centerIn: parent
        width: back.width * 0.48; height: width; radius: width / 2
        color: "#0b1226"
        border.color: "#e2bd63"
        border.width: Math.max(2, back.width * 0.01)
        Repeater {
            model: 8
            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: medal.width * (index % 2 ? 0.05 : 0.08)
                height: medal.height * (index % 2 ? 0.62 : 0.86)
                radius: width / 2
                rotation: index * 22.5
                color: "#e2bd63"
                opacity: index % 2 ? 0.5 : 0.9
            }
        }
        Text {
            anchors.centerIn: parent
            text: "OP"
            color: "#fff4d6"
            style: Text.Outline; styleColor: "#0b1226"
            font { pixelSize: medal.width * 0.3; weight: Font.Black; italic: true }
        }
    }
}

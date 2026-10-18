import QtQuick

// A rounded button that fills with its accent colour on hover.
Rectangle {
    id: button

    property string text
    property color accent: "#ffd56b"
    property real fontSize: 14
    property bool enabledLook: true
    signal clicked()

    width: label.width + fontSize * 2
    height: label.height + fontSize
    radius: height / 2
    color: mouse.containsMouse && enabledLook ? accent : "#1b2236"
    border.color: enabledLook ? accent : "#3a4258"
    opacity: enabledLook ? 1 : 0.6

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: mouse.containsMouse && button.enabledLook ? "#14171f" : (button.enabledLook ? button.accent : "#7a8090")
        font { pixelSize: button.fontSize; weight: Font.Bold }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}

// OPTCG desktop showcase -- macOS host window (see optcg.py --showcase).
// A card you picked with D, on the desktop above the icons; the shared
// ShowcaseCard does the rest, including the always-on status bar.
// Dragging uses macOS's own window dragging (startSystemMove), which is as
// smooth as moving any window; where it ends up is saved once it settles.
import QtQuick
import QtQuick.Window
import "../app"

Window {
    id: win
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    title: "OPTCG showcase"
    visible: true
    width: show.implicitWidth
    height: show.implicitHeight
    // placed from the saved distances, until the window is dragged
    x: screen.virtualX + screen.width - show.fromRight - width
    y: screen.virtualY + screen.height - show.fromBottom - height

    ShowcaseCard {
        id: show
        anchors.fill: parent
        host: macHost
        moveInside: false
        onSystemMoveRequested: {
            win.startSystemMove();
            settle.restart();
        }
    }

    // a native drag doesn't tell us when it ends: save once the window stops moving
    onXChanged: if (settle.running) settle.restart()
    onYChanged: if (settle.running) settle.restart()
    Timer {
        id: settle
        interval: 400
        onTriggered: show.placeAt(win.screen.virtualX + win.screen.width - win.x - win.width,
                                  win.screen.virtualY + win.screen.height - win.y - win.height)
    }
}

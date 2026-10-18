// OPTCG desktop showcase -- macOS host window (see optcg.py --showcase).
// A card you picked with D, on the desktop above the icons; the shared
// ShowcaseCard does the rest. Quits by itself when no card is picked.
import QtQuick
import QtQuick.Window
import "../app"

Window {
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    title: "OPTCG showcase"
    visible: true
    width: show.implicitWidth
    height: show.implicitHeight
    x: screen.virtualX + screen.width - show.fromRight - width
    y: screen.virtualY + screen.height - show.fromBottom - height

    ShowcaseCard {
        id: show
        anchors.fill: parent
        host: macHost
        onEmptied: Qt.quit()
    }
}

// Desktop showcase (Linux / Quickshell host): a card from your collection on
// the desktop, above the wallpaper and below your windows.
// run with: qs -n -p ~/.config/quickshell/optcg/showcase.qml
// Exits by itself when no card is picked, so it's safe to start at login.
import Quickshell
import Quickshell.Wayland
import QtQuick
import "app"

ShellRoot {
    PanelWindow {
        anchors { bottom: true; right: true }
        margins { bottom: show.fromBottom; right: show.fromRight }
        implicitWidth: show.implicitWidth
        implicitHeight: show.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "optcg-showcase"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ShowcaseCard {
            id: show
            anchors.fill: parent
            host: QuickshellHost {}
            onEmptied: Qt.quit()
        }
    }
}

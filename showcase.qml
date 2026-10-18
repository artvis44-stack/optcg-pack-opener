// Desktop showcase (Linux / Quickshell host): a card from your collection on
// the desktop, above the wallpaper and below your windows.
// run with: qs -n -p ~/.config/quickshell/optcg/showcase.qml
// Exits by itself when no card is picked, so it's safe to start at login.
//
// The layer covers the whole screen but only takes input on the card (the
// mask), so dragging moves the card inside it instead of moving a window --
// moving a layer surface takes a compositor round trip per step and lags.
import Quickshell
import Quickshell.Wayland
import QtQuick
import "app"

ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "optcg-showcase"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
            x: show.frameRect.x
            y: show.frameRect.y
            width: show.card ? show.frameRect.width : 0
            height: show.card ? show.frameRect.height : 0
        }

        ShowcaseCard {
            id: show
            anchors.fill: parent
            host: QuickshellHost {}
            moveInside: true
            onEmptied: Qt.quit()
        }
    }
}

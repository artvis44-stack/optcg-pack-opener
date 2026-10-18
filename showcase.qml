// Desktop companion (Linux / Quickshell host): the status bar and a card from
// your collection on the desktop, above the wallpaper and below your windows.
// run with: qs -n -p ~/.config/quickshell/optcg/showcase.qml
// Always running (started at login): the status bar is there even with no card picked.
//
// The layer covers the whole screen but only takes input on the widget (the
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
            width: show.frameRect.width
            height: show.frameRect.height
        }

        ShowcaseCard {
            id: show
            anchors.fill: parent
            host: QuickshellHost {}
            moveInside: true
        }
    }
}

// OPTCG booster pack opener -- run with: qs -p ~/.config/quickshell/optcg
import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "optcg"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Stage { anchors.fill: parent }
    }
}

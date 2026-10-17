// OPTCG booster pack opener -- run with: qs -p ~/.config/quickshell/optcg
// Linux / Quickshell host: the overlay window, IPC, and file/env access.
// Everything else is the platform-independent app in app/.
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "app"

ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "optcg"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Stage {
            id: stage
            anchors.fill: parent
            host: QuickshellHost {}
        }
    }

    // scriptable: qs ipc -p ~/.config/quickshell/optcg call optcg advance
    IpcHandler {
        target: "optcg"
        function advance(): void { stage.advance(); }
        function revealAll(): void { stage.revealAll(); }
        function newPack(): void { if (stage.db) stage.newPack(); }
        function close(): void { stage.close(); }
        function inspect(index: int): void { if (stage.phase === "summary") stage.inspectIndex = index; }
        function binder(): void { stage.toggleBinder(); }
        function switchMode(): void { stage.switchMode(); }
        function openAll(): void { stage.openAllRemaining(); }
        function openPack(index: int): void { if (stage.phase === "boxGrid") stage.openBoxPack(index); }
        function sets(): void { stage.toggleSets(); }
        function chooseSet(id: string): void { stage.chooseSet(id); }
        // debugging: render the overlay to a PNG
        function snapshot(path: string): void { stage.grabToImage(r => r.saveToFile(path)); }
    }
}

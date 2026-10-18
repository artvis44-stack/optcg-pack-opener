// OPTCG pack opener -- macOS host window (see optcg.py).
// The same app as the Linux version: everything in ../app, with `macHost`
// (from optcg.py) as its host.
import QtQuick
import QtQuick.Window
import "../app"

Window {
    id: win
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "OPTCG"

    Stage {
        id: stage
        anchors.fill: parent
        host: macHost
    }

    // commands for `optcg.py --ipc NAME [ARG]` (the Linux version's `qs ipc`)
    function advance() { stage.advance(); }
    function revealAll() { stage.revealAll(); }
    function newPack() { if (stage.db) stage.newPack(); }
    function closeOverlay() { stage.close(); }   // Window already has a close()
    function inspect(index) { if (stage.phase === "summary") stage.inspectIndex = parseInt(index); }
    function binder() { stage.toggleBinder(); }
    function switchMode() { stage.switchMode(); }
    function openAll() { stage.openAllRemaining(); }
    function openPack(index) { if (stage.phase === "boxGrid") stage.openBoxPack(parseInt(index)); }
    function sets() { stage.toggleSets(); }
    function chooseSet(id) { stage.chooseSet(String(id)); }
    function showcase() { stage.showcase(stage.focusedCard()); }
    function board() { stage.toggleBoard(); }
    function sellBulk() { stage.sell(stage.bulkDuplicates); }
    function snapshot(path) { stage.grabToImage(r => r.saveToFile(String(path))); }
}

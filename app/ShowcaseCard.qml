import QtQuick
import "tiers.js" as Tiers

// The desktop showcase: one card from your collection sitting on the desktop.
// Hover to tilt it (the foil only animates then, so it costs nothing while
// you work), drag to move, scroll to resize, right-click to put it away.
//
// The card and its placement live in showcase.json, written by the pack
// opener (D on a card) and by this item; it's re-read every couple of seconds,
// so picking another card swaps it live. Shared by the Linux and macOS hosts:
//   moveInside: true   the host gives this the whole screen (clicks only land
//                      on `frame`, see frameRect) and dragging moves the card
//                      inside it -- no window moves, so it tracks the mouse 1:1
//   moveInside: false  the window is just the card; dragging asks the host to
//                      move the window natively (systemMoveRequested), and the
//                      host reports where it ended up via placeAt()
Item {
    id: show

    required property QtObject host
    property bool moveInside: true
    readonly property string path: (host.env("XDG_DATA_HOME") || host.env("HOME") + "/.local/share") + "/optcg/showcase.json"

    property var card: null
    property real cardWidth: 260
    property real fromRight: 60     // distance from the screen's right edge
    property real fromBottom: 80    // ...and bottom edge
    property string lastText: ""
    property bool dragging: false
    readonly property real pad: cardWidth * 0.12   // room for the shadow and the tilt
    readonly property real frameWidth: cardWidth + 2 * pad
    readonly property real frameHeight: cardWidth / 0.716 + 2 * pad
    readonly property rect frameRect: Qt.rect(frame.x, frame.y, frame.width, frame.height)

    signal emptied()                // nothing to show: the host can quit
    signal systemMoveRequested()    // moveInside: false -- start a native window drag

    implicitWidth: frameWidth
    implicitHeight: frameHeight

    function load() {
        var text = host.readText(path);
        if (text === lastText) return;
        lastText = text;
        var s = null;
        try { s = text ? JSON.parse(text) : null; } catch (e) {}
        if (!s || !s.card) {
            card = null;
            emptied();
            return;
        }
        card = s.card;
        if (s.width) cardWidth = s.width;
        if (s.right !== undefined) fromRight = s.right;
        if (s.bottom !== undefined) fromBottom = s.bottom;
    }

    function save() {
        lastText = JSON.stringify({ card: card, width: cardWidth, right: fromRight, bottom: fromBottom });
        host.writeText(path, lastText);
    }

    // moveInside: false -- the host's window was moved; remember where
    function placeAt(right, bottom) {
        fromRight = Math.max(0, right);
        fromBottom = Math.max(0, bottom);
        save();
    }

    Component.onCompleted: load()
    Timer {
        interval: 1500
        running: !show.dragging
        repeat: true
        onTriggered: show.load()
    }

    // foil clock: only runs while hovered (and not while dragging)
    property real t: 0
    FrameAnimation {
        running: mouse.containsMouse && !show.dragging
        onTriggered: show.t += frameTime
    }

    Item {
        id: frame
        width: show.frameWidth
        height: show.frameHeight
        x: show.moveInside ? show.width - show.fromRight - width : 0
        y: show.moveInside ? show.height - show.fromBottom - height : 0
        visible: !!show.card

        Card {
            x: show.pad
            y: show.pad
            width: show.cardWidth
            card: show.card
            faceUp: true
            time: show.t
            readonly property bool tilting: mouse.containsMouse && !show.dragging
            tiltX: tilting ? (mouse.mouseX - frame.width / 2) / (width / 2) : 0
            tiltY: tilting ? (mouse.mouseY - frame.height / 2) / (height / 2) : 0
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: show.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real grabX
            property real grabY

            onPressed: e => {
                if (e.button !== Qt.LeftButton) return;
                if (!show.moveInside) {        // native window drag
                    show.systemMoveRequested();
                    return;
                }
                grabX = e.x;
                grabY = e.y;
                show.dragging = true;
            }
            onPositionChanged: e => {
                if (!show.dragging) return;
                // in the full-screen item's coordinates, which don't move
                var p = mapToItem(show, e.x, e.y);
                show.fromRight = Math.max(0, Math.min(show.width - frame.width, show.width - (p.x - grabX) - frame.width));
                show.fromBottom = Math.max(0, Math.min(show.height - frame.height, show.height - (p.y - grabY) - frame.height));
            }
            onReleased: e => {
                if (!show.dragging) return;
                show.dragging = false;
                show.save();
            }
            onClicked: e => {
                if (e.button !== Qt.RightButton) return;
                show.card = null;     // put it away
                show.save();
                show.emptied();
            }
            onWheel: w => {
                var f = w.angleDelta.y > 0 ? 1.08 : 1 / 1.08;
                show.cardWidth = Math.max(120, Math.min(600, show.cardWidth * f));
                show.save();
            }
        }
    }
}

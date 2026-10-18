import QtQuick
import "tiers.js" as Tiers

// The desktop showcase: one card from your collection sitting on the desktop.
// Hover to tilt it (the foil only animates then, so it costs nothing while
// you work), drag to move, scroll to resize, right-click to put it away.
//
// The card and its placement live in showcase.json, written by the pack
// opener (D on a card) and by this item; it's re-read every couple of seconds,
// so picking another card swaps it live. Shared by the Linux and macOS hosts,
// which put this in a desktop-level window placed by fromRight / fromBottom.
Item {
    id: show

    required property QtObject host
    readonly property string path: (host.env("XDG_DATA_HOME") || host.env("HOME") + "/.local/share") + "/optcg/showcase.json"

    property var card: null
    property real cardWidth: 260
    property real fromRight: 60     // distance from the screen's right edge
    property real fromBottom: 80    // ...and bottom edge
    property string lastText: ""
    readonly property real pad: cardWidth * 0.12   // room for the shadow and the tilt

    signal emptied()               // nothing to show: the host can quit

    implicitWidth: cardWidth + 2 * pad
    implicitHeight: cardWidth / 0.716 + 2 * pad

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

    Component.onCompleted: load()
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: show.load()
    }

    // foil clock: only runs while hovered
    property real t: 0
    FrameAnimation {
        running: mouse.containsMouse
        onTriggered: show.t += frameTime
    }

    Card {
        id: cardItem
        x: show.pad
        y: show.pad
        width: show.cardWidth
        card: show.card
        faceUp: true
        visible: !!show.card
        time: show.t
        tiltX: mouse.containsMouse ? (mouse.mouseX - show.width / 2) / (width / 2) : 0
        tiltY: mouse.containsMouse ? (mouse.mouseY - show.height / 2) / (height / 2) : 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX
        property real pressY

        onPressed: e => {
            pressX = e.x;
            pressY = e.y;
        }
        // the window follows the drag, so the pointer stays at the press point
        // inside it; each step moves by how far it has drifted from there
        onPositionChanged: e => {
            if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
            show.fromRight = Math.max(0, show.fromRight - (e.x - pressX));
            show.fromBottom = Math.max(0, show.fromBottom - (e.y - pressY));
        }
        onReleased: e => { if (e.button === Qt.LeftButton) show.save(); }
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

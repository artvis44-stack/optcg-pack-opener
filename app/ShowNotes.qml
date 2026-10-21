import QtQuick
import "progress.js" as Progress

// Your notes for the card show: a notepad for prices and what to look out for. In the
// Port's card shop tab and at the show (the "Notes" button). Saved as you type
// (Stage.saveShowNotes: synced with your progress).
Rectangle {
    id: pad

    property Item stage
    property bool closable: false        // at the show: a close button
    signal close()

    radius: 12
    color: "#f4ecd6"                     // paper
    border.color: "#c8b88a"
    border.width: 1

    // what's saved, when it changes elsewhere (another computer, or the other notepad)
    readonly property string saved: stage ? Progress.showNotes(stage.progress) : ""
    onSavedChanged: if (!edit.activeFocus && edit.text !== saved) edit.text = saved
    Component.onCompleted: edit.text = saved
    onVisibleChanged: if (!visible) save()

    function save() {
        saveTimer.stop();
        if (stage) stage.saveShowNotes(edit.text);
    }
    Timer {
        id: saveTimer
        interval: 700
        onTriggered: pad.save()
    }

    Row {
        id: top
        x: 16; y: 10
        width: parent.width - 32
        Text {
            width: parent.width - (closeButton.visible ? closeButton.width : 0)
            text: "Show notes"
            color: "#5a4325"
            font { pixelSize: 17; weight: Font.Black; italic: true }
        }
        PillButton {
            id: closeButton
            visible: pad.closable
            text: "Close"
            fontSize: 12
            accent: "#e8c48a"
            onClicked: { pad.save(); pad.close(); }
        }
    }

    FontMetrics {
        id: metrics
        font: edit.font
    }
    Repeater {   // ruled lines, under the lines of text
        model: Math.max(0, Math.floor((pad.height - 48) / metrics.lineSpacing) + 1)
        Rectangle {
            required property int index
            x: 12
            y: 44 + edit.topPadding + (index + 1) * metrics.lineSpacing - flick.contentY % metrics.lineSpacing + 1
            visible: y > 44 && y < pad.height - 6
            width: pad.width - 24
            height: 1
            color: "#d8c9a0"
        }
    }

    Flickable {
        id: flick
        anchors { fill: parent; topMargin: 44; leftMargin: 16; rightMargin: 16; bottomMargin: 8 }
        contentHeight: edit.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        function follow(r) {   // keep the cursor in view as you type
            if (contentY >= r.y) contentY = r.y;
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
        }
        TextEdit {
            id: edit
            width: flick.width
            height: Math.max(implicitHeight + 16, flick.height)   // click anywhere on the paper to write
            topPadding: 8
            wrapMode: TextEdit.Wrap
            color: "#2b1a0c"
            selectionColor: "#c8a96a"
            font.pixelSize: 16
            textFormat: TextEdit.PlainText
            onCursorRectangleChanged: flick.follow(cursorRectangle)
            onTextChanged: {
                if (length > Progress.SHOW_NOTES_MAX) remove(Progress.SHOW_NOTES_MAX, length);
                if (activeFocus) saveTimer.restart();
            }
            onActiveFocusChanged: if (!activeFocus) pad.save()
            Keys.onEscapePressed: event => {   // let go of the keyboard (Esc again closes what's open)
                pad.save();
                pad.stage.forceActiveFocus();
                event.accepted = true;
            }
            Text {
                y: edit.topPadding
                visible: !edit.text && !edit.activeFocus
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Click to write. Prices you looked up, cards you're after, what you'd pay for them..."
                color: "#a89470"
                font { pixelSize: 15; italic: true }
            }
        }
    }
}

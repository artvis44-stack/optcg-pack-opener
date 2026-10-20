import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Nico Robin's notes (a crew perk, from the Port and at the card show): what every vintage
// card and sealed vintage product is worth if it's genuine, raw and slabbed (Stage.robinNotes:
// the prices the show's vendors price from). Filter by game, search by name, set or number.
Rectangle {
    id: notes

    property Item stage
    property string line: ""             // "" = everything, else "ccg" | "hb" | "sealed"
    property string search: ""
    signal close()

    color: "#ee05070d"

    readonly property var all: stage && visible ? stage.robinNotes().list : []
    readonly property var rows: {
        var q = search.trim().toLowerCase();
        return all.filter(x => (!line || x.line === line)
                               && (!q || (x.card.name + " " + x.card.id + " " + (x.card.origin || "") + " " + (x.card.character || ""))
                                         .toLowerCase().indexOf(q) >= 0));
    }

    onVisibleChanged: if (!visible) { search = ""; stage.forceActiveFocus(); }

    function fromText(c) {
        return (c.set === "HYPERBATTLE" ? "Carddass Hyper Battle" : "One Piece CCG") + (c.origin ? " · " + c.origin : "");
    }

    MouseArea {
        anchors.fill: parent
        onClicked: notes.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(notes.width * 0.92, 920)
        height: notes.height * 0.86
        radius: 14
        color: "#151b2c"
        border.color: "#c8a0ff"
        border.width: 2
        MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

        Column {
            id: head
            x: 20; y: 16
            width: parent.width - 40
            spacing: 8
            Text {
                text: "Robin's notes"
                color: "#c8a0ff"
                font { pixelSize: 26; weight: Font.Black; italic: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "\"I've spent years with the old games. This is what a genuine one goes for. A fake is worth nothing, "
                      + "so look closely before you pay.\""
                color: "#e6d6ff"
                font { pixelSize: 13; italic: true }
            }
            Row {
                spacing: 8
                Repeater {
                    model: [["", "Everything"], ["ccg", "One Piece CCG"], ["hb", "Hyper Battle"], ["sealed", "Sealed"]]
                    PillButton {
                        id: lineButton
                        required property var modelData
                        text: modelData[1]
                        fontSize: 12
                        accent: notes.line === modelData[0] ? "#c8a0ff" : "#7a8090"
                        onClicked: notes.line = lineButton.modelData[0]
                    }
                }
                Rectangle {
                    width: 220
                    height: 30
                    radius: 15
                    color: "#0e1322"
                    border.color: searchInput.activeFocus ? "#c8a0ff" : "#2c3550"
                    TextInput {
                        id: searchInput
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#e8e8ee"
                        font.pixelSize: 13
                        clip: true
                        text: notes.search
                        onTextChanged: notes.search = text
                        Keys.onEscapePressed: event => {   // clear, then let go of the keyboard
                            if (text) text = "";
                            else notes.stage.forceActiveFocus();
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: notes.stage.forceActiveFocus()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchInput.text && !searchInput.activeFocus
                            text: "Search: name, set, number"
                            color: "#5a6070"
                            font.pixelSize: 13
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: notes.rows.length + " of " + notes.all.length
                    color: "#9aa0ad"
                    font.pixelSize: 12
                }
            }
            Text {   // the column heads
                width: parent.width
                text: "Worth, if genuine:   raw   ·   graded 9   ·   graded 10"
                horizontalAlignment: Text.AlignRight
                color: "#9aa0ad"
                font { pixelSize: 12; weight: Font.Bold }
            }
        }

        ListView {
            anchors {
                top: head.bottom; topMargin: 8
                bottom: foot.top; bottomMargin: 8
                left: parent.left; leftMargin: 12
                right: parent.right; rightMargin: 12
            }
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: notes.rows
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var c: modelData.card
                width: ListView.view.width
                height: 64
                radius: 8
                color: "#0e1322"
                Card {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    card: row.c
                    faceUp: true
                    dropShadow: false
                }
                Column {
                    x: 64
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - prices.width - 24
                    spacing: 3
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tiers.displayName(row.c)
                        color: "#fff6e0"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: notes.fromText(row.c) + (row.modelData.line === "sealed" ? "" : "  ·  " + row.c.id) + "  ·  " + Tiers.tierOf(row.c).label
                        color: Tiers.tierOf(row.c).color
                        font.pixelSize: 12
                    }
                }
                Text {
                    id: prices
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    readonly property int v: row.modelData.value
                    text: row.modelData.line === "sealed" ? Progress.format(v) + "   ·   sealed"
                          : Progress.format(v) + "   ·   " + Progress.format(Math.round(v * Progress.GRADE_MULT[9]))
                            + "   ·   " + Progress.format(Math.round(v * Progress.GRADE_MULT[10]))
                    color: "#ffd56b"
                    font { pixelSize: 14; weight: Font.Black }
                }
            }
        }

        Row {
            id: foot
            anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
            spacing: 10
            PillButton {
                text: "Close"
                fontSize: 13
                accent: "#9aa0ad"
                onClicked: notes.close()
            }
        }
    }
}

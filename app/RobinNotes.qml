import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Nico Robin's notes (a crew perk, from the Port and at the card show): what every vintage
// card and sealed vintage product is worth if it's genuine, raw and slabbed (Stage.robinNotes:
// the prices the show's vendors price from). Filter by game, sort, search by name, set or
// number; click a line to see the card big beside the list.
Rectangle {
    id: notes

    property Item stage
    property string line: ""             // "" = everything, else "ccg" | "hb" | "sealed"
    property string search: ""
    property string sort: "value"        // value | cheap | name | set
    property string picked: ""           // the line shown big (its key)
    signal close()

    color: "#f205070d"

    readonly property var all: stage && visible ? stage.robinNotes().list : []
    readonly property var sorts: [["value", "Most valuable"], ["cheap", "Cheapest"], ["name", "Name A–Z"], ["set", "By set"]]
    readonly property var found: {
        var q = search.trim().toLowerCase();
        var out = all.filter(x => (!line || x.line === line)
                                  && (!q || (x.card.name + " " + x.card.id + " " + (x.card.origin || "") + " " + (x.card.character || ""))
                                            .toLowerCase().indexOf(q) >= 0));
        if (sort === "cheap") out.sort((a, b) => a.value - b.value);
        else if (sort === "name") out.sort((a, b) => Tiers.displayName(a.card).localeCompare(Tiers.displayName(b.card)));
        else if (sort === "set") out.sort((a, b) => fromText(a.card).localeCompare(fromText(b.card)) || (a.card.id + "").localeCompare(b.card.id + "", undefined, { numeric: true }));
        return out;   // "value": the list comes most valuable first
    }
    // what the list shows: by set, each set gets a heading line
    readonly property var rows: {
        if (sort !== "set") return found;
        var out = [], last = null;
        found.forEach(x => {
            var g = fromText(x.card);
            if (g !== last) out.push({ heading: g, count: found.filter(y => fromText(y.card) === g).length });
            last = g;
            out.push(x);
        });
        return out;
    }
    readonly property var shown: picked ? all.filter(x => x.key === picked)[0] || null : null

    onVisibleChanged: if (!visible) { search = ""; picked = ""; stage.forceActiveFocus(); }
    onLineChanged: list.positionViewAtBeginning()
    onSortChanged: list.positionViewAtBeginning()

    function fromText(c) {
        return (c.set === "HYPERBATTLE" ? "Carddass Hyper Battle" : "One Piece CCG") + (c.origin ? " · " + c.origin : "");
    }
    function graded(v, g) { return Progress.format(Math.round(v * Progress.GRADE_MULT[g])); }

    MouseArea {
        anchors.fill: parent
        onClicked: notes.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(notes.width * 0.96, 1400)
        height: notes.height * 0.92
        radius: 16
        color: "#151b2c"
        border.color: "#c8a0ff"
        border.width: 2
        MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

        readonly property bool wide: width >= 1000                // room for the big card beside the list
        readonly property real priceW: Math.max(124, Math.min(150, width * 0.1))

        Column {
            id: head
            x: 24; y: 20
            width: parent.width - 48
            spacing: 10
            Row {
                width: parent.width
                spacing: 16
                Text {
                    id: title
                    text: "Robin's notes"
                    color: "#c8a0ff"
                    font { pixelSize: 32; weight: Font.Black; italic: true }
                }
                Text {
                    anchors.verticalCenter: title.verticalCenter
                    width: parent.width - title.width - 16
                    wrapMode: Text.WordWrap
                    text: "\"I've spent years with the old games. This is what a genuine one goes for. A fake is worth nothing, "
                          + "so look closely before you pay.\""
                    color: "#e6d6ff"
                    font { pixelSize: 15; italic: true }
                }
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: [["", "Everything"], ["ccg", "One Piece CCG"], ["hb", "Hyper Battle"], ["sealed", "Sealed"]]
                    PillButton {
                        id: lineButton
                        required property var modelData
                        text: modelData[1]
                        fontSize: 14
                        accent: notes.line === modelData[0] ? "#c8a0ff" : "#7a8090"
                        onClicked: notes.line = lineButton.modelData[0]
                    }
                }
                Item { width: 16; height: 1 }
                Text {
                    height: 33
                    verticalAlignment: Text.AlignVCenter
                    text: "Sort"
                    color: "#9aa0ad"
                    font { pixelSize: 14; weight: Font.Bold }
                }
                Repeater {
                    model: notes.sorts
                    PillButton {
                        id: sortButton
                        required property var modelData
                        text: modelData[1]
                        fontSize: 14
                        accent: notes.sort === modelData[0] ? "#ffd56b" : "#7a8090"
                        onClicked: notes.sort = sortButton.modelData[0]
                    }
                }
            }
            Row {
                spacing: 12
                Rectangle {
                    width: Math.min(380, head.width * 0.5)
                    height: 36
                    radius: 18
                    color: "#0e1322"
                    border.color: searchInput.activeFocus ? "#c8a0ff" : "#2c3550"
                    TextInput {
                        id: searchInput
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#e8e8ee"
                        font.pixelSize: 15
                        clip: true
                        text: notes.search
                        onTextChanged: { notes.search = text; list.positionViewAtBeginning(); }
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
                            font.pixelSize: 15
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: notes.found.length + " of " + notes.all.length
                    color: "#9aa0ad"
                    font { pixelSize: 14; weight: Font.Bold }
                }
            }
        }

        // ---- the list ----
        Item {
            id: listArea
            anchors {
                top: head.bottom; topMargin: 14
                bottom: foot.top; bottomMargin: 12
                left: parent.left; leftMargin: 16
                right: preview.visible ? preview.left : parent.right; rightMargin: 16
            }

            Row {   // the column heads, over the price columns
                id: heads
                anchors.right: parent.right
                anchors.rightMargin: 26
                Repeater {
                    model: ["Raw", "Graded 9", "Graded 10"]
                    Text {
                        required property string modelData
                        width: panel.priceW
                        horizontalAlignment: Text.AlignRight
                        text: modelData
                        color: "#9aa0ad"
                        font { pixelSize: 13; weight: Font.Black; capitalization: Font.AllUppercase }
                    }
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: heads.verticalCenter }
                text: "Worth, if genuine"
                color: "#9aa0ad"
                font { pixelSize: 13; weight: Font.Black; capitalization: Font.AllUppercase }
            }

            ListView {
                id: list
                anchors { top: heads.bottom; topMargin: 8; bottom: parent.bottom; left: parent.left; right: parent.right }
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: notes.rows
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool heading: !!modelData.heading
                    readonly property var c: heading ? null : modelData.card
                    readonly property bool picked: !heading && notes.picked === modelData.key
                    width: ListView.view.width - 14
                    height: heading ? 44 : 84

                    Text {   // a set's heading (sorted by set)
                        visible: row.heading
                        anchors { left: parent.left; leftMargin: 6; bottom: parent.bottom; bottomMargin: 6 }
                        text: row.heading ? row.modelData.heading + "   ·   " + row.modelData.count : ""
                        color: "#ffd56b"
                        font { pixelSize: 18; weight: Font.Black }
                    }

                    Rectangle {
                        visible: !row.heading
                        anchors.fill: parent
                        radius: 10
                        color: row.picked ? "#2a2145" : hover.containsMouse ? "#1c2238" : row.index % 2 ? "#111628" : "#0e1322"
                        border.color: row.picked ? "#c8a0ff" : "transparent"
                        border.width: 2

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notes.picked = row.picked ? "" : row.modelData.key
                        }
                        Card {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            card: row.c
                            faceUp: true
                            dropShadow: false
                        }
                        Column {
                            x: 78
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 3 * panel.priceW - 24
                            spacing: 5
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.c ? Tiers.displayName(row.c) : ""
                                color: "#fff6e0"
                                font { pixelSize: 17; weight: Font.Bold }
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: !row.c ? "" : notes.fromText(row.c) + (row.modelData.line === "sealed" ? "" : "  ·  " + row.c.id)
                                color: "#9aa0ad"
                                font.pixelSize: 14
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.c ? Tiers.tierOf(row.c).label : ""
                                color: row.c ? Tiers.tierOf(row.c).color : "white"
                                font { pixelSize: 13; weight: Font.Bold }
                            }
                        }
                        Row {
                            id: priceRow
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            readonly property int v: row.heading ? 0 : row.modelData.value
                            readonly property bool sealed: !row.heading && row.modelData.line === "sealed"
                            Repeater {
                                model: 3
                                Text {
                                    required property int index
                                    width: panel.priceW
                                    horizontalAlignment: Text.AlignRight
                                    text: index === 0 ? Progress.format(priceRow.v)
                                          : priceRow.sealed ? "—" : notes.graded(priceRow.v, index === 1 ? 9 : 10)
                                    color: index === 0 ? "#ffd56b" : priceRow.sealed ? "#4a5370" : "#e8c48a"
                                    font { pixelSize: 17; weight: Font.Black }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !notes.rows.length
                    text: notes.all.length ? "Nothing in her notes matches that." : "Her notes are still coming in (the vintage cards are downloading)."
                    color: "#7a8090"
                    font { pixelSize: 16; italic: true }
                }
            }

            Rectangle {   // where you are in the list
                visible: list.contentHeight > list.height
                anchors.right: parent.right
                y: list.y + list.visibleArea.yPosition * list.height
                width: 6
                height: Math.max(30, list.visibleArea.heightRatio * list.height)
                radius: 3
                color: "#c8a0ff"
                opacity: 0.6
            }
        }

        // ---- the card you picked, big ----
        Rectangle {
            id: preview
            visible: panel.wide
            anchors { top: listArea.top; bottom: listArea.bottom; right: parent.right; rightMargin: 16 }
            width: Math.min(340, panel.width * 0.26)
            radius: 12
            color: "#0e1322"
            border.color: "#2c3550"

            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 12
                Card {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !!notes.shown
                    width: Math.max(60, Math.min(parent.width, (preview.height - 200) * 0.716))
                    card: notes.shown ? notes.shown.card : null
                    faceUp: true
                    hoverTilt: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: notes.shown ? Tiers.displayName(notes.shown.card) : "Click a line to look at it closely."
                    color: notes.shown ? "#fff6e0" : "#7a8090"
                    font { pixelSize: notes.shown ? 18 : 15; weight: Font.Bold; italic: !notes.shown }
                }
                Text {
                    visible: !!notes.shown
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: notes.shown ? notes.fromText(notes.shown.card) + "  ·  " + Tiers.tierOf(notes.shown.card).label : ""
                    color: notes.shown ? Tiers.tierOf(notes.shown.card).color : "white"
                    font { pixelSize: 14; weight: Font.Bold }
                }
            }
        }

        Row {
            id: foot
            anchors { bottom: parent.bottom; bottomMargin: 16; horizontalCenter: parent.horizontalCenter }
            spacing: 10
            PillButton {
                text: "Close"
                fontSize: 14
                accent: "#9aa0ad"
                onClicked: notes.close()
            }
        }
    }
}

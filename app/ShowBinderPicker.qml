pragma ComponentBehavior: Bound
import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// Filling your show binder (the Port's card shop tab, before a show): up to 15 cards from
// your collection, raw copies or slabs, to sell or trade at the card show. Your cards on
// the left (most valuable first, search and filter), the binder on the right.
Rectangle {
    id: picker

    property Item stage
    property string search: ""
    property string kind: ""             // "" everything, "raw", "slab"
    signal close()

    color: "#f205070d"

    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var binder: stage ? stage.showBinderItems : []
    readonly property bool full: binder.length >= Progress.SHOW_BINDER_SIZE
    // what you could put in: { key, slabId, card, grade, value, spare (raw copies not in it yet) }
    readonly property var candidates: {
        if (!stage || !visible) return [];
        var out = [], m = stage.markets, q = search.trim().toLowerCase();
        stage.allOwned.forEach(it => {
            var key = stage.cardKey(it.card), spare = it.count - stage.inShowBinder(key);
            if (kind !== "slab" && it.count > 0) {
                if (spare > 0) out.push({ key: key, slabId: "", card: it.card, grade: 0, spare: spare, value: Progress.cardValue(it.card, m[it.card.set]) });
            }
            if (kind !== "raw") it.slabs.forEach(s => {
                if (stage.lockedSlabs[s.slabId] || stage.slabInShowBinder(s.slabId)) return;
                out.push({ key: "", slabId: s.slabId, card: s, grade: s.grade, spare: 1, value: Progress.slabValue(s, m[s.set]) });
            });
        });
        return out.filter(x => !q || (x.card.name + " " + x.card.id + " " + x.card.set).toLowerCase().indexOf(q) >= 0)
                  .sort((a, b) => b.value - a.value);
    }

    onVisibleChanged: {
        if (!visible) {
            search = "";
            if (stage) stage.forceActiveFocus();
        } else if (stage) {
            stage.loadAllMarkets();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: picker.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(picker.width * 0.96, 1500)
        height: picker.height * 0.92
        radius: 16
        color: "#151b2c"
        border.color: "#7fd1b9"
        border.width: 2
        MouseArea { anchors.fill: parent }

        Column {
            id: head
            x: 24; y: 18
            width: parent.width - 48
            spacing: 8
            Text {
                text: "Your show binder"
                color: "#7fd1b9"
                font { pixelSize: 28; weight: Font.Black; italic: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Up to " + Progress.SHOW_BINDER_SIZE + " cards to take to the card show, to sell or trade with the vendors. "
                      + "Each one makes you an offer, cash or trade, by how honest they are: know what yours are worth. "
                      + "Cards in a display case can't come along."
                color: "#c8ccd6"
                font.pixelSize: 14
            }
            Row {
                spacing: 8
                Repeater {
                    model: [["", "Everything"], ["raw", "Raw cards"], ["slab", "Slabs"]]
                    PillButton {
                        id: kindButton
                        required property var modelData
                        text: modelData[1]
                        fontSize: 13
                        accent: picker.kind === modelData[0] ? "#7fd1b9" : "#7a8090"
                        onClicked: picker.kind = kindButton.modelData[0]
                    }
                }
                Rectangle {
                    width: 280
                    height: 32
                    radius: 16
                    color: "#0e1322"
                    border.color: searchInput.activeFocus ? "#7fd1b9" : "#2c3550"
                    TextInput {
                        id: searchInput
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#e8e8ee"
                        font.pixelSize: 14
                        clip: true
                        text: picker.search
                        onTextChanged: picker.search = text
                        Keys.onEscapePressed: event => {
                            if (text) text = "";
                            else picker.stage.forceActiveFocus();
                            event.accepted = true;
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchInput.text && !searchInput.activeFocus
                            text: "Search: name, set, number"
                            color: "#5a6070"
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }

        // ---- your cards ----
        ListView {
            id: list
            anchors {
                top: head.bottom; topMargin: 14
                bottom: parent.bottom; bottomMargin: 18
                left: parent.left; leftMargin: 18
            }
            width: parent.width * 0.48
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: picker.candidates
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width - 12
                height: 70
                radius: 8
                color: index % 2 ? "#111628" : "#0e1322"
                Card {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    card: row.modelData.card
                    faceUp: true
                    dropShadow: false
                }
                Column {
                    x: 64
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - addButton.width - valueText.width - 40
                    spacing: 3
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tiers.displayName(row.modelData.card)
                        color: "#fff6e0"
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.card.set + "  ·  " + (row.modelData.grade ? "graded " + row.modelData.grade
                                                                  : row.modelData.spare + (row.modelData.spare > 1 ? " copies" : " copy") + " left")
                              + "  ·  " + Tiers.tierOf(row.modelData.card).label
                        color: "#9aa0ad"
                        font.pixelSize: 12
                    }
                }
                Text {
                    id: valueText
                    anchors { right: addButton.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: Progress.format(row.modelData.value)
                    color: "#ffd56b"
                    font { pixelSize: 15; weight: Font.Black }
                }
                PillButton {
                    id: addButton
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Add"
                    fontSize: 12
                    accent: "#7fd1b9"
                    enabledLook: !picker.full
                    onClicked: picker.stage.addToShowBinder(row.modelData.key, row.modelData.slabId)
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !picker.candidates.length
                text: picker.search ? "Nothing matches that." : "No cards to bring yet."
                color: "#7a8090"
                font { pixelSize: 15; italic: true }
            }
        }
        Rectangle {   // where you are in the list
            visible: list.contentHeight > list.height
            x: list.x + list.width - 6
            y: list.y + list.visibleArea.yPosition * list.height
            width: 5
            height: Math.max(30, list.visibleArea.heightRatio * list.height)
            radius: 2.5
            color: "#7fd1b9"
            opacity: 0.5
        }

        // ---- the binder ----
        Rectangle {
            id: binderBox
            readonly property int cols: 5
            readonly property int rows: Math.ceil(Progress.SHOW_BINDER_SIZE / cols)
            readonly property real pocketW: Math.min((width - 24 - (cols - 1) * 8) / cols, ((height - 64 - (rows - 1) * 8) / rows - 30) * 0.716)
            anchors {
                top: list.top; bottom: list.bottom
                left: list.right; leftMargin: 18
                right: parent.right; rightMargin: 18
            }
            radius: 10
            color: "#1b2a4a"
            border.color: "#0a0a0a"
            border.width: 2
            Text {
                x: 14; y: 10
                text: picker.binder.length + " / " + Progress.SHOW_BINDER_SIZE + "  ·  worth "
                      + Progress.format(picker.binder.reduce((n, it) => n + it.value, 0))
                color: "#fff6e0"
                font { pixelSize: 16; weight: Font.Black }
            }
            PillButton {
                anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 8 }
                visible: picker.binder.length > 0
                text: "Empty it"
                fontSize: 12
                accent: "#ff9a7a"
                onClicked: picker.stage.removeFromShowBinder(picker.binder.map(it => it.id))
            }
            Grid {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 48 }
                columns: binderBox.cols
                spacing: 8
                Repeater {
                    model: Progress.SHOW_BINDER_SIZE
                    Item {
                        id: slot
                        required property int index
                        readonly property var it: picker.binder[index] || null
                        width: binderBox.pocketW
                        height: binderBox.pocketW / 0.716 + 30
                        Rectangle {
                            width: parent.width
                            height: parent.width / 0.716
                            radius: 4
                            color: "#22ffffff"
                            border.color: "#40ffffff"
                            Card {
                                visible: !!slot.it && !slot.it.grade
                                anchors.centerIn: parent
                                width: parent.width - 6
                                card: slot.it && !slot.it.grade ? slot.it.card : null
                                faceUp: true
                                dropShadow: false
                            }
                            Slab {
                                visible: !!slot.it && !!slot.it.grade
                                anchors.centerIn: parent
                                width: (parent.height - 6) / 1.64
                                card: slot.it && slot.it.grade ? slot.it.card : null
                                hoverTilt: false
                            }
                            Rectangle {   // take it out
                                visible: !!slot.it
                                anchors { right: parent.right; top: parent.top; margins: 3 }
                                width: 22; height: 22; radius: 11
                                color: removeMouse.containsMouse ? "#ff8a7a" : "#cc1b2236"
                                border.color: "#ff8a7a"
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font { pixelSize: 15; weight: Font.Black } }
                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: picker.stage.removeFromShowBinder([slot.it.id])
                                }
                            }
                        }
                        Text {
                            y: parent.width / 0.716 + 5
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            visible: !!slot.it
                            text: slot.it ? Progress.format(slot.it.value) + (slot.it.grade ? " · " + slot.it.grade : "") : ""
                            color: "#ffd56b"
                            font { pixelSize: 12; weight: Font.Black }
                        }
                    }
                }
            }
        }

        PillButton {
            anchors { right: parent.right; rightMargin: 20; top: parent.top; topMargin: 20 }
            text: "Done"
            fontSize: 13
            accent: "#7fd1b9"
            onClicked: picker.close()
        }
    }
}

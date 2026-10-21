import QtQuick

// What's new: the patch notes of the update that was just installed (mac/update.py saves
// them; every release since the one you had, newest first). Shown once, over everything.
Rectangle {
    id: patch

    property var notes: null            // { from, to, releases: [{ version, date, notes }] }
    signal close()

    color: "#ee05070d"

    MouseArea {
        anchors.fill: parent
        onClicked: patch.close()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(patch.width * 0.9, 760)
        height: Math.min(patch.height * 0.86, head.height + list.contentHeight + foot.height + 100)
        radius: 16
        color: "#151b2c"
        border.color: "#ffd56b"
        border.width: 2
        MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

        Column {
            id: head
            x: 28; y: 24
            width: parent.width - 56
            spacing: 4
            Text {
                text: "What's new"
                color: "#ffd56b"
                font { pixelSize: 30; weight: Font.Black; italic: true }
            }
            Text {
                text: patch.notes ? "Updated" + (patch.notes.from ? " from " + patch.notes.from : "") + " to " + patch.notes.to : ""
                color: "#9aa0ad"
                font { pixelSize: 15; weight: Font.Bold }
            }
        }

        Flickable {
            id: list
            anchors {
                top: head.bottom; topMargin: 16
                bottom: foot.top; bottomMargin: 12
                left: parent.left; leftMargin: 28
                right: parent.right; rightMargin: 28
            }
            contentHeight: releases.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: releases
                width: list.width
                spacing: 22
                Repeater {
                    model: patch.notes ? patch.notes.releases : []
                    Column {
                        id: release
                        required property var modelData
                        width: releases.width
                        spacing: 8
                        Row {
                            spacing: 12
                            Text {
                                text: release.modelData.version
                                color: "#fff6e0"
                                font { pixelSize: 20; weight: Font.Black }
                            }
                            Text {
                                anchors.baseline: parent.children[0].baseline
                                text: release.modelData.date || ""
                                color: "#7a8090"
                                font.pixelSize: 13
                            }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            textFormat: Text.MarkdownText
                            text: release.modelData.notes || "Fixes and improvements."
                            color: "#d8dce6"
                            font.pixelSize: 15
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }
        }
        Rectangle {   // where you are in the notes
            visible: list.contentHeight > list.height
            x: list.x + list.width + 10
            y: list.y + list.visibleArea.yPosition * list.height
            width: 5
            height: Math.max(30, list.visibleArea.heightRatio * list.height)
            radius: 2.5
            color: "#ffd56b"
            opacity: 0.5
        }

        PillButton {
            id: foot
            anchors { bottom: parent.bottom; bottomMargin: 20; horizontalCenter: parent.horizontalCenter }
            text: "Got it"
            onClicked: patch.close()
        }
    }
}

import QtQuick
import "progress.js" as Progress

// The wanted board: today's bounties on the left, every achievement as a
// wanted poster on the right (unlocked ones show their bounty and date,
// locked ones what it takes), with your total bounty and lifetime stats.
Item {
    id: board

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.95
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: board.height * 0.05
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Wanted Board"
            color: "#ffd56b"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Your bounty  " + Progress.format(Progress.totalBounty(board.p))
            color: "#fff6e0"
            font { pixelSize: 20; weight: Font.Black }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var s: board.p.stats
            text: s.packs + " packs  ·  " + s.boxes + " boxes  ·  " + s.cases + " cases  ·  "
                  + s.focus + " focus sessions  ·  " + s.sold + " cards sold for " + Progress.format(s.soldValue)
                  + "  ·  day " + board.p.streak.count + " streak"
            color: "#9aa0ad"
            font.pixelSize: 14
        }
    }

    // ---- today's bounties ------------------------------------------------------------
    Column {
        id: daily
        x: board.width * 0.05
        y: header.y + header.height + 36
        width: Math.min(420, board.width * 0.28)
        spacing: 14

        Text {
            text: "Today's bounties"
            color: "#ffd56b"
            font { pixelSize: 18; weight: Font.Black }
        }
        Repeater {
            model: board.p.bounties.list || []
            Rectangle {
                required property var modelData
                width: daily.width
                height: bountyColumn.height + 24
                radius: 10
                color: modelData.done ? "#163626" : "#151b2c"
                border.color: modelData.done ? "#6fdc8c" : "#2c3550"
                Column {
                    id: bountyColumn
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 6
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: (parent.parent.modelData.done ? "✓  " : "") + Progress.bountyText(parent.parent.modelData)
                        color: "#e8e8ee"
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: "#22283a"
                        Rectangle {
                            readonly property var b: parent.parent.parent.modelData
                            width: parent.width * Math.min(1, b.progress / b.goal)
                            height: parent.height
                            radius: 3
                            color: b.done ? "#6fdc8c" : "#ffd56b"
                        }
                    }
                    Text {
                        readonly property var b: parent.parent.modelData
                        text: (b.kind === "income" ? Progress.format(b.progress) + " / " + Progress.format(b.goal) : b.progress + " / " + b.goal)
                              + "   ·   reward " + Progress.bountyRewardText(b)
                        color: "#9aa0ad"
                        font.pixelSize: 12
                    }
                }
            }
        }
        Text {
            width: daily.width
            wrapMode: Text.WordWrap
            text: "New bounties every day. Earn berries by being at your computer, finishing focus sessions on the desktop widget, keeping your daily streak and selling duplicates in the binder."
            color: "#7a8090"
            font.pixelSize: 12
        }
    }

    // ---- wanted posters ----------------------------------------------------------------
    GridView {
        id: posters
        anchors {
            left: daily.right; leftMargin: board.width * 0.04
            right: parent.right; rightMargin: board.width * 0.04
            top: daily.top
            bottom: parent.bottom; bottomMargin: 44
        }
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 190)))
        cellHeight: 230
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Progress.ACHIEVEMENTS

        delegate: Item {
            required property var modelData
            readonly property string got: board.p.achievements[modelData.id] || ""
            width: posters.cellWidth
            height: posters.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 3
                color: parent.got ? "#ead9ae" : "#1a1f2e"
                border.color: parent.got ? "#5a4325" : "#2c3550"
                border.width: 2
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 4
                    readonly property var a: parent.parent.modelData
                    readonly property bool got: parent.parent.got !== ""
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "WANTED"
                        color: parent.got ? "#3b2a16" : "#3a4258"
                        font { pixelSize: 24; weight: Font.Black; family: "serif"; letterSpacing: 2 }
                    }
                    Rectangle {   // where the portrait would be
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.55
                        height: 44
                        color: parent.got ? "#d8c28f" : "#141927"
                        border.color: parent.got ? "#5a4325" : "#2c3550"
                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.got ? "★" : "?"
                            color: parent.parent.got ? "#7a4e10" : "#3a4258"
                            font { pixelSize: 26; weight: Font.Black }
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: parent.a.title.toUpperCase()
                        color: parent.got ? "#3b2a16" : "#9aa0ad"
                        font { pixelSize: 13; weight: Font.Black; family: "serif" }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: parent.a.text
                        color: parent.got ? "#5a4325" : "#7a8090"
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Progress.formatBounty(parent.a.bounty)
                        color: parent.got ? "#3b2a16" : "#4a5370"
                        font { pixelSize: 16; weight: Font.Black; family: "serif" }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.got ? parent.parent.parent.got : (parent.a.reward ? "+" + Progress.format(parent.a.reward) : "")
                        color: parent.got ? "#7a4e10" : "#4a5370"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: Object.keys(board.p.achievements).length + " / " + Progress.ACHIEVEMENTS.length + " posters   ·   W or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

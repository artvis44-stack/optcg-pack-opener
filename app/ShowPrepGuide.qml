import QtQuick
import "progress.js" as Progress

// The first time you head for the card show (K), the Port's card shop tab opens with this
// on top: the show is real berries and has no price tags, so here's what your show binder
// and notes are for. Get ready first (later) or go straight in (ready).
Rectangle {
    id: guide

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property bool robin: Progress.hasCrew(p, "robin")
    signal later()
    signal ready()

    color: "#e605070d"

    MouseArea { anchors.fill: parent }   // nothing underneath until it's put away

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(guide.width * 0.92, 820)
        height: Math.min(guide.height * 0.92, col.height + 56)
        radius: 16
        color: "#151b2c"
        border.color: "#ff9ad5"
        border.width: 2

        Flickable {
            anchors { fill: parent; margins: 28 }
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: parent.width
                spacing: 14

                Text {
                    text: "Before your first card show"
                    color: "#ff9ad5"
                    font { pixelSize: 30; weight: Font.Black; italic: true }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "The show is played with your real berries. Whatever you buy, sell or trade in there is for keeps, "
                          + "and once you're through the doors nothing shows a market price: not on their cards, not on yours. "
                          + "So get ready here first. Everything you need is on this tab."
                    color: "#e8e8ee"
                    font.pixelSize: 15
                    lineHeight: 1.15
                }

                Section {
                    title: "Your show binder"
                    accent: "#7fd1b9"
                    body: "Up to " + Progress.SHOW_BINDER_SIZE + " of your cards, raw or graded, to take along. At any table you can "
                          + "ask what the vendor would give for them: cash if you sell, or trade credit towards one of their cards. "
                          + "Some cards are kept under the table and only ever traded, never sold, so a good binder can get you "
                          + "things berries can't. Only what's in the binder comes with you, and it's packed once you walk in."
                }
                Section {
                    title: "Your notes"
                    accent: "#f4ecd6"
                    body: "Inside you won't see what anything is worth, so write down what matters: what your binder cards "
                          + "go for, the cards you're hunting, and the most you'd pay for each. Your notes come with you "
                          + "(the Notes button at the show) and save as you type."
                }
                Section {
                    visible: guide.robin
                    title: "Robin's notes"
                    accent: "#c8a0ff"
                    body: "Robin's vintage price list stays here at the Port. Study it before you go: in there it's on you."
                }
                Section {
                    title: "One visit a day"
                    accent: "#ffd56b"
                    body: "There's a show every day, and it's " + Progress.format(Progress.SHOW_ENTRY) + " at the door ("
                          + Progress.format(Progress.SHOW_EARLY) + " more to get in before the crowd). Once you leave, that's it "
                          + "until tomorrow, so don't rush out with berries you meant to spend."
                }

                Item { width: 1; height: 4 }
                Row {
                    spacing: 12
                    PillButton {
                        text: "Get ready first"
                        accent: "#7fd1b9"
                        onClicked: guide.later()
                    }
                    PillButton {
                        text: "I'm ready, go in  K"
                        accent: "#ff9ad5"
                        onClicked: guide.ready()
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "When you're done, press K or \"Go to the card show\" at the top of this tab."
                    color: "#9aa0ad"
                    font.pixelSize: 13
                }
            }
        }
    }

    component Section: Column {
        property string title
        property string body
        property color accent
        width: col.width
        spacing: 4
        Text {
            text: parent.title
            color: parent.accent
            font { pixelSize: 18; weight: Font.Black }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: parent.body
            color: "#c8ccd6"
            font.pixelSize: 14
            lineHeight: 1.15
        }
    }
}

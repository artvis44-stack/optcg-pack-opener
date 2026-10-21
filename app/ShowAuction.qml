import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The expo's auction (Progress.showAuction): one gem-mint lot, authenticated by the house.
// It opens once the hall clock gets there; then you bid a step at a time against whoever's
// left in the room, or put your paddle down. Their limits are hidden; from Regular up you can
// read their style.
Rectangle {
    id: room

    property Item stage
    property Item hall                   // CardShow: cardOf(), crowd clock
    signal close()

    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var a: Progress.showAuction(p)
    readonly property var rivals: a ? Progress.auctionRivals(a) : []
    readonly property var next: a ? Progress.auctionNext(a) : null
    readonly property bool readStyles: Progress.showLevel(p) >= 2
    readonly property int opensIn: a && !a.state ? Math.max(0, Progress.SHOW_AUCTION.at - (Progress.showState(p).clock || 0)) : 0
    readonly property var styleName: ({ cautious: "cautious", steady: "steady", stubborn: "stubborn" })

    color: "#ee05070d"

    MouseArea {
        anchors.fill: parent
        onClicked: room.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(room.width * 0.92, 980)
        height: Math.min(room.height * 0.9, 620)
        radius: 16
        color: "#1a1424"
        border.color: "#ffd56b"
        border.width: 2
        MouseArea { anchors.fill: parent }   // clicks on the stage don't close it

        Row {
            anchors { fill: parent; margins: 30 }
            spacing: 36

            Slab {   // the lot
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(260, parent.height * 0.6)
                card: room.a && room.hall ? room.hall.cardOf(room.a.lot) : null
                time: room.stage ? room.stage.t : 0
            }

            Column {
                width: parent.width - 296
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "The Auction"
                    color: "#ffd56b"
                    font { pixelSize: 30; weight: Font.Black; italic: true }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: room.a ? Tiers.displayName(room.a.lot.card) + "  ·  gem mint 10  ·  authenticated by the house" : ""
                    color: "#fff6e0"
                    font { pixelSize: 17; weight: Font.Bold }
                }

                // not open yet
                Text {
                    visible: !!room.a && !room.a.state
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "The auction starts after " + room.opensIn + " more thing" + (room.opensIn > 1 ? "s" : "")
                          + " you do in the hall. Bidding opens at " + (room.a ? Progress.format(room.a.lot.ask) : "") + "."
                    color: "#c8ccd6"
                    font.pixelSize: 15
                }

                // open, or over
                Text {
                    visible: !!room.a && !!room.a.state
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !room.a || !room.a.state ? ""
                          : room.a.state === "won" ? "SOLD to you for " + Progress.format(room.a.paid) + " with the buyer's premium."
                          : room.a.state === "lost" ? (room.a.leader ? "Sold to " + room.a.leader.toLowerCase() + " for " + Progress.format(room.a.bid) + "."
                                                                    : "You put your paddle down.")
                          : room.a.leader === "you" ? "Your bid: " + Progress.format(room.a.bid) + ". It's yours unless someone goes higher."
                          : room.a.leader ? room.a.leader + " bids " + Progress.format(room.a.bid) + "."
                          : "Bidding opens at " + Progress.format(room.a.bid) + ". Nobody's bid yet."
                    color: room.a && room.a.state === "won" ? "#7fd1b9" : room.a && room.a.state === "lost" ? "#9aa0ad" : "#ffd56b"
                    font { pixelSize: 22; weight: Font.Black }
                }
                Text {
                    visible: !!room.a && room.a.state === "open"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: room.rivals.length ? "Still in: " + room.rivals.map(b => b.name + (room.readStyles ? " (" + room.styleName[b.style] + ")" : "")).join(", ")
                                             : "Nobody else is in."
                    color: "#c8ccd6"
                    font.pixelSize: 14
                }
                Text {
                    visible: !!room.a && room.a.state === "open" && !room.readStyles
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "At Regular you'll be able to read the room: who's cautious, who's stubborn."
                    color: "#7a8090"
                    font { pixelSize: 12; italic: true }
                }
                Row {
                    visible: !!room.a && room.a.state === "open"
                    spacing: 10
                    PillButton {
                        visible: !!room.a && room.a.leader !== "you"
                        text: room.next ? "Bid " + Progress.format(room.next.bid) + "  (" + Progress.format(room.next.cost) + " with the premium)" : ""
                        accent: "#ffd56b"
                        enabledLook: !!room.next && room.p.berries >= room.next.cost
                        onClicked: room.stage.auctionBid()
                    }
                    PillButton {
                        text: "Put my paddle down"
                        accent: "#9aa0ad"
                        onClicked: room.stage.auctionDrop()
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Each bid is " + Math.round(Progress.SHOW_AUCTION.step * 100) + "% of the lot's value, plus a "
                          + Math.round(Progress.SHOW_AUCTION.premium * 100) + "% buyer's premium if you win. Every bid moves the hall clock on."
                    color: "#7a8090"
                    font.pixelSize: 12
                }
                PillButton {
                    text: "Back to the hall"
                    fontSize: 13
                    accent: "#9aa0ad"
                    onClicked: room.close()
                }
            }
        }
    }
}

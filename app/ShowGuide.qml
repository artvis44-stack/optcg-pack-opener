import QtQuick
import "progress.js" as Progress

// The first time you walk into the card show: a few pages on how it works (the hall,
// buying and haggling, who's behind the tables, spotting a fake, selling and trading your
// binder), then off you go. Skip it any time (Esc); it doesn't come back.
Rectangle {
    id: guide

    property Item stage
    property Item hall                   // CardShow: cardOf()
    property int page: 0
    signal done()

    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property int pages: 6

    // the example for spotting a fake: a slab from the hall (an honest one, a modern 10 if
    // there is one), and the same card as a scammer would sell it
    readonly property var example: {
        var stock = Progress.showState(p).stock || [], best = null, score = -1;
        stock.forEach(t => (t.listings || []).forEach(x => {
            if (!x.grade || x.fake || x.sealed || t.kind === "scammer") return;
            var sc = (x.grade === 10 ? 2 : 0) + (Progress.isShowSet(x.card.set) ? 0 : 1);
            if (sc > score) { best = x; score = sc; }
        }));
        return best && hall ? hall.cardOf(best) : null;
    }
    readonly property var exampleFake: example ? Object.assign({}, example, { fake: true, fakeLook: 0.5, tells: ["label", "case"] }) : null

    color: "#ee05070d"
    onVisibleChanged: if (visible) page = 0

    MouseArea { anchors.fill: parent }   // the hall waits

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(guide.width * 0.92, 900)
        height: Math.min(guide.height * 0.9, 680)
        radius: 16
        color: "#151b2c"
        border.color: "#ffd56b"
        border.width: 2

        Text {
            id: kicker
            x: 30; y: 22
            text: "Your first card show  ·  " + (guide.page + 1) + " / " + guide.pages
            color: "#9aa0ad"
            font { pixelSize: 13; weight: Font.Bold; letterSpacing: 1 }
        }

        Flickable {
            id: flick
            anchors {
                top: kicker.bottom; topMargin: 10
                left: parent.left; leftMargin: 30
                right: parent.right; rightMargin: 30
                bottom: nav.top; bottomMargin: 14
            }
            contentHeight: pageCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: pageCol
                width: flick.width
                spacing: 12

                // ---- 1: the hall ----
                Page {
                    n: 0
                    title: "Welcome to the hall"
                    Para {
                        text: "Every table on the map is a vendor. Click one to walk over, and click a card on their table to "
                              + "pick it up and look at it closely. You have <b>" + Progress.checkBudget(guide.p) + " checks</b> this "
                              + "visit: each one is a close look at one thing about one card (the label, the print, the back...). "
                              + "Spend them where the money is."
                    }
                    Para {
                        text: "<b>You're not the only buyer.</b> Every check, question, offer or deal you make, the rest of the "
                              + "hall moves too: after a few, the crowd comes in and starts buying, the best deals first. Walking "
                              + "round and looking are free. An <b>early entry ticket</b> (" + Progress.format(Progress.SHOW_EARLY)
                              + ", only before you do anything) keeps the hall quiet a while longer."
                    }
                    Para {
                        text: "There are no price tags with a market price on them. What a card says is what the vendor is "
                              + "<i>asking</i>, and some ask a lot more than it's worth. Your notes (the Notes button) are the "
                              + "only price list you've got."
                    }
                    Para {
                        text: "Nobody tells you who's honest. When you leave, the recap shows what every card you bought "
                              + "was really worth, and who sold it to you. Many dealers are regulars who come back show after "
                              + "show, so keep track: in your notes, who oversold you and who was fair."
                    }
                }

                // ---- 2: buying ----
                Page {
                    n: 1
                    title: "Buying and haggling"
                    Para {
                        text: "<b>Buy</b> pays the asking price. Or <b>make an offer</b> first: 5%, 10% or 20% off. You get one "
                              + "offer per card, and the bigger it is, the likelier they say no. Honest dealers take a small "
                              + "offer more often than not; premium dealers budge less."
                    }
                    Para {
                        text: "<b>Ask about it</b> (free, once per card): where it's from, how it's been kept. Honest dealers "
                              + "mostly give a straight answer. Scammers mostly don't, and some lie very convincingly."
                    }
                    Para {
                        text: "Paying under three quarters of what a card is really worth counts as a <b>steal</b>. "
                              + "Steals are real, but so is the scammer's version of a steal."
                    }
                }

                // ---- 3: who's who ----
                Page {
                    n: 2
                    title: "Who's behind the tables"
                    Para {
                        text: "<b>Honest dealers</b> ask around market and stand behind their cards. <b>Bargain tables</b> (a kid "
                              + "clearing a collection, an estate sale) price by guesswork, often well under market. "
                              + "<b>Premium dealers</b> have the big cards and the big prices. The <b>vintage tables</b> sell "
                              + "only old cards: the 2005-06 One Piece CCG and Carddass Hyper Battle."
                    }
                    Para {
                        text: "<b>Scammers</b> look like everyone else. About half of what they sell is fake: counterfeit "
                              + "cards, slabs with forged labels, sealed packs that were opened, searched and glued shut again. "
                              + "Their prices look like a deal, their raw cards are always \"pack fresh\", and if you inspect "
                              + "too much they start pushing you to buy."
                    }
                    Para {
                        text: "A price that's too good to be true is the first warning. It isn't proof: bargain tables "
                              + "have real steals. That's what your checks are for. Watch the names, too: a scammer will "
                              + "happily set up as a regular's name with one letter off."
                    }
                }

                // ---- 4: a fake ----
                Page {
                    n: 3
                    title: "Spotting a fake"
                    Row {
                        visible: !!guide.example
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 40
                        Column {
                            spacing: 6
                            Slab {
                                width: 130
                                card: guide.example
                                time: guide.stage ? guide.stage.t : 0
                                hoverTilt: false
                            }
                            Text {
                                width: 130
                                horizontalAlignment: Text.AlignHCenter
                                text: "The real one"
                                color: "#7fd1b9"
                                font { pixelSize: 14; weight: Font.Black }
                            }
                        }
                        Column {
                            spacing: 6
                            Slab {
                                width: 130
                                card: guide.exampleFake
                                time: guide.stage ? guide.stage.t : 0
                                hoverTilt: false
                            }
                            Text {
                                width: 130
                                horizontalAlignment: Text.AlignHCenter
                                text: "A scammer's copy"
                                color: "#ff8a7a"
                                font { pixelSize: 14; weight: Font.Black }
                            }
                        }
                    }
                    Para {
                        text: "Two slabs of the same card. On the table they look alike, so you pick the fake one up and check:"
                    }
                    Para {
                        readonly property var c: guide.example || { grade: 10 }
                        text: "• <b>The label</b>: \"" + Progress.fakeGradeName(c) + "\". Close, not quite: a real "
                              + "one says " + Progress.gradeName(c) + ".<br>"
                              + "• <b>Look up the cert</b>: no record of that number, or it's registered to a different card.<br>"
                              + "• <b>The case</b>: glue marks along the seam, where it was opened and closed again."
                    }
                    Para {
                        text: "A crude fake gives itself away in three checks, a good one in only one, so one clean check "
                              + "proves nothing. Real cards have innocent quirks too: a faded label or a scuffed case is just "
                              + "wear. A misspelt grade or a cert that doesn't exist isn't. For raw cards, the loupe (a real "
                              + "card's print is a rosette of tiny dots), the light, the back, the feel of the stock and the "
                              + "edges each give fakes away."
                    }
                    Para {
                        text: "Caught one? <b>Report it to security.</b> They take the whole table down and you get a bounty: "
                              + "a quarter of what they were asking. Get it wrong and the card's real, and that vendor won't deal "
                              + "with you for the rest of the show, and word gets round. One report a table, so be sure."
                    }
                }

                // ---- 5: your binder ----
                Page {
                    n: 4
                    title: "Selling and trading your binder"
                    Para {
                        text: "At a table, open <b>Your binder</b>, pick some cards and <b>ask what they'd give</b>: one check "
                              + "for the lot. Each card gets two numbers: <b>cash</b> if you sell it, and <b>trade credit</b> "
                              + "towards one of their cards. Credit is worth more than cash, and if your cards come up short you "
                              + "add berries. If they come to more, honest vendors give you change at their cash rate."
                    }
                    Para {
                        text: "An offer doesn't tell you who's honest. Dealers keep a margin, bargain tables guess, and anyone "
                              + "can be overstocked on a set (they'll say so). Your own cards show no market price in there "
                              + "either, so know what they're worth before you go."
                    }
                    Para {
                        text: "<b>Scammers love a trade</b>, because they pay in fakes. A trade offer well over what your "
                              + "cards are worth is the warning sign. Check the card you'd get before you hand yours over, and "
                              + "know that they keep the change."
                    }
                    Para {
                        text: "<b>Regulars remember you.</b> Deal with the same one a few times and they keep an extra card "
                              + "under the table for you, take your small offers, and in time save the best thing they brought for you."
                    }
                    Para {
                        text: "Every vendor also keeps a few cards <b>under the table</b>: never for sale, only for a trade. "
                              + "You'll find them in your binder at their table."
                    }
                }

                // ---- 6: go ----
                Page {
                    n: 5
                    title: "Go have fun"
                    Para {
                        text: "Entry was " + Progress.format(Progress.SHOW_ENTRY) + " at the door. Take your time: walk the hall, check what matters, haggle, trade. When you're done, Esc leaves "
                              + "(it asks first). You can't come back until the next show, so spend what you meant to spend."
                    }
                    Para {
                        text: "Then the recap: what everything was really worth, which cards were fakes, and who you bought them from. "
                              + "Every show you go to, every deal you make and every scammer you catch builds your name at the "
                              + "shows: Familiar Face, Regular, Insider, Legend, each with its own perks (the Port's card shop tab). "
                              + "And on the 1st of every month, the Grand Line Expo: a bigger hall, dealers you'll only see there, "
                              + "an auction and a booth that tells you for sure if a card's real. "
                              + "Good luck out there."
                    }
                }
            }
        }

        Row {
            id: nav
            anchors { bottom: parent.bottom; bottomMargin: 22; left: parent.left; leftMargin: 30 }
            spacing: 10
            PillButton {
                visible: guide.page > 0
                text: "Back"
                accent: "#9aa0ad"
                onClicked: { guide.page--; flick.contentY = 0; }
            }
            PillButton {
                text: guide.page < guide.pages - 1 ? "Next" : "Let's go"
                accent: "#ffd56b"
                onClicked: {
                    if (guide.page < guide.pages - 1) { guide.page++; flick.contentY = 0; }
                    else guide.done();
                }
            }
        }
        Row {   // where you are
            anchors { verticalCenter: nav.verticalCenter; horizontalCenter: parent.horizontalCenter }
            spacing: 8
            Repeater {
                model: guide.pages
                Rectangle {
                    required property int index
                    width: 8; height: 8; radius: 4
                    color: index === guide.page ? "#ffd56b" : "#3a4258"
                }
            }
        }
        PillButton {
            anchors { verticalCenter: nav.verticalCenter; right: parent.right; rightMargin: 30 }
            visible: guide.page < guide.pages - 1
            text: "Skip the tour"
            fontSize: 12
            accent: "#7a8090"
            onClicked: guide.done()
        }
    }

    component Page: Column {
        property int n
        property string title
        visible: guide.page === n
        width: pageCol.width
        spacing: 12
        Text {
            text: parent.title
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
    }
    component Para: Text {
        width: pageCol.width
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        color: "#d8dbe4"
        font.pixelSize: 15
        lineHeight: 1.2
    }
}

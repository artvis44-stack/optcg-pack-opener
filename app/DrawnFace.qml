pragma ComponentBehavior: Bound
import QtQuick
import "tiers.js" as Tiers

// A card face drawn from its data, for a card with no picture: the vintage cards
// there's no photo of (2005-06 CCG style: an aged frame, the title on a parchment
// banner, Gold and Silver Rares lettered in gold or silver), and promos optcgapi
// has no image for. Card.qml puts the holo shader over it like any picture.
Item {
    id: face

    property var card
    readonly property bool vintage: Tiers.isVintage(card)
    // a sealed 2005-06 pack or box on a card show table (its card stands in for it)
    readonly property bool sealed: !!card && (card.tier === "SEALED_PACK" || card.tier === "SEALED_BOX")
    readonly property real u: width / 100
    // the lettering: gold and silver rares in metal, everything else in ink
    readonly property var metal: !card ? null
        : card.tier === "V_GOLD" || card.tier === "V_PROMO" ? ["#fff2b0", "#d9a520", "#8a5a10"]
        : card.tier === "V_SILVER" ? ["#ffffff", "#b9c3cc", "#5f6b76"] : null
    // "CH001-F" -> "CH001"
    readonly property string number: card ? String(card.id).replace(/-F$/, "") : ""
    // the character, from the name's start ("Monkey.D.Luffy (CS 2024 Event Pack)" -> "Monkey.D.Luffy")
    readonly property string title: card ? Tiers.displayName(card).replace(/\s*\(.*$/, "").replace(/\s*\[.*$/, "") : ""
    readonly property string subtitle: card ? (Tiers.displayName(card).match(/\(([^)]*)\)/) || ["", ""])[1] : ""

    // ---- the 2005-06 CCG: wood frame, parchment, a big name in the art window ----
    Rectangle {
        anchors.fill: parent
        visible: face.vintage
        radius: 3.5 * face.u
        gradient: Gradient {
            GradientStop { position: 0; color: "#5a3a22" }
            GradientStop { position: 0.5; color: "#3d2616" }
            GradientStop { position: 1; color: "#2a190e" }
        }
        // the title banner
        Rectangle {
            id: banner
            x: 6 * face.u; y: 4 * face.u
            width: parent.width - 12 * face.u
            height: 12 * face.u
            radius: 2 * face.u
            gradient: Gradient {
                GradientStop { position: 0; color: "#f3e2b8" }
                GradientStop { position: 1; color: "#d8bf86" }
            }
            Text {
                anchors.fill: parent
                anchors.margins: 1.5 * face.u
                text: face.card ? Tiers.displayName(face.card).replace(/\s*\((Tournament Winner|Jolly Roger Stamped|Bandai Exclusive|Promo)\)/, "") : ""
                color: "#2b1a0c"
                font { family: "serif"; pixelSize: 6.2 * face.u; weight: Font.Bold }
                fontSizeMode: Text.Fit
                minimumPixelSize: 6
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
        }
        // the art window: aged paper, the character's name where the picture would be
        Rectangle {
            id: art
            x: 8 * face.u
            anchors.top: banner.bottom; anchors.topMargin: 3 * face.u
            width: parent.width - 16 * face.u
            height: 70 * face.u
            border.color: "#1e1209"
            border.width: Math.max(1, 0.8 * face.u)
            gradient: Gradient {
                GradientStop { position: 0; color: "#efe0b4" }
                GradientStop { position: 0.7; color: "#dcc488" }
                GradientStop { position: 1; color: "#c9a96a" }
            }
            Text {   // a faint Jolly Roger behind the name
                anchors.centerIn: parent
                text: "☠"
                color: "#5a3a22"
                opacity: 0.13
                font.pixelSize: 48 * face.u
            }
            Text {
                id: who
                anchors.centerIn: parent
                width: parent.width - 8 * face.u
                text: face.card ? (face.card.character || face.title) : ""
                color: face.metal ? face.metal[1] : "#3a2312"
                style: Text.Outline
                styleColor: face.metal ? face.metal[2] : "#f3e2b8"
                font { family: "serif"; pixelSize: 15 * face.u; weight: Font.Black; italic: true }
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: who.bottom; topMargin: 2 * face.u }
                text: face.card ? face.card.origin || "" : ""
                color: "#5a3a22"
                font { family: "serif"; pixelSize: 4.2 * face.u; italic: true }
            }
            Rectangle {   // the yellowing at the edges
                anchors.fill: parent
                color: "transparent"
                border.color: "#40a0702a"
                border.width: 3 * face.u
            }
        }
        // the power plaque and the rules box (left blank: it's the look, not the game)
        Rectangle {
            id: plaque
            x: 8 * face.u
            anchors.top: art.bottom; anchors.topMargin: 3 * face.u
            width: 22 * face.u
            height: 34 * face.u
            radius: 1.5 * face.u
            color: "#e6d3a3"
            border.color: "#1e1209"
            border.width: Math.max(1, 0.6 * face.u)
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 3 * face.u }
                text: "POWER"
                color: "#3a2312"
                font { family: "serif"; pixelSize: 3.6 * face.u; weight: Font.Bold }
            }
            Text {
                anchors.centerIn: parent
                text: "★"
                color: face.metal ? face.metal[1] : "#5a3a22"
                font.pixelSize: 11 * face.u
            }
        }
        Rectangle {
            anchors { left: plaque.right; leftMargin: 3 * face.u; top: plaque.top; bottom: plaque.bottom }
            width: parent.width - 16 * face.u - plaque.width - 3 * face.u
            radius: 1.5 * face.u
            color: "#f0e4c4"
            border.color: "#1e1209"
            border.width: Math.max(1, 0.6 * face.u)
            Column {
                id: rules
                readonly property real u: face.u
                anchors { fill: parent; margins: 3.5 * face.u }
                spacing: 2.6 * face.u
                Repeater {
                    model: [1, 1, 1, 0.55]
                    Rectangle {
                        required property real modelData
                        width: rules.width * modelData
                        height: Math.max(1, 0.5 * rules.u)
                        color: "#cdb98a"
                    }
                }
            }
        }
        // the foot: rarity and number, like the real ones
        Text {
            anchors { left: parent.left; leftMargin: 7 * face.u; bottom: parent.bottom; bottomMargin: 3 * face.u }
            text: "© 2005 Eiichiro Oda/Shueisha, Toei Animation"
            color: "#d8c49a"
            opacity: 0.8
            font.pixelSize: 2.8 * face.u
        }
        Row {
            anchors { right: parent.right; rightMargin: 7 * face.u; bottom: parent.bottom; bottomMargin: 2.6 * face.u }
            spacing: 1.2 * face.u
            Rectangle {
                visible: !!face.metal
                width: tag.width + 2 * face.u
                height: tag.height
                radius: face.u
                color: face.metal ? face.metal[1] : "transparent"
                Text {
                    id: tag
                    anchors.centerIn: parent
                    text: !face.card ? "" : face.card.tier === "V_GOLD" ? "GR" : face.card.tier === "V_SILVER" ? "SR" : "PR"
                    color: "#2b1a0c"
                    font { pixelSize: 3.4 * face.u; weight: Font.Black }
                }
            }
            Text {
                text: face.number
                color: "#f3e2b8"
                font { pixelSize: 3.6 * face.u; weight: Font.Bold }
            }
        }
    }

    // ---- a modern promo with no picture: the card's colour, its name, a PROMO stamp ----
    Rectangle {
        id: promo
        anchors.fill: parent
        visible: !face.vintage && !face.sealed
        radius: 3.5 * face.u
        readonly property color tint: ({ Red: "#b8323a", Green: "#2f8a52", Blue: "#2f62b0", Purple: "#7a3fa8",
                                         Black: "#30343c", Yellow: "#c9a227" })[String(face.card && face.card.color || "").split(" ")[0]] || "#3a4a66"
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(promo.tint, 1.25) }
            GradientStop { position: 1; color: Qt.darker(promo.tint, 1.8) }
        }
        Text {
            anchors { top: parent.top; topMargin: 6 * face.u; horizontalCenter: parent.horizontalCenter }
            text: "PROMO"
            color: "#ffffff"
            opacity: 0.85
            font { pixelSize: 6 * face.u; weight: Font.Black; letterSpacing: 1.2 * face.u }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 12 * face.u
            spacing: 2 * face.u
            Text {
                width: parent.width
                text: face.title
                color: "#ffffff"
                font { pixelSize: 11 * face.u; weight: Font.Black; italic: true }
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
                style: Text.Raised
                styleColor: "#40000000"
            }
            Text {
                width: parent.width
                text: face.subtitle
                color: "#e8ecf4"
                font.pixelSize: 4.6 * face.u
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
        Text {
            anchors { right: parent.right; rightMargin: 6 * face.u; bottom: parent.bottom; bottomMargin: 4 * face.u }
            text: face.number
            color: "#ffffff"
            opacity: 0.8
            font { pixelSize: 4 * face.u; weight: Font.Bold }
        }
    }

    // ---- a sealed pack or box: the wrapper, crimped top and bottom (a box: its lid) ----
    Rectangle {
        anchors.fill: parent
        visible: face.sealed
        readonly property bool box: !!face.card && face.card.tier === "SEALED_BOX"
        radius: (box ? 1 : 2.5) * face.u
        gradient: Gradient {
            GradientStop { position: 0; color: "#f08a24" }
            GradientStop { position: 0.45; color: "#d4421c" }
            GradientStop { position: 1; color: "#6e1a12" }
        }
        Repeater {   // the crimps
            model: parent.box ? 0 : 2
            Row {
                required property int index
                y: index ? parent.height - 6 * face.u : 0
                Repeater {
                    model: 25
                    Rectangle {
                        required property int index
                        width: 4 * face.u; height: 6 * face.u; opacity: 0.85
                        color: index % 2 ? "#b8b8c0" : "#e8e8ee"
                    }
                }
            }
        }
        Rectangle {   // a box's lid
            visible: parent.box
            width: parent.width
            height: 14 * face.u
            color: "#2a190e"
            Text {
                anchors.centerIn: parent
                text: "BOOSTER BOX  ·  12 PACKS"
                color: "#ffd56b"
                font { pixelSize: 5 * face.u; weight: Font.Black; letterSpacing: 0.5 * face.u }
            }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 12 * face.u
            spacing: 2 * face.u
            Text {
                width: parent.width
                text: "ONE PIECE"
                color: "#fff2b0"
                style: Text.Outline
                styleColor: "#5a1a0a"
                font { family: "serif"; pixelSize: 16 * face.u; weight: Font.Black; italic: true }
                fontSizeMode: Text.HorizontalFit
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "COLLECTIBLE CARD GAME"
                color: "#ffffff"
                font { pixelSize: 4.6 * face.u; weight: Font.Black; letterSpacing: 0.6 * face.u }
                horizontalAlignment: Text.AlignHCenter
            }
            Item { width: 1; height: 8 * face.u }
            Text {
                width: parent.width
                text: face.card ? face.card.origin || "" : ""
                color: "#ffe9c0"
                font { family: "serif"; pixelSize: 7 * face.u; weight: Font.Bold; italic: true }
                fontSizeMode: Text.HorizontalFit
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: face.card && face.card.tier === "SEALED_BOX" ? "12 booster packs" : "10 game cards"
                color: "#ffe9c0"
                font.pixelSize: 4.4 * face.u
                horizontalAlignment: Text.AlignHCenter
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 * face.u }
            text: "BANDAI  ·  SHONEN JUMP"
            color: "#ffd0a0"
            opacity: 0.8
            font { pixelSize: 3.4 * face.u; weight: Font.Bold; letterSpacing: 0.4 * face.u }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "tiers.js" as Tiers
import "progress.js" as Progress

// The card show (K, on show days). You walk in to a floor plan of the hall: every
// vendor's stall (Progress.makeShowStock), honest or not, looks alike from the aisle.
// Click one to walk over: its table, with slabs on the pegboard, raw cards in top
// loaders on the cloth and sealed product stacked at the end, a price tag on each.
// No market prices anywhere while you're here: you have to know what things are worth.
// Click something to pick it up: check it (the loupe, the light, the back... a few
// checks a visit, Progress.checkListing), ask the vendor about it, haggle once, buy.
// You find out who was who when you leave (Esc), and the recap shows what you really got.
// With Nico Robin aboard, her notes (vintage prices) come along; she won't tell you what a
// particular listing is worth, though: that's still on you.
Item {
    id: show

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var s: Progress.showState(p)
    readonly property var stock: s.stock || []
    readonly property var recap: stage ? stage.showRecap : null
    property string stallId: ""          // the stall you're at ("": the hall map)
    property string inspected: ""        // the listing in your hands
    property bool confirmLeave: false
    property var visited: ({})           // stalls you've walked up to this visit
    property bool notes: false           // Robin's notes, open
    readonly property bool robin: Progress.hasCrew(p, "robin")

    readonly property var stall: stallId ? stock.filter(t => t.id === stallId)[0] || null : null
    readonly property var listing: inspected ? Progress.showListing(p, inspected) : null
    readonly property var vendor: inspected ? Progress.showVendor(p, inspected) : null
    readonly property int checksLeft: Math.max(0, Progress.SHOW_CHECK_BUDGET - (s.looks || 0))

    function back() {
        if (recap) stage.closeShow();
        else if (notes) notes = false;
        else if (inspected) inspected = "";
        else if (stallId) stallId = "";
        else if (!confirmLeave) confirmLeave = true;
        else leave();
    }

    function leave() {
        confirmLeave = false;
        inspected = "";
        stallId = "";
        stage.leaveShow();
    }

    function walkTo(id) {
        stallId = id;
        confirmLeave = false;
        var v = Object.assign({}, visited);
        v[id] = true;
        visited = v;
    }

    onVisibleChanged: if (visible) { inspected = ""; stallId = ""; confirmLeave = false; notes = false; }

    // a listing as a card the Card / Slab components draw (a fake looks a little off: how
    // much, and which of a slab's checks show it, come with it)
    function cardOf(x) {
        if (!x || !stage) return null;
        var c = x.sealed ? Object.assign({}, x.card) : stage.localCard(Object.assign({ key: x.key }, x.card));
        return Object.assign(c, { grade: x.grade, fake: x.fake, fakeLook: x.fakeLook, tells: x.tells || [] });
    }

    function priceText(x) {
        var now = Progress.showPrice(p, x);
        return now !== x.ask ? Progress.format(now) + "  (was " + Progress.format(x.ask) + ")" : Progress.format(x.ask);
    }

    // where a card's from: its set, or for the show-only ones what they are ("One Piece CCG · The Quest Begins")
    function fromText(c) {
        return c.set === "VINTAGE" ? "One Piece CCG" + (c.origin ? " · " + c.origin : "")
             : c.set === "HYPERBATTLE" ? "Carddass Hyper Battle" + (c.origin ? " · " + c.origin : "")
             : c.set === "PROMO" ? "Promo" : c.set;
    }

    function bought(id) { return !!(s.bought || {})[id]; }

    // a stall's look: its tablecloth, from its name (the same every visit)
    readonly property var cloths: ["#7a2230", "#24507a", "#2f6b46", "#6b4a8a", "#8a5a24", "#2c6a6e", "#7a6a22", "#4a4f5c", "#8a3a5e"]
    function clothOf(t) {
        if (t.vintage === "hb") return "#1f3f7a";   // Carddass blue
        if (t.vintage) return "#5a3a22";
        var h = 0;
        for (var i = 0; i < t.name.length; i++) h = (h * 31 + t.name.charCodeAt(i)) % 9973;
        return cloths[h % cloths.length];
    }

    function countText(t) {
        var raw = t.listings.filter(x => !x.grade && !x.sealed).length, slabs = t.listings.filter(x => x.grade).length;
        var sealed = t.listings.filter(x => x.sealed).length, out = [];
        if (raw) out.push(raw + " card" + (raw > 1 ? "s" : ""));
        if (slabs) out.push(slabs + " slab" + (slabs > 1 ? "s" : ""));
        if (sealed) out.push(sealed + " sealed");
        return out.join(" · ");
    }

    readonly property var kindName: ({ honest: "an honest dealer", bargain: "a bargain table", premium: "a premium dealer",
                                       vintage: "a vintage specialist", carddass: "a Carddass specialist", scammer: "a SCAMMER" })
    readonly property var kindColor: ({ honest: "#7fd1b9", bargain: "#ffd56b", premium: "#c8a0ff", vintage: "#e8c48a",
                                        carddass: "#9ad8ff", scammer: "#ff8a7a" })
    readonly property var gradeName: ({ crude: "a crude fake", decent: "a decent fake", good: "a good fake" })

    // ---- the hall: a warm ceiling, rows of lights ----------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#1c1424" }
            GradientStop { position: 0.35; color: "#120c18" }
            GradientStop { position: 1; color: "#08060c" }
        }
    }
    Repeater {   // pools of light from the ceiling
        model: 6
        Shape {
            id: light
            required property int index
            x: show.width * (index / 6) - width * 0.1
            y: -height * 0.25
            width: show.width * 0.3
            height: show.height * 0.85
            opacity: 0.55
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: light.width / 2; centerY: 0
                    focalX: light.width / 2; focalY: 0
                    centerRadius: light.width * 0.75
                    GradientStop { position: 0; color: "#40ffd9a0" }
                    GradientStop { position: 1; color: "#00ffd9a0" }
                }
                startX: 0; startY: 0
                PathLine { x: light.width; y: 0 }
                PathLine { x: light.width; y: light.height }
                PathLine { x: 0; y: light.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    component Note: Text {
        color: "#9aa0ad"
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    // a little white price tag, a touch crooked
    component PriceTag: Rectangle {
        id: tag
        property string text
        property bool sold: false
        width: tagText.implicitWidth + 12
        height: 20
        radius: 3
        color: sold ? "#c8433a" : "#f4f1ea"
        rotation: -3
        Text {
            id: tagText
            anchors.centerIn: parent
            text: tag.sold ? "SOLD" : tag.text
            color: tag.sold ? "white" : "#1a1a1a"
            font { pixelSize: 12; weight: Font.Black }
        }
    }

    // ---- header -----------------------------------------------------------------------
    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: 52   // under the wallet bar
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: show.stall && !show.recap ? show.stall.name : "The Card Show"
            color: "#ff9ad5"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Progress.format(show.p.berries) + "   ·   checks left: " + show.checksLeft + " / " + Progress.SHOW_CHECK_BUDGET
                  + "   ·   bought " + Object.keys(show.s.bought || {}).length
            color: "#fff6e0"
            font { pixelSize: 16; weight: Font.Bold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !show.recap
            text: show.stall ? "\"" + show.stall.blurb + "\""
                : "No prices to look up in here: know your market. Some vendors are honest, some aren't."
            color: show.stall ? "#e8d8b8" : "#9aa0ad"
            font { pixelSize: 13; italic: !!show.stall }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            visible: !show.recap
            PillButton {
                visible: !!show.stall
                text: "‹  Back to the hall"
                fontSize: 13
                accent: "#ffd56b"
                onClicked: show.stallId = ""
            }
            PillButton {
                visible: show.robin
                text: "Robin's notes"
                fontSize: 13
                accent: "#c8a0ff"
                onClicked: show.notes = true
            }
            PillButton {
                text: show.confirmLeave ? "Leave? You can't come back until the next show. Yes, leave" : "Leave the show"
                fontSize: 13
                accent: show.confirmLeave ? "#ff8a7a" : "#9aa0ad"
                onClicked: show.confirmLeave ? show.leave() : show.confirmLeave = true
            }
        }
    }

    // ---- the hall map: every stall, from above --------------------------------------------
    Item {
        id: map
        visible: !show.recap && !show.stall
        anchors {
            top: header.bottom; topMargin: 18
            bottom: parent.bottom; bottomMargin: 40
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(show.width * 0.94, 1300)
        readonly property int cols: 5
        readonly property int rows: Math.ceil(show.stock.length / cols)
        readonly property real stallW: (width - 60 - (cols - 1) * 26) / cols
        readonly property real stallH: Math.min(210, (height - 90 - (rows - 1) * 44) / Math.max(1, rows))

        Rectangle {   // the floor: carpet, with the aisles between the rows
            anchors.fill: parent
            radius: 14
            color: "#1d1826"
            border.color: "#3a2c4a"
            border.width: 2
            clip: true
            Grid {   // the carpet's pattern
                anchors.fill: parent
                columns: Math.ceil(width / 40)
                opacity: 0.18
                Repeater {
                    model: Math.ceil(map.width / 40) * Math.ceil(map.height / 40)
                    Rectangle {
                        required property int index
                        width: 40; height: 40
                        color: "transparent"
                        border.color: index % 2 ? "#4a3a5a" : "#3a2c4a"
                        border.width: 1
                    }
                }
            }
            Text {   // the entrance
                anchors { bottom: parent.bottom; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                text: "▲  Entrance  ·  you are here"
                color: "#ffd56b"
                font { pixelSize: 13; weight: Font.Bold; letterSpacing: 1 }
            }
        }

        Repeater {
            model: show.stock
            Item {
                id: booth
                required property var modelData
                required property int index
                readonly property int col: index % map.cols
                readonly property int row: Math.floor(index / map.cols)
                readonly property bool been: !!show.visited[modelData.id]
                readonly property int boughtHere: modelData.listings.filter(x => show.bought(x.id)).length
                readonly property color cloth: show.clothOf(modelData)
                x: 30 + col * (map.stallW + 26)
                y: 28 + row * (map.stallH + 44)
                width: map.stallW
                height: map.stallH
                scale: boothMouse.containsMouse ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }

                Rectangle {   // the shadow on the carpet
                    anchors.fill: table
                    anchors.topMargin: 8
                    anchors.leftMargin: 4
                    radius: 8
                    color: "#000000"
                    opacity: 0.4
                }
                Rectangle {   // the table, cloth draped over it
                    id: table
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * 0.76
                    radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(booth.cloth, 1.25) }
                        GradientStop { position: 0.75; color: booth.cloth }
                        GradientStop { position: 1; color: Qt.darker(booth.cloth, 1.6) }
                    }
                    border.color: boothMouse.containsMouse ? "#ffd56b" : Qt.darker(booth.cloth, 1.8)
                    border.width: boothMouse.containsMouse ? 2 : 1
                    Row {   // what's on it, from the aisle: a peek at the cards, as big as the table allows
                        id: peeks
                        readonly property real h: Math.max(30, table.height - 30)
                        anchors { left: parent.left; leftMargin: 8; top: parent.top; topMargin: 6 }
                        spacing: 4
                        Repeater {
                            model: booth.modelData.listings.slice(0, Math.max(1, Math.floor((map.stallW - 16) / (peeks.h * 0.716 + 4))))
                            Rectangle {
                                id: peek
                                required property var modelData
                                width: modelData.sealed ? peeks.h * 0.86 : peeks.h * 0.716
                                height: modelData.sealed && modelData.sealed.kind === "box" ? peeks.h * 0.74 : peeks.h
                                radius: 2
                                color: modelData.sealed ? "#d4421c" : modelData.grade ? "#d8dde4" : "#1a1a1a"
                                border.color: modelData.grade ? "#ffffff" : "#00000000"
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: peek.modelData.grade ? 3 : 1
                                    anchors.topMargin: peek.modelData.grade ? peeks.h * 0.2 : 1
                                    visible: !peek.modelData.sealed
                                    source: !peek.modelData.sealed && show.stage
                                            ? "file://" + show.stage.localCard(Object.assign({ key: peek.modelData.key }, peek.modelData.card)).image : ""
                                    sourceSize.width: 120
                                    asynchronous: true
                                    fillMode: Image.Stretch
                                }
                            }
                        }
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                        text: show.countText(booth.modelData)
                        color: "#f4ead8"
                        font { pixelSize: 11; weight: Font.Bold }
                    }
                }
                Rectangle {   // the stall's sign, on its pole
                    width: 3; height: parent.height * 0.24 - 6
                    x: parent.width / 2 - 1.5
                    y: 6
                    color: "#2a2230"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: Math.min(parent.width, signText.implicitWidth + 22)
                    height: 28
                    radius: 5
                    color: "#f4ead8"
                    border.color: "#3a2412"
                    border.width: 2
                    Text {
                        id: signText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, booth.width - 22)
                        elide: Text.ElideRight
                        text: booth.modelData.name
                        color: "#2b1a0c"
                        font { pixelSize: 13; weight: Font.Black }
                    }
                }
                Rectangle {   // you've been here / bought here
                    visible: booth.been || booth.boughtHere > 0
                    anchors { right: parent.right; rightMargin: 6; top: table.top; topMargin: -10 }
                    width: badge.implicitWidth + 12
                    height: 20
                    radius: 10
                    color: booth.boughtHere ? "#2f6b46" : "#2a2a3a"
                    border.color: booth.boughtHere ? "#7fd1b9" : "#5a5a6a"
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: booth.boughtHere ? "bought " + booth.boughtHere : "looked"
                        color: "#e8e8ee"
                        font { pixelSize: 11; weight: Font.Bold }
                    }
                }
                MouseArea {
                    id: boothMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: show.walkTo(booth.modelData.id)
                }
            }
        }
    }

    // ---- a stall, up close: the vendor's table, from the aisle (StallTable) -----------------
    Item {
        id: stallView
        visible: !show.recap && !!show.stall
        anchors {
            top: header.bottom; topMargin: 20
            bottom: parent.bottom; bottomMargin: 36
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(show.width * 0.96, 1400)
        readonly property string mood: show.stall ? Progress.vendorMood(show.p, show.stall.id) : ""

        StallTable {
            anchors.fill: parent
            owner: show
            vendor: show.stall
            cloth: show.stall ? show.clothOf(show.stall) : "#333"
            onPicked: id => show.inspected = id
        }

        Rectangle {   // the vendor, behind the table, has something to say
            id: bubble
            visible: text.length > 0
            readonly property string text: stallView.mood
            anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 4 }
            width: Math.min(420, bubbleText.implicitWidth + 28)
            height: bubbleText.implicitHeight + 16
            radius: 12
            color: "#f4ead8"
            z: 3
            Text {
                id: bubbleText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 392)
                wrapMode: Text.WordWrap
                text: bubble.text
                color: "#2b1a0c"
                font { pixelSize: 13; italic: true; weight: Font.Bold }
            }
        }
    }

    // ---- in your hands: check it, ask about it, haggle, buy ----------------------------------
    Rectangle {
        anchors.fill: parent
        visible: !!show.listing && !show.recap
        color: "#ee05070d"
        MouseArea {
            anchors.fill: parent
            onClicked: show.inspected = ""
        }
        Row {
            anchors.centerIn: parent
            spacing: 40
            Loader {
                anchors.verticalCenter: parent.verticalCenter
                readonly property var c: show.cardOf(show.listing)
                sourceComponent: show.listing && show.listing.grade ? bigSlab : bigCard
                Component {
                    id: bigCard
                    Card { width: Math.min(340, show.height * 0.6 * 0.716); card: parent.c; faceUp: true; hoverTilt: true
                           time: show.stage ? show.stage.t : 0 }
                }
                Component {
                    id: bigSlab
                    Slab { width: Math.min(320, show.height * 0.55 * 0.716); card: parent.c; time: show.stage ? show.stage.t : 0 }
                }
            }
            Flickable {
                anchors.verticalCenter: parent.verticalCenter
                width: 480
                height: Math.min(show.height - 120, info.height)
                contentHeight: info.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                MouseArea { anchors.fill: parent }   // clicks on the panel don't put it down
                Column {
                    id: info
                    width: parent.width
                    spacing: 10
                    readonly property var lst: show.listing
                    readonly property bool sold: !!lst && show.bought(lst.id)
                    readonly property var haggled: lst ? (show.s.haggled || {})[lst.id] : null
                    readonly property var seen: lst ? Progress.showSeen(show.p, lst.id) : ({})
                    readonly property bool asked: !!lst && !!(show.s.asked || {})[lst.id]
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: info.lst ? Tiers.displayName(info.lst.card) : ""
                        color: "#fff6e0"
                        font { pixelSize: 24; weight: Font.Black; italic: true }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: !info.lst ? "" : (info.lst.card.set === "PROMO" ? "" : show.fromText(info.lst.card) + "  ·  ")   // a promo's tier says it
                                                 + (info.lst.sealed ? "" : info.lst.card.id + "  ·  ") + Tiers.tierOf(info.lst.card).label
                        color: info.lst ? Tiers.tierOf(info.lst.card).color : "white"
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: !info.lst ? "" : info.lst.grade ? "In a slab, graded " + info.lst.grade + "."
                              : info.lst.sealed ? ({ box: "A sealed box of 12 packs", pack: "A sealed pack of 10 cards",
                                                     vpack: "An unopened Carddass vending pack: 4 cards",
                                                     grandbox: "A sealed Grand Box: a ready-made deck",
                                                     jfpack: "An unopened Jump Festa limited pack" })[info.lst.sealed.kind] || "Sealed"
                                                  + ". The vendor says: \"" + info.lst.claim + "\""
                              : "Raw. The vendor says: \"" + info.lst.claim + "\""
                        color: "#c8ccd6"
                        font.pixelSize: 14
                    }
                    Text {
                        text: info.lst ? (info.sold ? "Bought for " + Progress.format(show.s.bought[info.lst.id].price) : "Asking " + show.priceText(info.lst)) : ""
                        color: "#ffd56b"
                        font { pixelSize: 22; weight: Font.Black }
                    }

                    // the checks: each one a look at one thing about it
                    Text {
                        text: "Check it  ·  " + show.checksLeft + " check" + (show.checksLeft === 1 ? "" : "s") + " left this visit"
                        color: "#c8a0ff"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: info.lst && info.lst.checks ? Progress.showChecks(info.lst) : []
                            PillButton {
                                id: checkButton
                                required property var modelData
                                readonly property bool done: info.seen[modelData.id] !== undefined
                                text: modelData.label
                                fontSize: 12
                                accent: done ? "#7a7090" : "#c8a0ff"
                                enabledLook: !done && show.checksLeft > 0
                                onClicked: {
                                    if (done || !show.checksLeft) return;
                                    var id = show.inspected, check = checkButton.modelData.id;
                                    show.stage.prog(q => { Progress.checkListing(q, id, check, Date.now()); return []; });
                                }
                            }
                        }
                    }
                    Repeater {   // what you've seen
                        model: info.lst && info.lst.checks ? Progress.showChecks(info.lst).filter(c => info.seen[c.id] !== undefined) : []
                        Text {
                            required property var modelData
                            width: info.width
                            wrapMode: Text.WordWrap
                            text: "<b>" + modelData.label + ":</b> " + info.seen[modelData.id]
                            textFormat: Text.StyledText
                            color: "#e6d6ff"
                            font.pixelSize: 13
                        }
                    }
                    Note {
                        width: parent.width
                        visible: !!info.lst && !info.sold && !Object.keys(info.seen).length
                        text: info.lst && info.lst.sealed ? "Bought, it goes with your sealed products in the port, to hold or open a pack at a time. Resealed packs turn up at shows."
                              : "A real foil catches the light as you tilt it. A fake can fool one check and fail another; a real card can have a harmless quirk."
                    }

                    // the vendor
                    Row {
                        spacing: 10
                        PillButton {
                            text: info.asked ? "Asked" : "Ask the vendor about it"
                            fontSize: 12
                            accent: "#ffd56b"
                            enabledLook: !info.asked
                            onClicked: {
                                if (info.asked) return;
                                var id = show.inspected;
                                show.stage.prog(q => { Progress.askVendor(q, id, Date.now()); return []; });
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: show.vendor ? "at " + show.vendor.name : ""
                            color: "#9aa0ad"
                            font.pixelSize: 13
                        }
                    }
                    Text {
                        width: parent.width
                        visible: info.asked
                        wrapMode: Text.WordWrap
                        text: info.lst ? info.lst.talk || "" : ""
                        color: "#ffe9b0"
                        font { pixelSize: 14; italic: true }
                    }

                    // haggle and buy
                    Row {
                        spacing: 8
                        visible: !info.sold && !info.haggled
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Make an offer (once):"
                            color: "#c8ccd6"
                            font.pixelSize: 13
                        }
                        Repeater {
                            model: Progress.SHOW_HAGGLE
                            PillButton {
                                id: offer
                                required property real modelData
                                text: Math.round(modelData * 100) + "% off"
                                fontSize: 12
                                accent: "#7fd1b9"
                                onClicked: {
                                    var id = show.inspected, pct = offer.modelData, ok = null;
                                    show.stage.prog(q => { ok = Progress.haggle(q, id, pct, Date.now()); return []; });
                                    if (ok !== null) show.stage.sfx(ok ? "coin" : "flip");
                                }
                            }
                        }
                    }
                    Text {
                        visible: !!info.haggled && !info.sold
                        text: info.haggled ? (info.haggled.ok ? "\"Deal.\" Your offer of " + Math.round(info.haggled.pct * 100) + "% off was taken."
                                                              : "\"No, that's my price.\" Your offer was turned down.") : ""
                        color: info.haggled && info.haggled.ok ? "#7fd1b9" : "#9aa0ad"
                        font.pixelSize: 13
                    }
                    Row {
                        spacing: 10
                        PillButton {
                            visible: !info.sold
                            text: "Buy  " + (info.lst ? Progress.format(Progress.showPrice(show.p, info.lst)) : "")
                            enabledLook: !!info.lst && show.p.berries >= Progress.showPrice(show.p, info.lst)
                            onClicked: show.stage.buyAtShow(show.inspected)
                        }
                        PillButton {
                            text: "Put it down"
                            accent: "#9aa0ad"
                            onClicked: show.inspected = ""
                        }
                    }
                }
            }
        }
    }

    // ---- the recap: home again ------------------------------------------------------------
    Flickable {
        visible: !!show.recap
        anchors {
            top: header.bottom; topMargin: 4
            bottom: parent.bottom; bottomMargin: 36
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(show.width * 0.9, 900)
        contentHeight: recapCol.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: recapCol
            width: parent.width
            spacing: 10
            readonly property var r: show.recap
            Text {
                text: "Home from the show"
                color: "#ffd56b"
                font { pixelSize: 22; weight: Font.Black }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !!recapCol.r
                readonly property int net: recapCol.r ? recapCol.r.worth - recapCol.r.paid : 0
                text: !recapCol.r ? "" : !recapCol.r.items.length ? "You didn't buy anything this time."
                      : "You paid " + Progress.format(recapCol.r.paid) + " for things worth " + Progress.format(recapCol.r.worth)
                        + " at market:  " + (net >= 0 ? "+" : "−") + Progress.format(Math.abs(net)).slice(1) + " ฿"
                        + (recapCol.r.fakes ? "   ·   " + recapCol.r.fakes + " fake" + (recapCol.r.fakes > 1 ? "s" : "") + " (in the vault)" : "")
                        + (recapCol.r.steals ? "   ·   " + recapCol.r.steals + " steal" + (recapCol.r.steals > 1 ? "s" : "") : "")
                color: net >= 0 ? "#7fd1b9" : "#ff8a7a"
                font { pixelSize: 16; weight: Font.Bold }
            }
            Repeater {
                model: recapCol.r ? recapCol.r.items : []
                Rectangle {
                    id: line
                    required property var modelData
                    readonly property var l: modelData.listing
                    width: recapCol.width
                    height: 46
                    radius: 8
                    color: "#161020"
                    border.color: l.fake ? "#ff8a7a" : "#3a2c4a"
                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.5
                        elide: Text.ElideRight
                        text: Tiers.displayName(line.l.card) + "  ·  " + show.fromText(line.l.card)
                              + (line.l.grade ? "  ·  graded " + line.l.grade : "")
                              + "  ·  from " + (line.modelData.vendor ? line.modelData.vendor.name : "")
                        color: "#e8e8ee"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "paid " + Progress.format(line.modelData.paid) + "   ·   "
                              + (line.l.fake ? (line.l.sealed ? "RESEALED: " : "FAKE: ") + (show.gradeName[line.l.fakeGrade] || "a fake")
                                 : "worth " + Progress.format(line.l.value)
                                   + (!line.l.grade && line.l.cond && line.l.claim === Progress.SHOW_CLAIM.pristine
                                      && line.l.cond !== "pristine" ? "  (really " + Progress.CONDITION[line.l.cond].name + ")" : ""))
                        color: line.l.fake ? "#ff8a7a" : line.modelData.paid <= line.l.value ? "#7fd1b9" : "#ffb347"
                        font { pixelSize: 14; weight: Font.Bold }
                    }
                }
            }
            Text {
                text: "Who was who"
                color: "#ffd56b"
                font { pixelSize: 18; weight: Font.Black }
                topPadding: 8
            }
            Repeater {
                model: recapCol.r ? recapCol.r.vendors : []
                Text {
                    required property var modelData
                    text: modelData.name + ": " + show.kindName[modelData.kind]
                    color: show.kindColor[modelData.kind]
                    font { pixelSize: 14; weight: Font.Bold }
                }
            }
            PillButton {
                text: "Done"
                onClicked: show.stage.closeShow()
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
        text: show.recap ? "Esc or Done: back"
              : show.inspected ? "Move the mouse to tilt it   ·   click outside or Esc: put it down"
              : show.stall ? "Click something to pick it up   ·   Esc: back to the hall"
              : "Click a stall to walk over   ·   Esc: leave the show"
        color: "#9aa0ad"
        font.pixelSize: 14
    }

    RobinNotes {   // Robin's notes, over everything
        anchors.fill: parent
        visible: show.notes
        stage: show.stage
        onClose: show.notes = false
    }
}

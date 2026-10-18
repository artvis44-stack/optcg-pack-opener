import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The desktop companion: a status bar (berries, free packs, streak, focus
// sessions) that's always on the desktop, and -- once you pick one with D -- a
// card from your collection above it, in a
// graded-style acrylic slab (label with name, set, rarity, pull date) above
// an info plate (copies owned, set completion, TCGplayer market price).
// Hover to tilt the slab (the foil only animates then, so it costs nothing
// while you work), drag to move, scroll to resize, double-click to inspect it
// big in the overlay, right-click to put it away.
//
// The card and its placement live in showcase.json, written by the pack
// opener (D on a card) and by this item; it's re-read every couple of seconds,
// so picking another card swaps it live. Prices come from optcgapi.com about
// once a day and are kept in prices.json, so the plate can show the change.
// The companion also runs the progression clock (progress.js): every minute
// it counts free packs, the daily streak and -- while you're at the computer --
// passive income, and it times focus sessions, with desktop notifications.
// Shared by the Linux and macOS hosts:
//   moveInside: true   the host gives this the whole screen (clicks only land
//                      on `frame`, see frameRect) and dragging moves the widget
//                      inside it -- no window moves, so it tracks the mouse 1:1
//   moveInside: false  the window is just the widget; dragging asks the host to
//                      move the window natively (systemMoveRequested), and the
//                      host reports where it ended up via placeAt()
Item {
    id: show

    required property QtObject host
    property bool moveInside: true
    readonly property string home: host.env("HOME")
    readonly property string dataDir: (host.env("XDG_DATA_HOME") || home + "/.local/share") + "/optcg"
    readonly property string cacheRoot: (host.env("XDG_CACHE_HOME") || home + "/.cache") + "/optcg"
    readonly property string path: dataDir + "/showcase.json"

    property var card: null
    property real cardWidth: 260
    property real fromRight: 60     // distance from the screen's right edge
    property real fromBottom: 80    // ...and bottom edge
    property string lastText: ""
    property bool dragging: false

    // ---- layout: everything scales with the card ------------------------------
    readonly property real u: cardWidth / 100          // 1% of the card's width
    readonly property real slabPad: 7 * u
    readonly property real labelH: 30 * u
    readonly property real slabWidth: cardWidth + 2 * slabPad
    readonly property real slabHeight: slabPad + labelH + 0.6 * slabPad + cardWidth / 0.716 + slabPad
    readonly property real plateGap: 5 * u
    readonly property real plateHeight: 33 * u
    readonly property real pad: 8 * u                  // room for the shadow and the tilt
    readonly property real barGap: 4 * u
    readonly property real barHeight: Math.max(30, 13 * u)
    readonly property real frameWidth: slabWidth + 2 * pad
    readonly property real frameHeight: 2 * pad + barHeight + (card ? slabHeight + plateGap + plateHeight + barGap : 0)
    readonly property rect frameRect: Qt.rect(frame.x, frame.y, frame.width, frame.height)

    signal emptied()                // nothing to show: the host can quit
    signal systemMoveRequested()    // moveInside: false -- start a native window drag

    implicitWidth: frameWidth
    implicitHeight: frameHeight

    // ---- what the plate and label show -------------------------------------------
    readonly property var tier: Tiers.tierOf(card)
    readonly property string setId: !card ? "" : card.set || ((card.image || "").match(/optcg\/([^/]+)\//) || [])[1] || ""
    readonly property string key: card ? setId + ":" + card.image.split("/").pop() : ""
    property var sets: ({})
    property int setTotal: 0
    property var owned: null          // this card's collection entry { count, first }
    property int setOwned: 0
    property string collectionText: ""
    property var priceHistory: []     // [{ d: "2026-10-18", p: 84.2 }, ...]

    readonly property var shortTier: ({
        C: "C", UC: "UC", R: "R", L: "L", SR: "SR", SEC: "SEC", AA: "AA", L_AA: "L·AA",
        SEC_AA: "SEC·AA", SP: "SP", TR: "TR", MANGA: "MANGA", SUPER: "SUPER", SUPER_L: "SUPER",
        SP_GOLD: "SP", SIGNED: "SIGN", PANDA: "PANDA", TOPPER: "TOP", FOIL: "FOIL", TEX: "TEX",
        DON: "DON!!", DON_GOLD: "DON!!", DON_SP: "DON!!"
    })

    function load() {
        var text = host.readText(path);
        if (text === lastText) return;
        lastText = text;
        var s = null;
        try { s = text ? JSON.parse(text) : null; } catch (e) {}
        if (!s || !s.card) {
            card = null;
            emptied();
            return;
        }
        var changed = !card || card.image !== s.card.image;
        card = s.card;
        if (s.width) cardWidth = s.width;
        if (s.right !== undefined) fromRight = s.right;
        if (s.bottom !== undefined) fromBottom = s.bottom;
        if (changed) refreshCardInfo();
    }

    function save() {
        lastText = JSON.stringify({ card: card, width: cardWidth, right: fromRight, bottom: fromBottom });
        host.writeText(path, lastText);
    }

    // moveInside: false -- the host's window was moved; remember where
    function placeAt(right, bottom) {
        fromRight = Math.max(0, right);
        fromBottom = Math.max(0, bottom);
        save();
    }

    function refreshCardInfo() {
        // how many different cards the set has (same keying as the collection)
        setTotal = 0;
        try {
            var db = JSON.parse(host.readText(cacheRoot + "/" + setId + "/cards.json") || "{}");
            var seen = {};
            (db.cards || []).forEach(c => seen[c.image.split("/").pop()] = true);
            setTotal = Object.keys(seen).length;
        } catch (e) {}
        collectionText = "";
        loadCollection();
        loadPrices();
        refreshPrice();
    }

    function loadCollection() {
        var text = host.readText(dataDir + "/collection.json");
        if (text === collectionText || !card) return;
        collectionText = text;
        try {
            var cards = JSON.parse(text || "{}").cards || {};
            owned = cards[key] || null;
            setOwned = Object.keys(cards).filter(k => k.indexOf(setId + ":") === 0).length;
        } catch (e) {}
    }

    // ---- market price (optcgapi.com carries TCGplayer market prices) ------------------
    function today() {
        return new Date().toISOString().slice(0, 10);
    }

    function loadPrices() {
        try {
            priceHistory = JSON.parse(host.readText(dataDir + "/prices.json") || "{}")[key] || [];
        } catch (e) {
            priceHistory = [];
        }
    }

    function recordPrice(p) {
        var all = {};
        try { all = JSON.parse(host.readText(dataDir + "/prices.json") || "{}"); } catch (e) {}
        var hist = (all[key] || []).filter(h => h.d !== today());
        hist.push({ d: today(), p: p });
        all[key] = hist.slice(-60);
        host.writeText(dataDir + "/prices.json", JSON.stringify(all));
        priceHistory = all[key];
    }

    function refreshPrice() {
        if (!card || card.type === "DON!!" || !setId) return;   // DON!! cards aren't priced there
        if (priceHistory.length && priceHistory[priceHistory.length - 1].d === today()) return;
        var forKey = key;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200 || forKey !== show.key) return;
            try {
                var list = JSON.parse(xhr.responseText);
                var m = list.find(c => c.card_image_id === card.id && c.card_name === card.name)
                        || list.find(c => c.card_image_id === card.id);
                if (m && m.market_price !== null && m.market_price !== undefined) recordPrice(Number(m.market_price));
            } catch (e) {}
        };
        xhr.open("GET", "https://optcgapi.com/api/sets/" + setId + "/");
        xhr.send();
    }

    readonly property real price: priceHistory.length ? priceHistory[priceHistory.length - 1].p : -1
    readonly property real previousPrice: priceHistory.length > 1 ? priceHistory[priceHistory.length - 2].p : -1

    Component.onCompleted: {
        try { sets = JSON.parse(host.readText(host.appPath("app/sets.json")) || "{}"); } catch (e) {}
        load();
        tick();
    }

    // ---- progression clock -------------------------------------------------------------
    readonly property string progressPath: dataDir + "/progress.json"
    property var progress: Progress.fresh(Date.now())
    property real now: Date.now()
    readonly property bool focusing: progress.focus.endsAt > now

    function downloadedSets() {
        return Object.keys(sets).filter(id => host.readText(cacheRoot + "/" + id + "/cards.json") !== "")
                                .map(id => ({ id: id, name: sets[id].name }));
    }

    function change(fn) {
        var r = Progress.update(host, progressPath, fn);
        progress = r.p;
        now = Date.now();
        announce(r.result || []);
    }

    function tick() {
        var t = Date.now(), idle = host.isIdle();
        var value = Progress.collectionValue(host, dataDir);   // income grows with it
        change(p => {
            var done = Progress.accrue(p, t, () => show.downloadedSets());
            done = done.concat(Progress.setValue(p, value));
            if (!idle) done = done.concat(Progress.addIncome(p, 1, t));
            if (Progress.focusRunning(p, t)) {
                // isIdle means 5+ minutes away; count the minutes past that
                p.focus.idleMinutes = idle ? p.focus.idleMinutes + 1 : 0;
                if (p.focus.idleMinutes + 5 >= Progress.FOCUS_IDLE_LIMIT) {
                    Progress.stopFocus(p);
                    done.push({ kind: "focusLost" });
                }
            }
            return done;
        });
    }

    function startFocus() {
        change(p => { Progress.startFocus(p, Date.now()); return []; });
        host.notify("Focus started", Progress.FOCUS_MINUTES + " minutes. Stay at your computer to earn a free pack.");
    }

    function stopFocus() {
        change(p => { Progress.stopFocus(p); return []; });
    }

    function announce(events) {
        events.forEach(e => {
            if (e.kind === "streak")
                host.notify("Day " + e.count + " streak", "+" + Progress.format(e.reward) + (e.freePack ? " and a free pack" : ""));
            else if (e.kind === "freePack")
                host.notify("A free pack is ready", "Open it from the desktop widget.");
            else if (e.kind === "achievement")
                host.notify("WANTED: " + e.a.title + (e.a.set ? " (" + e.a.set + ")" : ""), e.a.text + "  ·  bounty " + Progress.formatBounty(e.a.bounty)
                            + (e.a.reward ? "  ·  +" + Progress.format(e.a.reward) : ""));
            else if (e.kind === "bounty")
                host.notify("Bounty complete", Progress.bountyText(e.b) + "  ·  +" + Progress.bountyRewardText(e.b));
            else if (e.kind === "focusDone")
                host.notify("Focus session complete", "+1 free pack and +" + Progress.format(Progress.FOCUS_BERRIES));
            else if (e.kind === "focusLost")
                host.notify("Focus session lost", "You were away for " + Progress.FOCUS_IDLE_LIMIT + " minutes.");
        });
    }

    Timer {   // the progression clock
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: show.tick()
    }
    Timer {   // the focus countdown
        interval: 1000
        running: show.focusing
        repeat: true
        onTriggered: {
            show.now = Date.now();
            if (show.progress.focus.endsAt > 0 && show.now >= show.progress.focus.endsAt)
                show.change(p => [{ kind: "focusDone" }].concat(Progress.finishFocus(p)));
        }
    }
    Timer {   // a new card picked in the pack opener, or the collection grew
        interval: 1500
        running: !show.dragging
        repeat: true
        onTriggered: {
            show.load();
            show.loadCollection();
        }
    }
    Timer {   // the price, about once a day
        interval: 3600 * 1000
        running: true
        repeat: true
        onTriggered: show.refreshPrice()
    }

    // ---- tilt -----------------------------------------------------------------------------
    property real t: 0                // foil clock: only runs while hovered
    FrameAnimation {
        running: mouse.containsMouse && !show.dragging
        onTriggered: show.t += frameTime
    }
    readonly property bool tilting: mouse.containsMouse && !show.dragging
    property real tiltX: tilting ? Math.max(-1, Math.min(1, (mouse.mouseX - slab.x - slab.width / 2) / (slab.width / 2))) : 0
    property real tiltY: tilting ? Math.max(-1, Math.min(1, (mouse.mouseY - slab.y - slab.height / 2) / (slab.height / 2))) : 0
    property real tx: tiltX
    property real ty: tiltY
    Behavior on tx { SmoothedAnimation { velocity: 4 } }
    Behavior on ty { SmoothedAnimation { velocity: 4 } }

    Item {
        id: frame
        width: show.frameWidth
        height: show.frameHeight
        x: show.moveInside ? show.width - show.fromRight - width : 0
        y: show.moveInside ? show.height - show.fromBottom - height : 0

        // ---- the slab -----------------------------------------------------------------
        Item {
            id: slab
            visible: !!show.card
            x: show.pad
            y: show.pad
            width: show.slabWidth
            height: show.slabHeight
            transform: [
                Rotation {
                    origin.x: slab.width / 2; origin.y: slab.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: show.tx * 10
                },
                Rotation {
                    origin.x: slab.width / 2; origin.y: slab.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: -show.ty * 10
                }
            ]

            Rectangle {   // shadow on the desktop
                anchors.fill: parent
                anchors.topMargin: 3 * show.u
                anchors.margins: -1 * show.u
                radius: 6 * show.u
                color: "#000000"
                opacity: 0.45
                transform: Translate { x: -show.tx * 8 * show.u / 3; y: 2 * show.u - show.ty * 8 * show.u / 3 }
            }
            Rectangle {   // the acrylic's thickness, showing past the face as it tilts
                anchors.fill: parent
                radius: 5 * show.u
                color: "#22d8e4ff"
                border.color: "#55ffffff"
                border.width: 1
                transform: Translate { x: show.tx * 1.4 * show.u; y: show.ty * 1.4 * show.u + 0.8 * show.u }
            }
            Rectangle {   // the face
                id: face
                anchors.fill: parent
                radius: 5 * show.u
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#3dffffff" }
                    GradientStop { position: 0.45; color: "#14ffffff" }
                    GradientStop { position: 1.0; color: "#26ffffff" }
                }
                border.color: "#99ffffff"
                border.width: Math.max(1, 0.5 * show.u)
                Rectangle {   // bevel
                    anchors.fill: parent
                    anchors.margins: 1.8 * show.u
                    radius: 3.6 * show.u
                    color: "transparent"
                    border.color: "#40ffffff"
                    border.width: 1
                }
            }

            // label
            Rectangle {
                id: label
                x: show.slabPad
                y: show.slabPad
                width: show.cardWidth
                height: show.labelH
                radius: 2 * show.u
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#fbf8f1" }
                    GradientStop { position: 1.0; color: "#e9e3d6" }
                }
                Rectangle {   // rarity stripe
                    width: 1.6 * show.u
                    height: parent.height
                    radius: width / 2
                    color: show.tier.color
                }
                Column {
                    x: 5 * show.u
                    y: 3.5 * show.u
                    width: parent.width - grade.width - 10 * show.u
                    spacing: 0.6 * show.u
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: show.card ? Tiers.displayName(show.card) : ""
                        color: "#14171f"
                        font { pixelSize: 7.4 * show.u; weight: Font.Black }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: show.setId + ((show.sets[show.setId] || {}).name ? "  ·  " + show.sets[show.setId].name : "")
                        color: "#4c5260"
                        font { pixelSize: 4.4 * show.u; weight: Font.Bold }
                    }
                    Text {
                        text: show.card ? show.card.id : ""
                        color: "#4c5260"
                        font.pixelSize: 4.2 * show.u
                    }
                    Text {
                        text: show.owned && show.owned.first
                              ? "PULLED  " + new Date(show.owned.first).toLocaleDateString(Qt.locale("en_GB"), "d MMM yyyy").toUpperCase()
                              : "SHOWCASE"
                        color: "#8a8f9b"
                        font { pixelSize: 3.8 * show.u; letterSpacing: 0.3 * show.u; weight: Font.Bold }
                    }
                }
                Rectangle {   // the "grade": the rarity, big
                    id: grade
                    anchors.right: parent.right
                    anchors.rightMargin: 3 * show.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26 * show.u
                    height: parent.height - 6 * show.u
                    radius: 2 * show.u
                    color: "#14171f"
                    border.color: show.tier.color
                    border.width: Math.max(1, 0.6 * show.u)
                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: show.card ? show.shortTier[show.card.tier] || show.card.tier : ""
                            color: show.tier.color
                            font { pixelSize: (text.length > 4 ? 6.2 : 9.5) * show.u; weight: Font.Black }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "RARITY"
                            color: "#9aa0ad"
                            font { pixelSize: 3 * show.u; letterSpacing: 0.4 * show.u; weight: Font.Bold }
                        }
                    }
                }
            }

            // the card, in its well
            Rectangle {
                x: show.slabPad - 0.8 * show.u
                y: label.y + label.height + 0.6 * show.slabPad - 0.8 * show.u
                width: show.cardWidth + 1.6 * show.u
                height: show.cardWidth / 0.716 + 1.6 * show.u
                radius: 4.4 * show.u
                color: "#30000000"
                border.color: "#30ffffff"
                border.width: 1
                Card {
                    x: 0.8 * show.u
                    y: 0.8 * show.u
                    width: show.cardWidth
                    card: show.card
                    faceUp: true
                    time: show.t
                    tiltRotates: false
                    dropShadow: false
                    tiltX: show.tx
                    tiltY: show.ty
                }
            }

            // glare across the acrylic, sliding with the tilt
            Item {
                anchors.fill: parent
                clip: true
                Rectangle {
                    width: parent.width * 0.55
                    height: parent.height * 2
                    x: -width + (show.tx + 1) / 2 * (parent.width + width)
                    y: -parent.height / 2
                    rotation: 22
                    opacity: show.tilting ? 0.9 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00ffffff" }
                        GradientStop { position: 0.5; color: "#2effffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
            }
        }

        // ---- the info plate --------------------------------------------------------
        Rectangle {
            id: plate
            visible: !!show.card
            x: show.pad
            y: slab.y + slab.height + show.plateGap
            width: show.slabWidth
            height: show.plateHeight
            radius: 4 * show.u
            color: "#d90f1424"
            border.color: Qt.rgba(show.tier.color.r, show.tier.color.g, show.tier.color.b, 0.45)
            border.width: Math.max(1, 0.4 * show.u)

            Column {
                x: 5 * show.u
                y: 3.6 * show.u
                width: parent.width - 10 * show.u
                spacing: 2.6 * show.u

                Item {   // rarity  ·  copies
                    width: parent.width
                    height: rarity.height
                    Rectangle {
                        id: rarity
                        width: rarityText.width + 5 * show.u
                        height: rarityText.height + 1.6 * show.u
                        radius: height / 2
                        color: Qt.rgba(show.tier.color.r, show.tier.color.g, show.tier.color.b, 0.18)
                        border.color: show.tier.color
                        border.width: 1
                        Text {
                            id: rarityText
                            anchors.centerIn: parent
                            text: show.tier.label
                            color: show.tier.color
                            font { pixelSize: 4.4 * show.u; weight: Font.Bold }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: show.owned ? "×" + show.owned.count + " owned" : "not in your binder"
                        color: "#c8ccd6"
                        font { pixelSize: 4.6 * show.u; weight: Font.Bold }
                    }
                }

                Column {   // set completion
                    width: parent.width
                    spacing: 1.2 * show.u
                    Item {
                        width: parent.width
                        height: setText.height
                        Text {
                            id: setText
                            text: show.setId + " collection"
                            color: "#9aa0ad"
                            font.pixelSize: 4.2 * show.u
                        }
                        Text {
                            anchors.right: parent.right
                            text: show.setTotal ? show.setOwned + " / " + show.setTotal
                                                  + "  (" + Math.round(100 * show.setOwned / show.setTotal) + "%)" : ""
                            color: "#e8e8ee"
                            font { pixelSize: 4.2 * show.u; weight: Font.Bold }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1.4 * show.u
                        radius: height / 2
                        color: "#22283a"
                        Rectangle {
                            width: parent.width * (show.setTotal ? Math.min(1, show.setOwned / show.setTotal) : 0)
                            height: parent.height
                            radius: height / 2
                            color: show.tier.color
                        }
                    }
                }

                Item {   // market price
                    width: parent.width
                    height: priceText.height
                    Text {
                        id: priceText
                        text: show.card && show.card.type === "DON!!" ? "DON!! cards aren't priced"
                              : show.price >= 0 ? "$" + show.price.toFixed(2)
                              : "price: checking…"
                        color: show.price >= 0 ? "#fff6e0" : "#7a8090"
                        font { pixelSize: (show.price >= 0 ? 7.2 : 4.2) * show.u; weight: Font.Black }
                    }
                    Text {
                        anchors.left: priceText.right
                        anchors.leftMargin: 2.4 * show.u
                        anchors.baseline: priceText.baseline
                        visible: show.price >= 0 && show.previousPrice > 0   // needs a second day's price
                        readonly property real change: show.previousPrice > 0 ? (show.price - show.previousPrice) / show.previousPrice : 0
                        text: (change > 0 ? "▲ " : change < 0 ? "▼ " : "■ ") + Math.abs(change * 100).toFixed(1) + "%"
                        color: change > 0 ? "#6fdc8c" : change < 0 ? "#ff7a7a" : "#9aa0ad"
                        font { pixelSize: 4.4 * show.u; weight: Font.Bold }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.baseline: priceText.baseline
                        visible: show.price >= 0
                        text: "TCGplayer market"
                        color: "#7a8090"
                        font.pixelSize: 3.6 * show.u
                    }
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: show.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real grabX
            property real grabY

            onPressed: e => {
                if (e.button !== Qt.LeftButton) return;
                if (!show.moveInside) {        // native window drag
                    show.systemMoveRequested();
                    return;
                }
                grabX = e.x;
                grabY = e.y;
                show.dragging = true;
            }
            onPositionChanged: e => {
                if (!show.dragging) return;
                // in the full-screen item's coordinates, which don't move
                var p = mapToItem(show, e.x, e.y);
                show.fromRight = Math.max(0, Math.min(show.width - frame.width, show.width - (p.x - grabX) - frame.width));
                show.fromBottom = Math.max(0, Math.min(show.height - frame.height, show.height - (p.y - grabY) - frame.height));
            }
            onReleased: e => {
                if (!show.dragging) return;
                show.dragging = false;
                show.save();
            }
            onDoubleClicked: e => {
                if (e.button === Qt.LeftButton) show.host.openInspect();
            }
            onClicked: e => {
                if (e.button !== Qt.RightButton) return;
                show.card = null;     // put it away
                show.save();
                show.emptied();
            }
            onWheel: w => {
                var f = w.angleDelta.y > 0 ? 1.08 : 1 / 1.08;
                show.cardWidth = Math.max(140, Math.min(600, show.cardWidth * f));
                show.save();
            }
        }

        // ---- the status bar: berries, free packs, streak, focus ------------------------
        Rectangle {
            id: bar
            z: 2
            x: show.pad
            y: show.card ? plate.y + plate.height + show.barGap : show.pad
            width: show.slabWidth
            height: show.barHeight
            radius: height / 2
            color: "#e60f1424"
            border.color: show.focusing ? "#7fd1b9" : "#3a4258"
            border.width: show.focusing ? 2 : 1
            readonly property real fs: Math.max(11, 4.4 * show.u)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.height * 0.35
                spacing: parent.height * 0.3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Progress.format(show.progress.berries)
                    color: "#ffd56b"
                    font { pixelSize: bar.fs * 1.15; weight: Font.Black }
                }
                PillButton {   // open a pack (free if you have one)
                    anchors.verticalCenter: parent.verticalCenter
                    fontSize: bar.fs * 0.85
                    accent: show.progress.freePacks > 0 ? "#7fd1b9" : "#9aa0ad"
                    text: show.progress.freePacks > 0 ? show.progress.freePacks + " free" : "pack"
                    onClicked: show.host.openOverlay([])
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: show.progress.streak.count > 0
                    text: "day " + show.progress.streak.count
                    color: "#ffb347"
                    font { pixelSize: bar.fs * 0.85; weight: Font.Bold }
                }
            }
            PillButton {   // focus session: start / countdown + stop
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: parent.height * 0.18
                fontSize: bar.fs * 0.85
                accent: show.focusing ? "#7fd1b9" : "#ffd56b"
                readonly property int secondsLeft: Math.max(0, Math.ceil((show.progress.focus.endsAt - show.now) / 1000))
                text: show.focusing ? Math.floor(secondsLeft / 60) + ":" + ("0" + secondsLeft % 60).slice(-2) + "  stop"
                                    : "focus " + Progress.FOCUS_MINUTES + "m"
                onClicked: show.focusing ? show.stopFocus() : show.startFocus()
            }
        }
    }
}

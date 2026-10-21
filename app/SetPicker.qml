import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// The shop: sealed boxes on the shelves along the back wall, single packs
// fanned out on the counter. A box opens that set in box mode, a pack in
// single-pack mode. Every booster in sets.json, release order, English and
// Japanese on their own tabs. Sets that aren't downloaded yet download when
// picked; their pack and box photos are fetched up front.
Item {
    id: picker

    property Item stage
    property var have: ({})        // set id -> downloaded?
    property bool previewsFetched: false
    property bool reloading: false
    property string lang: "en"     // the tab: "en" | "jp"
    property string hoverId: ""    // what the sign describes
    property string hoverKind: ""  // "pack" | "box"

    readonly property var ids: stage ? Object.keys(stage.sets).filter(id => (stage.sets[id].lang || "en") === lang) : []

    onVisibleChanged: {
        if (!visible) return;
        hoverId = "";
        lang = (stage.sets[stage.setId] || {}).lang || "en";
        var h = {};
        Object.keys(stage.sets).forEach(id => h[id] = stage.downloaded(id));
        have = h;
        if (!previewsFetched) {   // pack and box photos of every set (skips ones already cached)
            previewsFetched = true;
            stage.host.run([stage.python, "-I", "-u", stage.fetchScript, "previews"], null, code => {
                reloading = true;   // pick up the new files
                reloading = false;
            });
        }
    }

    function owned(id) {
        return Object.keys(stage.collection.cards).filter(k => k.indexOf(id + ":") === 0).length;
    }
    function photo(id, name) {
        return reloading ? "" : "file://" + stage.cacheRoot + "/" + id + "/" + name;
    }
    function hover(id, kind, on) {
        if (on) {
            hoverId = id;
            hoverKind = kind;
        } else if (hoverId === id && hoverKind === kind) {
            hoverId = "";
        }
    }
    function choose(id, kind) {
        stage.chooseSet(id, kind);
    }
    function packPrice(id) {
        return Progress.packPrice(Tiers.setConfig(stage.sets[id]), stage.progress, id, stage.tierValues(id));
    }
    function boxPrice(id) {
        return Progress.boxPrice(Tiers.setConfig(stage.sets[id]), stage.progress, id, stage.tierValues(id));
    }
    // the set (and way of opening it) on screen right now
    function isCurrent(id, kind) {
        return id === stage.setId && kind === stage.mode && !!stage.db;
    }

    readonly property var confidence: ({
        documented: { label: "documented odds", color: "#7fd1b9" },
        estimated:  { label: "estimated odds",  color: "#ffd56b" },
        rough:      { label: "rough odds",      color: "#ff9a7a" }
    })

    // ---- the room -----------------------------------------------------------

    Rectangle {   // back wall
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0c0a10" }
            GradientStop { position: 0.6; color: "#17110f" }
            GradientStop { position: 1.0; color: "#0a0807" }
        }
        opacity: 0.97
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: picker.height * 0.03
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The card shop"
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Boxes on the shelf, single packs on the counter"
            color: "#9aa0ad"
            font.pixelSize: 13
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Repeater {
                model: [{ id: "en", label: "English" }, { id: "jp", label: "Japanese  日本語" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: picker.lang === modelData.id
                    width: tabText.implicitWidth + 36
                    height: 32
                    radius: 16
                    color: on ? "#ffd56b" : "#1a1f2b"
                    border.color: on ? "#ffd56b" : "#3a4152"
                    Text {
                        id: tabText
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        color: parent.on ? "#14171f" : "#d8dbe2"
                        font { pixelSize: 14; weight: Font.Black }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            picker.lang = parent.modelData.id;
                            picker.hoverId = "";
                        }
                    }
                }
            }
        }
    }

    // ---- the shelves: sealed boxes ------------------------------------------

    Item {
        id: shelves
        readonly property real plankH: 14
        readonly property real labelH: 34
        // as big as fits with every box on a shelf (whatever number of shelves does that best), at most 170 tall
        readonly property real boxH: {
            var n = Math.max(1, picker.ids.length), best = 0;
            for (var r = 1; r <= n; r++) {
                var tall = height / r - plankH - labelH - 18;
                var wide = (width / Math.ceil(n / r) - 18) / 0.95;
                best = Math.max(best, Math.min(170, tall, wide));
            }
            return Math.max(60, best);
        }
        readonly property real cellW: boxH * 0.95 + 18
        readonly property real cellH: boxH + plankH + labelH + 18
        readonly property int cols: Math.max(1, Math.min(picker.ids.length, Math.floor(width / cellW)))
        readonly property int rows: Math.ceil(picker.ids.length / cols)
        anchors {
            top: header.bottom; topMargin: 18
            bottom: sign.top; bottomMargin: 8
            left: parent.left; right: parent.right
            leftMargin: picker.width * 0.04; rightMargin: picker.width * 0.04
        }
        clip: true

        // the planks: one per row, scrolling with the boxes
        Repeater {
            model: shelves.rows
            Item {
                required property int index
                x: shelfGrid.x - 14
                y: shelfGrid.y + index * shelves.cellH + shelves.boxH + 18 - shelfGrid.contentY
                width: shelfGrid.width + 28
                height: shelves.plankH + 10
                Rectangle {   // shadow on the wall
                    width: parent.width
                    y: shelves.plankH
                    height: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#a0000000" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: shelves.plankH
                    radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#8a5a32" }
                        GradientStop { position: 0.25; color: "#6b4426" }
                        GradientStop { position: 1.0; color: "#3e2614" }
                    }
                }
            }
        }

        GridView {
            id: shelfGrid
            anchors.horizontalCenter: parent.horizontalCenter
            width: shelves.cols * cellWidth
            height: Math.min(parent.height, shelves.rows * cellHeight)
            cellWidth: shelves.cellW
            cellHeight: shelves.cellH
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: picker.ids

            delegate: Item {
                id: slot
                required property string modelData
                readonly property var info: picker.stage.sets[modelData]
                readonly property bool current: picker.isCurrent(modelData, "box")
                width: shelfGrid.cellWidth
                height: shelfGrid.cellHeight

                Item {
                    id: boxArt
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: shelves.boxH * 0.95
                    height: shelves.boxH
                    y: 18 - (boxMouse.containsMouse ? 10 : 0)
                    Behavior on y { NumberAnimation { duration: 150 } }

                    Image {
                        id: boxImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        verticalAlignment: Image.AlignBottom
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        source: picker.photo(slot.modelData, "box.png")
                    }
                    Rectangle {   // no photo: a plain carton
                        visible: boxImg.status !== Image.Ready
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.9
                        height: parent.height * 0.8
                        radius: 4
                        color: "#2a1b22"
                        border.color: "#5a3a40"
                        Text {
                            anchors.centerIn: parent
                            text: slot.modelData
                            color: "#b8a0a6"
                            font { pixelSize: 15; weight: Font.Black }
                        }
                    }
                    Rectangle {   // the one you're opening
                        visible: slot.current
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: (boxImg.status === Image.Ready ? boxImg.paintedWidth : parent.width * 0.9) + 10
                        height: (boxImg.status === Image.Ready ? boxImg.paintedHeight : parent.height * 0.8) + 10
                        anchors.bottomMargin: -5
                        radius: 8
                        color: "transparent"
                        border.color: "#ffd56b"
                        border.width: 2
                    }
                }

                Column {   // the price tag on the shelf lip
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: shelves.boxH + 18 + shelves.plankH + 3
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: slot.modelData
                        color: slot.current ? "#ffd56b" : "#e8e8ee"
                        font { pixelSize: 13; weight: Font.Black }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: picker.stage.offTheRecord ? "free" : Progress.format(picker.boxPrice(slot.modelData))
                        color: "#c9a26b"
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: boxMouse
                    x: boxArt.x
                    width: boxArt.width
                    height: shelves.boxH + 18
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: picker.hover(slot.modelData, "box", containsMouse)
                    onClicked: picker.choose(slot.modelData, "box")
                }
            }
        }
    }

    // ---- the sign between: what you're pointing at --------------------------

    Rectangle {
        id: sign
        readonly property var info: picker.hoverId ? picker.stage.sets[picker.hoverId] || {} : null
        readonly property var conf: info ? picker.confidence[info.confidence] || null : null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: counter.top
        anchors.bottomMargin: 10
        width: Math.min(picker.width * 0.9, signText.implicitWidth + 48)
        height: 46
        radius: 8
        color: "#1a1410"
        border.color: info ? "#c9a26b" : "#3a2c20"

        Text {
            id: signText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, picker.width * 0.9 - 48)
            elide: Text.ElideRight
            textFormat: Text.StyledText
            color: "#e8e2d6"
            font.pixelSize: 14
            text: {
                var i = sign.info;
                if (!i) return "Pick a <b>box</b> off the shelf to open a whole box, or a <b>pack</b> from the counter to open single packs";
                var id = picker.hoverId, box = picker.hoverKind === "box";
                var cfg = Tiers.setConfig(i);
                var what = box ? "Box of " + cfg.packsPerBox + " packs" : "Single pack";
                var price = picker.stage.offTheRecord ? "free"
                          : Progress.format(box ? picker.boxPrice(id) : picker.packPrice(id));
                var parts = ["<b><font color='#ffd56b'>" + id + "</font></b>  " + (i.name || "")
                             + (i.nameJp ? "  <font color='#8a8fa0'>" + i.nameJp + "</font>" : ""),
                             what + " <b>" + price + "</b>"];
                if (sign.conf) parts.push("<font color='" + sign.conf.color + "'>" + sign.conf.label + "</font>");
                parts.push(picker.have[id] ? picker.owned(id) + " cards collected" : "<font color='#9aa0ad'>not downloaded yet (~40 MB)</font>");
                return parts.join("   ·   ");
            }
        }
    }

    // ---- the counter: single packs -----------------------------------------

    Item {
        id: counter
        anchors { left: parent.left; right: parent.right; bottom: footer.top; bottomMargin: 10 }
        height: Math.max(170, Math.min(310, picker.height * 0.32))

        readonly property real topY: height * 0.66          // where the counter top meets the front
        readonly property real packH: Math.min(topY + 6, 230)
        readonly property real packW: packH * 0.62
        readonly property real avail: width * 0.9
        // the packs overlap when they don't fit side by side
        readonly property real step: picker.ids.length > 1
                                     ? Math.min(packW + 12, (avail - packW) / (picker.ids.length - 1)) : 0
        readonly property real startX: (width - (step * (picker.ids.length - 1) + packW)) / 2

        Rectangle {   // the counter top, seen from a little above
            x: parent.width * 0.02
            width: parent.width * 0.96
            y: counter.topY - 26
            height: 30
            radius: 4
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#5c3c22" }
                GradientStop { position: 1.0; color: "#8a5e36" }
            }
        }
        Rectangle {   // the front of the counter
            x: parent.width * 0.02
            width: parent.width * 0.96
            y: counter.topY + 4
            height: parent.height - y
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#4a2e18" }
                GradientStop { position: 0.08; color: "#2e1c10" }
                GradientStop { position: 1.0; color: "#160d07" }
            }
            Rectangle {   // the edge catching the light
                width: parent.width
                height: 3
                color: "#b07a48"
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 4
                text: "SINGLE PACKS"
                color: "#6b4a2e"
                font { pixelSize: Math.max(12, parent.height * 0.32); weight: Font.Black; letterSpacing: 6 }
            }
        }

        Repeater {
            model: picker.ids
            Item {
                id: packSlot
                required property string modelData
                required property int index
                readonly property bool current: picker.isCurrent(modelData, "pack")
                readonly property bool hovered: packMouse.containsMouse
                x: counter.startX + index * counter.step
                y: counter.topY - counter.packH + 4 - (hovered ? counter.packH * 0.22 : current ? 10 : 0)
                z: hovered ? 1000 : index
                width: counter.packW
                height: counter.packH
                Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                rotation: hovered ? 0 : (index % 3 - 1) * 1.5

                Rectangle {   // shadow on the counter
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - 6
                    width: parent.width * 0.9
                    height: 10
                    radius: 5
                    color: "#80000000"
                    visible: !packSlot.hovered
                }
                Image {
                    id: packImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    verticalAlignment: Image.AlignBottom
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    source: picker.photo(packSlot.modelData, "pack.png")
                }
                Rectangle {   // no photo: a plain wrapper
                    visible: packImg.status !== Image.Ready
                    anchors.fill: parent
                    radius: 4
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#b3122b" }
                        GradientStop { position: 1; color: "#141c44" }
                    }
                    border.color: "#e2bd63"
                    Text {
                        anchors.centerIn: parent
                        rotation: -90
                        text: packSlot.modelData
                        color: "#fff6e0"
                        font { pixelSize: 16; weight: Font.Black }
                    }
                }
                Rectangle {   // the one you're opening
                    visible: packSlot.current
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 6
                    color: "transparent"
                    border.color: "#ffd56b"
                    border.width: 2
                }
                Rectangle {   // the set code on a little tag, while you point at it
                    visible: packSlot.hovered
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    width: tagText.implicitWidth + 16
                    height: tagText.implicitHeight + 6
                    radius: height / 2
                    color: "#ffd56b"
                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        text: packSlot.modelData + "  ·  " + (picker.stage.offTheRecord ? "free" : Progress.format(picker.packPrice(packSlot.modelData)))
                        color: "#14171f"
                        font { pixelSize: 12; weight: Font.Black }
                    }
                }

                MouseArea {
                    id: packMouse
                    anchors.fill: parent
                    anchors.bottomMargin: packSlot.hovered ? -counter.packH * 0.22 : 0   // still yours while it's lifted
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: picker.hover(packSlot.modelData, "pack", containsMouse)
                    onClicked: picker.choose(packSlot.modelData, "pack")
                }
            }
        }
    }

    Text {
        id: footer
        anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
        text: "Click a box or a pack to open it (sets you haven't downloaded are fetched first, ~40 MB)   ·   S or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

import QtQuick

// Pick a set: every booster in sets.json, release order, English and Japanese
// on their own tabs. Sets that aren't downloaded yet download when picked;
// their pack photos are fetched up front.
Item {
    id: picker

    property Item stage
    property var have: ({})        // set id -> downloaded?
    property bool previewsFetched: false
    property bool reloading: false
    property string lang: "en"     // the tab: "en" | "jp"

    onVisibleChanged: {
        if (!visible) return;
        lang = (stage.sets[stage.setId] || {}).lang || "en";
        var h = {};
        Object.keys(stage.sets).forEach(id => h[id] = stage.downloaded(id));
        have = h;
        if (!previewsFetched) {   // pack photos of every set (skips ones already cached)
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

    readonly property var confidence: ({
        documented: { label: "documented odds", color: "#7fd1b9" },
        estimated:  { label: "estimated odds",  color: "#ffd56b" },
        rough:      { label: "rough odds",      color: "#ff9a7a" }
    })

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.94
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: picker.height * 0.04
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Choose a set"
            color: "#ffd56b"
            font { pixelSize: 28; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: picker.lang === "jp"
                  ? "Japanese boosters: 6-card packs, 1-2 hits a box · odds are Japanese community tallies · prices in ¥ at today's market"
                  : "Odds: documented = set-specific case data · estimated = era defaults + set facts · rough = nothing published"
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
                        onClicked: picker.lang = parent.modelData.id
                    }
                }
            }
        }
    }

    GridView {
        id: grid
        readonly property int cols: 8
        readonly property real tileW: Math.min(150, picker.width * 0.92 / cols - 20)
        anchors {
            top: header.bottom; topMargin: 24
            bottom: parent.bottom; bottomMargin: 44
            horizontalCenter: parent.horizontalCenter
        }
        width: cols * cellWidth
        cellWidth: tileW + 20
        cellHeight: tileW / 0.62 + 88
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: picker.stage ? Object.keys(picker.stage.sets).filter(id => (picker.stage.sets[id].lang || "en") === picker.lang) : []

        delegate: Item {
            id: tile
            required property string modelData
            readonly property var info: picker.stage.sets[modelData]
            readonly property bool current: modelData === picker.stage.setId
            readonly property bool local: !!picker.have[modelData]
            width: grid.cellWidth
            height: grid.cellHeight

            Item {
                id: art
                anchors.horizontalCenter: parent.horizontalCenter
                width: grid.tileW
                height: grid.tileW / 0.62
                y: mouse.containsMouse ? -8 : 0
                Behavior on y { NumberAnimation { duration: 150 } }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: 10
                    color: "transparent"
                    border.color: "#ffd56b"
                    border.width: 2
                    visible: tile.current
                }
                Image {
                    id: packImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    source: picker.reloading ? "" : "file://" + picker.stage.cacheRoot + "/" + tile.modelData + "/pack.png"
                }
                Text {
                    anchors.centerIn: parent
                    visible: packImg.status !== Image.Ready
                    text: tile.modelData
                    color: "#7a8090"
                    font { pixelSize: 18; weight: Font.Black }
                }
                Rectangle {   // Japanese product: the pack photo is the English one's
                    visible: tile.info.lang === "jp"
                    anchors { right: parent.right; top: parent.top; margins: 4 }
                    width: 30; height: 20; radius: 4
                    color: "#d0021b"
                    Text {
                        anchors.centerIn: parent
                        text: "JP"
                        color: "white"
                        font { pixelSize: 11; weight: Font.Black }
                    }
                }
            }

            Column {
                anchors.top: art.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: grid.tileW + 10
                spacing: 2
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData
                    color: tile.current ? "#ffd56b" : "#e8e8ee"
                    font { pixelSize: 14; weight: Font.Black }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.info.name
                    color: "#b8bcc6"
                    font.pixelSize: 11
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: !!tile.info.nameJp
                    text: tile.info.nameJp || ""
                    color: "#8a8fa0"
                    font.pixelSize: 10
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: (picker.confidence[tile.info.confidence] || {}).label || ""
                    color: (picker.confidence[tile.info.confidence] || {}).color || "#9aa0ad"
                    font.pixelSize: 10
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: !tile.local ? "not downloaded" : picker.owned(tile.modelData) + " cards collected"
                    color: "#7a8090"
                    font.pixelSize: 10
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.stage.chooseSet(tile.modelData)
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: "Click a set to open it (sets you haven't downloaded are fetched first, ~40 MB)   ·   S or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

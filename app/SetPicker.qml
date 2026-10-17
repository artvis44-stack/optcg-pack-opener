import QtQuick

// Pick a set: every booster in sets.json, release order. Sets that aren't
// downloaded yet show TCGplayer's pack photo and download when picked.
Item {
    id: picker

    property Item stage
    property var have: ({})        // set id -> downloaded?

    onVisibleChanged: {
        if (!visible) return;
        var h = {};
        Object.keys(stage.sets).forEach(id => h[id] = stage.downloaded(id));
        have = h;
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
            text: "Odds: documented = set-specific case data · estimated = era defaults + set facts · rough = nothing published"
            color: "#9aa0ad"
            font.pixelSize: 13
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
        cellHeight: tileW / 0.62 + 74
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: picker.stage ? Object.keys(picker.stage.sets) : []

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
                    source: tile.local ? "file://" + picker.stage.cacheRoot + "/" + tile.modelData + "/pack.png"
                                       : "https://tcgplayer-cdn.tcgplayer.com/product/" + tile.info.pack + "_in_1000x1000.jpg"
                    opacity: tile.local ? 1 : 0.55
                }
                Text {
                    anchors.centerIn: parent
                    visible: packImg.status !== Image.Ready
                    text: tile.modelData
                    color: "#7a8090"
                    font { pixelSize: 18; weight: Font.Black }
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

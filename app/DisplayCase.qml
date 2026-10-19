import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// A saved set in its display case (the vault's Sets tab): a framed case with a
// velvet back, its slabs laid out in rows, glass over them, a light above and a
// brass nameplate. The frame and velvet go with what kind of set it is; a Gem
// Set (every slab a 10) gets a gold frame that glows, a shimmer and sparkles.
Item {
    id: dcase

    property var saved: ({})          // the saved set: { title, style, gem, avg, ... }
    property var slabs: []            // its slabs (null: one that's gone)
    property real worth: 0
    property real time: 0
    property bool hovered: false
    property bool slabsClickable: false   // the opened case: a slab click shows it big
    signal clicked()
    signal slabClicked(var slab)

    readonly property bool gem: !!saved.gem
    readonly property real u: width / 100

    readonly property var styles: ({
        sp:        { frameA: "#7a4e2c", frameB: "#3a2412", velvetA: "#6a1222", velvetB: "#2a0610", accent: "#ff8a8a" },
        manga:     { frameA: "#3a3a3a", frameB: "#0c0c0c", velvetA: "#1c1c1c", velvetB: "#050505", accent: "#ffffff" },
        laa:       { frameA: "#6e3424", frameB: "#2e120a", velvetA: "#173a7a", velvetB: "#08183a", accent: "#8ab4ff" },
        sec:       { frameA: "#7a4e2c", frameB: "#3a2412", velvetA: "#11563a", velvetB: "#05261a", accent: "#7fe0b0" },
        master:    { frameA: "#5a3a22", frameB: "#20140a", velvetA: "#42205e", velvetB: "#1a0a2e", accent: "#d0a8ff" },
        strawhats: { frameA: "#c49a4a", frameB: "#5e4520", velvetA: "#0f2a4a", velvetB: "#06121f", accent: "#ffd56b" },
        emperors:  { frameA: "#c49a4a", frameB: "#5e4520", velvetA: "#3a0a0a", velvetB: "#160303", accent: "#ff6b6b" },
        admirals:  { frameA: "#c49a4a", frameB: "#5e4520", velvetA: "#16324a", velvetB: "#08141f", accent: "#9fd8ff" },
        wanted:    { frameA: "#8a6a3a", frameB: "#3a2a12", velvetA: "#5a4325", velvetB: "#2a1d0e", accent: "#ead9ae" },
        tr:        { frameA: "#c49a4a", frameB: "#5e4520", velvetA: "#3a2a06", velvetB: "#160f02", accent: "#ffe08a" },
        gold:      { frameA: "#c49a4a", frameB: "#5e4520", velvetA: "#2a2a2a", velvetB: "#0c0c0c", accent: "#ffe08a" },
        char:      { frameA: "#c8ccd6", frameB: "#5a5f6a", velvetA: "#4a1030", velvetB: "#1e0614", accent: "#ff9ad0" }
    })
    readonly property var st: styles[saved.style] || styles.master
    readonly property color frameA: gem ? "#ffe9a0" : st.frameA
    readonly property color frameB: gem ? "#a8780a" : st.frameB

    // the slabs' grid: as many columns as makes them biggest in the case's window
    readonly property real winW: width - 14 * u
    readonly property real winH: height - 30 * u
    readonly property int count: Math.max(1, slabs.length)
    readonly property int cols: {
        var best = 1, size = 0;
        for (var c = 1; c <= count; c++) {
            var rows = Math.ceil(count / c);
            var w = Math.min(winW / c, winH / rows * 0.62);   // a slab is about 0.62 wide for its height
            if (w > size) { size = w; best = c; }
        }
        return best;
    }
    readonly property real cellW: Math.min(winW / cols, winH / Math.ceil(count / cols) * 0.62)

    // glow behind a Gem Set's case
    Rectangle {
        visible: dcase.gem
        anchors.fill: parent
        anchors.margins: -3 * dcase.u
        radius: 4 * dcase.u
        color: "transparent"
        border.color: "#ffd700"
        border.width: 2.2 * dcase.u
        opacity: 0.35 + 0.25 * Math.sin(dcase.time * 2.2)
    }
    Rectangle {   // shadow
        x: 1.6 * dcase.u; y: 2.4 * dcase.u
        width: parent.width; height: parent.height
        radius: 3 * dcase.u
        color: "#000000"
        opacity: 0.55
    }
    Rectangle {   // the frame
        id: frame
        anchors.fill: parent
        radius: 3 * dcase.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: dcase.frameA }
            GradientStop { position: 0.5; color: Qt.darker(dcase.frameA, 1.25) }
            GradientStop { position: 1.0; color: dcase.frameB }
        }
        border.color: Qt.darker(dcase.frameB, 1.4)
        border.width: Math.max(1, 0.4 * dcase.u)
        scale: dcase.hovered ? 1.015 : 1
        Behavior on scale { NumberAnimation { duration: 140 } }

        Rectangle {   // the velvet back
            id: velvet
            x: 4 * dcase.u; y: 4 * dcase.u
            width: parent.width - 8 * dcase.u
            height: parent.height - 18 * dcase.u
            radius: 1.5 * dcase.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: dcase.st.velvetA }
                GradientStop { position: 1.0; color: dcase.st.velvetB }
            }
            border.color: Qt.darker(dcase.frameB, 1.8)
            border.width: Math.max(1, 0.8 * dcase.u)
            clip: true

            Rectangle {   // the light above, falling on the velvet
                anchors.horizontalCenter: parent.horizontalCenter
                y: -parent.height * 0.55
                width: parent.width * 1.1
                height: parent.height
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.6; color: "#00ffffff" }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 0.95, 0.85, 0.16) }
                }
            }
            Canvas {   // manga cases: a halftone screen in the velvet
                visible: dcase.saved.style === "manga"
                anchors.fill: parent
                opacity: 0.12
                onPaint: {
                    var g = getContext("2d");
                    g.reset();
                    g.fillStyle = "#ffffff";
                    var step = Math.max(6, 3 * dcase.u);
                    for (var y = 0; y < height; y += step)
                        for (var x = (y / step) % 2 ? step / 2 : 0; x < width; x += step) {
                            g.beginPath();
                            g.arc(x, y, step * 0.18, 0, Math.PI * 2);
                            g.fill();
                        }
                }
                onWidthChanged: requestPaint()
            }

            Grid {   // the slabs
                anchors.centerIn: parent
                columns: dcase.cols
                spacing: 0
                Repeater {
                    model: dcase.slabs
                    Item {
                        id: mini
                        required property var modelData
                        width: dcase.cellW
                        height: dcase.cellW / 0.62
                        readonly property real m: width * 0.08
                        Rectangle {   // acrylic
                            x: mini.m; y: mini.m
                            width: parent.width - 2 * mini.m
                            height: parent.height - 2 * mini.m
                            radius: width * 0.05
                            color: "#30e8f4ff"
                            border.color: !mini.modelData ? "#60ff8a7a" : mini.modelData.diamond ? Qt.hsla((dcase.time * 0.2) % 1, 0.9, 0.75, 1)
                                          : mini.modelData.grade === 10 ? "#ffd700" : "#a0ffffff"
                            border.width: Math.max(1, width * 0.03)
                            Rectangle {   // label: the grade
                                x: parent.width * 0.06; y: parent.width * 0.06
                                width: parent.width * 0.88
                                height: parent.height * 0.17
                                radius: 2
                                color: mini.modelData && mini.modelData.diamond ? "#dff6ff" : "#f4f1ea"
                                Text {
                                    anchors.centerIn: parent
                                    text: !mini.modelData ? "gone" : (mini.modelData.diamond ? "◆" : "") + mini.modelData.grade
                                    color: !mini.modelData ? "#a03a2a" : mini.modelData.grade === 10 ? "#b8860b" : "#14171f"
                                    font { pixelSize: Math.max(7, parent.height * 0.7); weight: Font.Black }
                                }
                            }
                            Image {   // the card
                                x: parent.width * 0.08
                                y: parent.height * 0.26
                                width: parent.width * 0.84
                                height: parent.height * 0.7
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                sourceSize.width: 240
                                source: mini.modelData && mini.modelData.image ? "file://" + mini.modelData.image : ""
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !!mini.modelData && dcase.slabsClickable
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dcase.slabClicked(mini.modelData)
                            }
                        }
                    }
                }
            }

            Rectangle {   // the glass: a reflection across it
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#14ffffff" }
                    GradientStop { position: 0.3; color: "#06ffffff" }
                    GradientStop { position: 0.32; color: "#00ffffff" }
                    GradientStop { position: 1.0; color: "#0affffff" }
                }
            }
            Rectangle {   // a Gem Set's shimmer, sweeping across the glass
                visible: dcase.gem
                readonly property real sweep: (dcase.time * 0.3) % 1.8 - 0.4
                x: sweep * parent.width
                y: -parent.height * 0.25
                width: parent.width * 0.18
                height: parent.height * 1.5
                rotation: 20
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00fff2c0" }
                    GradientStop { position: 0.5; color: "#40fff2c0" }
                    GradientStop { position: 1.0; color: "#00fff2c0" }
                }
            }
            Repeater {   // and its sparkles
                model: dcase.gem ? [[0.1, 0.12, 0], [0.86, 0.2, 1.3], [0.5, 0.06, 2.5], [0.2, 0.9, 3.7], [0.92, 0.85, 4.6]] : []
                Text {
                    required property var modelData
                    readonly property real tw: Math.max(0, Math.sin(dcase.time * 2.4 + modelData[2]))
                    x: modelData[0] * parent.width - width / 2
                    y: modelData[1] * parent.height - height / 2
                    text: "✦"
                    color: "#fff6d0"
                    font.pixelSize: Math.max(8, 4 * dcase.u)
                    opacity: tw
                    scale: 0.5 + tw
                }
            }
        }

        Rectangle {   // the brass nameplate
            id: plate
            anchors.horizontalCenter: parent.horizontalCenter
            y: velvet.y + velvet.height + 2.2 * dcase.u
            width: parent.width * 0.78
            height: 10 * dcase.u
            radius: 1.2 * dcase.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#f2d48a" }
                GradientStop { position: 0.5; color: "#c79a3c" }
                GradientStop { position: 1.0; color: "#8a6420" }
            }
            border.color: "#5a4010"
            Column {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: plate.width * 0.94
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: (dcase.saved.title || "").toUpperCase()
                    color: "#3a2606"
                    style: Text.Raised; styleColor: "#f8e4a8"
                    font { pixelSize: Math.max(8, 3.4 * dcase.u); weight: Font.Black; letterSpacing: 0.25 * dcase.u; family: "serif" }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (dcase.gem ? "★ GEM SET ★" : "avg grade " + Number(dcase.saved.avg || 0).toFixed(1))
                          + "   ·   " + dcase.slabs.length + " slabs   ·   " + Progress.format(dcase.worth)
                    color: "#4a3008"
                    font { pixelSize: Math.max(7, 2.4 * dcase.u); weight: Font.Bold; family: "serif" }
                }
            }
        }
        Repeater {   // brass screws in the corners
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Rectangle {
                required property var modelData
                width: 1.8 * dcase.u; height: width; radius: width / 2
                x: modelData[0] ? frame.width - width - 1.1 * dcase.u : 1.1 * dcase.u
                y: modelData[1] ? frame.height - height - 1.1 * dcase.u : 1.1 * dcase.u
                color: "#d8b060"
                border.color: "#6a4a14"
            }
        }
    }

    MouseArea {   // the whole case (under the slabs, which take their own clicks)
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: dcase.hovered = containsMouse
        onClicked: dcase.clicked()
    }
}

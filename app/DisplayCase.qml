import QtQuick
import "tiers.js" as Tiers
import "progress.js" as Progress

// A saved set in its display case (the vault's Sets tab): a slim bevelled frame
// round a shadow box with a velvet back, a light strip along the top, its slabs
// standing off the velvet in rows under glass, and an engraved plaque beneath them. The frame and velvet go with what kind of set it is; a Gem
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
        char:      { frameA: "#c8ccd6", frameB: "#5a5f6a", velvetA: "#4a1030", velvetB: "#1e0614", accent: "#ff9ad0" },
        vintage:   { frameA: "#6a4426", frameB: "#2a190e", velvetA: "#3a2a14", velvetB: "#160e05", accent: "#ead9ae" },
        promo:     { frameA: "#4a5a7a", frameB: "#1a2238", velvetA: "#0e3040", velvetB: "#04141c", accent: "#7fe0ff" }
    })
    readonly property var st: styles[saved.style] || styles.master
    readonly property color frameA: gem ? "#ffe9a0" : st.frameA
    readonly property color frameB: gem ? "#a8780a" : st.frameB

    // the slabs' grid: as many columns as makes them biggest in the case's window (above the plaque)
    readonly property real gap: 3 * u
    readonly property real winW: width - 10 * u
    readonly property real plateH: Math.min(13 * u, 72)
    readonly property real winH: height - 5.2 * u - 4 * u - plateH - 6 * u   // the velvet, less the light strip and the plaque
    readonly property int count: Math.max(1, slabs.length)
    readonly property int cols: {
        var best = 1, size = 0;
        for (var c = 1; c <= count; c++) {
            var rows = Math.ceil(count / c);
            var w = Math.min((winW - (c - 1) * gap) / c, ((winH - (rows - 1) * gap) / rows) * 0.62);   // a slab is about 0.62 wide for its height
            if (w > size) { size = w; best = c; }
        }
        return best;
    }
    readonly property int rows: Math.ceil(count / cols)
    readonly property real cellW: Math.min((winW - (cols - 1) * gap) / cols, ((winH - (rows - 1) * gap) / rows) * 0.62)

    // glow behind a Gem Set's case
    Rectangle {
        visible: dcase.gem
        anchors.fill: parent
        anchors.margins: -2.4 * dcase.u
        radius: 2.4 * dcase.u
        color: "transparent"
        border.color: "#ffd700"
        border.width: 1.4 * dcase.u
        opacity: 0.3 + 0.25 * Math.sin(dcase.time * 2.2)
    }

    Item {
        id: body
        anchors.fill: parent
        scale: dcase.hovered ? 1.015 : 1
        Behavior on scale { NumberAnimation { duration: 140 } }

        Rectangle {   // its shadow on the wall
            x: 0.8 * dcase.u; y: 2.2 * dcase.u
            width: parent.width; height: parent.height
            radius: 1.2 * dcase.u
            color: "#000000"
            opacity: 0.5
        }
        Rectangle {   // the frame: a slim bevelled moulding, lit from above
            id: frame
            anchors.fill: parent
            radius: 1.2 * dcase.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(dcase.frameA, 1.25) }
                GradientStop { position: 0.08; color: dcase.frameA }
                GradientStop { position: 0.92; color: dcase.frameB }
                GradientStop { position: 1.0; color: Qt.darker(dcase.frameB, 1.4) }
            }
            border.color: Qt.darker(dcase.frameB, 1.6)
            border.width: Math.max(1, 0.3 * dcase.u)
        }

        Rectangle {   // the shadow box: velvet back, a few centimetres deep
            id: velvet
            x: 2.6 * dcase.u; y: 2.6 * dcase.u
            width: parent.width - 5.2 * dcase.u
            height: parent.height - 5.2 * dcase.u
            radius: 0.4 * dcase.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(dcase.st.velvetA, 1.12) }
                GradientStop { position: 0.55; color: dcase.st.velvetA }
                GradientStop { position: 1.0; color: dcase.st.velvetB }
            }
            clip: true

            Canvas {   // manga cases: a halftone screen in the velvet
                visible: dcase.saved.style === "manga"
                anchors.fill: parent
                opacity: 0.1
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

            Rectangle {   // the light strip along the top, and the light it throws down the back
                width: parent.width
                height: parent.height * 0.6
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 0.96, 0.86, 0.26) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 0.96, 0.86, 0.07) }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            Rectangle {
                width: parent.width
                height: Math.max(1, 0.5 * dcase.u)
                color: "#fff6e0"
                opacity: 0.85
            }
            Repeater {   // the box's depth: shade along the sides and the bottom
                model: [[0, 0, 1, 0], [1, 0, 1, 0], [0, 1, 0, 1]]
                Rectangle {
                    required property var modelData
                    readonly property bool side: modelData[2] === 1
                    x: side && modelData[0] ? parent.width - width : 0
                    y: !side ? parent.height - height : 0
                    width: side ? 2.4 * dcase.u : parent.width
                    height: side ? parent.height : 2.4 * dcase.u
                    gradient: Gradient {
                        orientation: side ? Gradient.Horizontal : Gradient.Vertical
                        GradientStop { position: 0.0; color: side && !modelData[0] ? "#66000000" : "#00000000" }
                        GradientStop { position: 1.0; color: side && !modelData[0] ? "#00000000" : "#66000000" }
                    }
                }
            }

            Grid {   // the slabs, standing off the velvet
                x: (parent.width - width) / 2
                y: 4 * dcase.u + (dcase.winH - height) / 2
                columns: dcase.cols
                spacing: dcase.gap
                Repeater {
                    model: dcase.slabs
                    Item {
                        id: mini
                        required property var modelData
                        width: dcase.cellW
                        height: dcase.cellW / 0.62
                        Rectangle {   // its shadow on the velvet
                            x: parent.width * 0.05; y: parent.width * 0.07
                            width: parent.width; height: parent.height
                            radius: width * 0.05
                            color: "#000000"
                            opacity: 0.45
                        }
                        Rectangle {   // acrylic
                            anchors.fill: parent
                            radius: width * 0.05
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#5cf2f8ff" }
                                GradientStop { position: 1.0; color: "#30d8e4f0" }
                            }
                            border.color: !mini.modelData ? "#60ff8a7a" : mini.modelData.diamond ? Qt.hsla((dcase.time * 0.2) % 1, 0.9, 0.75, 1)
                                          : mini.modelData.grade === 10 ? "#ffd700" : "#c0ffffff"
                            border.width: Math.max(1, width * 0.025)
                            Rectangle {   // label: the grade
                                x: parent.width * 0.06; y: parent.width * 0.06
                                width: parent.width * 0.88
                                height: parent.height * 0.15
                                radius: 2
                                color: mini.modelData && mini.modelData.diamond ? "#dff6ff" : "#f4f1ea"
                                Rectangle {   // the label's coloured stripe
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * 0.06
                                    radius: 2
                                    color: !mini.modelData ? "#a03a2a" : mini.modelData.grade === 10 ? "#d4a017" : dcase.st.accent
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: !mini.modelData ? "gone" : (mini.modelData.diamond ? "◆ " : "") + mini.modelData.grade
                                    color: !mini.modelData ? "#a03a2a" : mini.modelData.grade === 10 ? "#b8860b" : "#14171f"
                                    font { pixelSize: Math.max(7, parent.height * 0.68); weight: Font.Black }
                                }
                            }
                            Image {   // the card
                                id: miniCard
                                x: parent.width * 0.07
                                y: parent.height * 0.24
                                width: parent.width * 0.86
                                height: parent.height * 0.72
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                sourceSize.width: 300
                                source: mini.modelData && mini.modelData.image ? "file://" + mini.modelData.image : ""
                            }
                            Loader {   // no picture of it: drawn
                                anchors.centerIn: miniCard
                                width: Math.min(miniCard.width, miniCard.height * 0.716)
                                height: width / 0.716
                                active: miniCard.status === Image.Error
                                sourceComponent: DrawnFace { card: mini.modelData }
                            }
                            Rectangle {   // a glint on the acrylic
                                x: parent.width * 0.06
                                y: parent.height * 0.22
                                width: Math.max(1, parent.width * 0.025)
                                height: parent.height * 0.7
                                color: "#40ffffff"
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

            Rectangle {   // the plaque, engraved, on the velvet under the slabs
                id: plate
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 * dcase.u }
                width: Math.min(parent.width * 0.86, Math.max(plateTitle.implicitWidth, plateLine.implicitWidth) + Math.min(8 * dcase.u, 48))
                height: dcase.plateH
                radius: 0.6 * dcase.u
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: dcase.gem ? "#c99a2e" : "#a8823c" }
                    GradientStop { position: 0.45; color: dcase.gem ? "#ffe9a0" : "#e6c77e" }
                    GradientStop { position: 1.0; color: dcase.gem ? "#b8860b" : "#9a7432" }
                }
                border.color: "#4a330c"
                border.width: Math.max(1, 0.25 * dcase.u)
                Rectangle {   // its shadow
                    z: -1
                    x: 0.5 * dcase.u; y: 0.8 * dcase.u
                    width: parent.width; height: parent.height
                    radius: parent.radius
                    color: "#000000"
                    opacity: 0.5
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 0.3 * dcase.u
                    Text {
                        id: plateTitle
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, dcase.width * 0.8)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (dcase.saved.title || "").toUpperCase()
                        color: "#2e1e04"
                        style: Text.Raised; styleColor: "#fbe9b4"
                        font { pixelSize: Math.max(9, Math.min(3.8 * dcase.u, 24)); weight: Font.Black; letterSpacing: Math.min(0.3 * dcase.u, 2) }
                    }
                    Text {
                        id: plateLine
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (dcase.gem ? "★ GEM SET ★" : "avg grade " + Number(dcase.saved.avg || 0).toFixed(1))
                              + "   ·   " + dcase.slabs.length + " slabs   ·   " + Progress.format(dcase.worth)
                        color: "#4a3008"
                        font { pixelSize: Math.max(7, Math.min(2.6 * dcase.u, 16)); weight: Font.Bold }
                    }
                }
            }

            Rectangle {   // the glass: one soft diagonal reflection
                x: parent.width * 0.58
                y: -parent.height * 0.3
                width: parent.width * 0.16
                height: parent.height * 1.6
                rotation: 24
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: "#0dffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
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
        Rectangle {   // the glass's edge, catching the light
            x: velvet.x; y: velvet.y
            width: velvet.width; height: velvet.height
            color: "transparent"
            border.color: "#26ffffff"
            border.width: Math.max(1, 0.25 * dcase.u)
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

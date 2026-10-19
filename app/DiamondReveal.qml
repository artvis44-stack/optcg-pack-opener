import QtQuick
import "progress.js" as Progress

// A DIAMOND LABEL 10 is back (Progress.DIAMOND_CHANCE): the whole screen goes
// for it. Prism rays turn behind it, diamonds rain, shockwaves, the slab slams
// in with the screen shaking, the title waves through the rainbow and the
// value counts up to 10x the card. Stage.qml shows it for a while; a click
// moves on.
Item {
    id: reveal

    property var slab: null            // the slab (stage.localCard'd), null: hidden
    property real value: 0             // what it's worth
    property real time: 0
    readonly property bool on: !!slab
    signal dismissed()

    visible: opacity > 0
    opacity: on ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350 } }

    property real shown: 0             // the value, counting up
    property real quake: 0             // how hard the screen shakes, 1 at the slam
    readonly property real shakeX: quake * 30 * Math.sin(time * 90)
    readonly property real shakeY: quake * 22 * Math.cos(time * 73)

    onOnChanged: if (on) intro.restart()

    SequentialAnimation {
        id: intro
        ScriptAction { script: { reveal.shown = 0; } }
        ParallelAnimation {
            NumberAnimation { target: slabBox; property: "scale"; from: 4; to: 1; duration: 520; easing.type: Easing.InQuad }
            NumberAnimation { target: slabBox; property: "rotation"; from: -25; to: 0; duration: 520; easing.type: Easing.OutQuad }
            NumberAnimation { target: slabBox; property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { target: title; property: "opacity"; from: 0; to: 0; duration: 0 }
            NumberAnimation { target: tenText; property: "scale"; from: 0; to: 0; duration: 0 }
        }
        ScriptAction { script: { ring1.go(); shake.restart(); } }
        PauseAnimation { duration: 180 }
        ParallelAnimation {
            NumberAnimation { target: title; property: "opacity"; to: 1; duration: 300 }
            NumberAnimation { target: tenText; property: "scale"; from: 0; to: 1; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 3 }
        }
        ScriptAction { script: ring2.go() }
        NumberAnimation { target: reveal; property: "shown"; from: 0; to: reveal.value; duration: 1800; easing.type: Easing.OutCubic }
        ScriptAction { script: ring1.go() }
    }

    NumberAnimation {   // the slam: a hard shake, settling
        id: shake
        target: reveal; property: "quake"
        from: 1; to: 0; duration: 1100; easing.type: Easing.OutQuad
    }

    // ---- the room goes dark, with a glow behind the slab ---------------------------
    Rectangle {
        anchors.fill: parent
        color: "#02040c"
        opacity: 0.9
    }
    MouseArea {
        anchors.fill: parent
        enabled: reveal.on
        cursorShape: Qt.PointingHandCursor
        onClicked: reveal.dismissed()
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(reveal.width, reveal.height) * 1.1
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#5a7ae8ff" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
        opacity: 0.6 + 0.2 * Math.sin(reveal.time * 2)
    }

    // ---- prism rays, turning --------------------------------------------------------
    Item {
        anchors.centerIn: parent
        width: 1; height: 1
        rotation: reveal.time * 14
        Repeater {
            model: 18
            Rectangle {
                required property int index
                x: -width / 2
                y: 0
                width: 70 + (index % 3) * 30
                height: Math.hypot(reveal.width, reveal.height) * 0.6
                transformOrigin: Item.Top
                rotation: index * 20
                antialiasing: true
                opacity: 0.16 + 0.1 * Math.sin(reveal.time * 3 + index)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.hsla((index / 18 + reveal.time * 0.05) % 1, 1, 0.75, 0.9) }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
        }
    }

    // ---- shockwave rings ------------------------------------------------------------
    component Ring: Rectangle {
        id: ring
        function go() { anim.restart(); }
        anchors.centerIn: parent
        width: 60; height: width
        radius: width / 2
        color: "transparent"
        border.width: 10
        border.color: "#dff6ff"
        antialiasing: true
        opacity: 0
        ParallelAnimation {
            id: anim
            NumberAnimation { target: ring; property: "width"; from: 60; to: 1800; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 900 }
        }
    }
    Ring { id: ring1 }
    Ring { id: ring2; border.color: "#ffd1f5" }

    // ---- diamond rain -------------------------------------------------------------
    Repeater {
        model: reveal.on ? 70 : 0
        Text {
            id: shard
            required property int index
            readonly property real seed: Math.random()
            text: index % 4 === 0 ? "✦" : "◆"
            x: Math.random() * reveal.width
            color: Qt.hsla(Math.random(), 0.85, 0.82, 1)
            style: Text.Outline; styleColor: "#ffffff"
            font.pixelSize: 10 + Math.random() * 30
            opacity: 0.55 + Math.random() * 0.45
            NumberAnimation on y {
                from: -60 - Math.random() * reveal.height; to: reveal.height + 60
                duration: 1800 + shard.seed * 2600
                loops: Animation.Infinite
            }
            NumberAnimation on rotation {
                from: 0; to: shard.seed > 0.5 ? 360 : -360
                duration: 700 + shard.seed * 1500
                loops: Animation.Infinite
            }
        }
    }

    // ---- the slab and the words ------------------------------------------------------
    Item {
        id: stageBox
        width: parent.width
        height: parent.height
        x: reveal.shakeX
        y: reveal.shakeY

        Item {   // title: each letter its own colour, waving
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            y: reveal.height * 0.06
            width: letters.width
            height: letters.height
            Row {
                id: letters
                spacing: 2
                Repeater {
                    model: "DIAMOND LABEL".split("")
                    Text {
                        required property string modelData
                        required property int index
                        text: modelData === " " ? "  " : modelData
                        y: 10 * Math.sin(reveal.time * 5 + index * 0.55)
                        color: Qt.hsla((reveal.time * 0.35 + index * 0.06) % 1, 0.95, 0.75, 1)
                        style: Text.Outline; styleColor: "#ffffff"
                        font { pixelSize: Math.min(76, reveal.width / 14); weight: Font.Black; italic: true }
                    }
                }
            }
        }

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: title.bottom; topMargin: 4 }
            text: "✦  SECRET GRADE  ·  1 IN " + Math.round(1 / Progress.DIAMOND_CHANCE) + "  ✦"
            color: "#bfe9ff"
            font { pixelSize: 18; weight: Font.Black; letterSpacing: 6 }
            opacity: title.opacity * (0.7 + 0.3 * Math.sin(reveal.time * 4))
        }

        Slab {
            id: slabBox
            anchors.centerIn: parent
            anchors.verticalCenterOffset: reveal.height * 0.04 + 8 * Math.sin(reveal.time * 1.6)
            width: Math.min(300, reveal.height * 0.36)
            card: reveal.slab
            time: reveal.time
            hoverTilt: false
        }

        Text {   // the big 10, left of the slab
            id: tenText
            anchors { right: slabBox.left; rightMargin: 40; verticalCenter: slabBox.verticalCenter }
            text: "10"
            color: Qt.hsla((reveal.time * 0.3) % 1, 0.9, 0.8, 1)
            style: Text.Outline; styleColor: "#ffffff"
            font { pixelSize: Math.min(200, reveal.height * 0.22); weight: Font.Black; italic: true }
            rotation: -8 + 3 * Math.sin(reveal.time * 3)
        }
        Column {   // and what it's worth, right of it
            anchors { left: slabBox.right; leftMargin: 40; verticalCenter: slabBox.verticalCenter }
            spacing: 6
            opacity: title.opacity
            Text {
                text: "×" + Progress.DIAMOND_MULT + " VALUE"
                color: "#fff6c0"
                style: Text.Outline; styleColor: "#7a4e10"
                font { pixelSize: 44; weight: Font.Black; italic: true }
                scale: 1 + 0.06 * Math.sin(reveal.time * 6)
            }
            Text {
                text: Progress.format(reveal.shown)
                color: "#ffd700"
                style: Text.Outline; styleColor: "#3a2400"
                font { pixelSize: 40; weight: Font.Black }
            }
        }

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: reveal.height * 0.05 }
            text: reveal.slab ? reveal.slab.name + "  ·  " + reveal.slab.set + "  ·  in your vault (G)   ·   click to continue" : ""
            color: "#9fc6e0"
            font { pixelSize: 16; weight: Font.Bold }
        }
    }
}

import QtQuick
import "progress.js" as Progress

// The wanted board: today's bounties on the left, wanted posters on the right
// (unlocked ones show their bounty and date, locked ones what it takes and how
// far along you are). Tabs across the top: the overall board, the season (this
// week's event and weekly bounties, the month's goals and reward track), then
// one board per set. Left / Right switch boards.
Item {
    id: board

    property Item stage
    readonly property var p: stage ? stage.progress : Progress.fresh(Date.now())
    readonly property var setIds: stage ? Object.keys(stage.sets) : []
    property string set: ""    // "" = the overall board, "season" = the season, else a set
    readonly property bool seasonTab: set === "season"
    readonly property string setId: seasonTab ? "" : set
    readonly property var shown: seasonTab ? [] : set ? Progress.setBoard(p, set) : Progress.ACHIEVEMENTS
    readonly property int gotCount: shown.filter(x => !!p.achievements[x.id]).length

    function step(d) {
        var tabs = ["", "season"].concat(setIds);
        set = tabs[(tabs.indexOf(set) + d + tabs.length) % tabs.length];
    }

    onVisibleChanged: if (visible) set = ""

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.95
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    Column {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        y: board.height * 0.05
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: board.seasonTab ? Progress.seasonName(board.p.season.id || Progress.monthOf(Date.now()))
                  : board.set ? board.set + "  " + ((board.stage.sets[board.set] || {}).name || "") : "Wanted Board"
            color: "#ffd56b"
            font { pixelSize: 30; weight: Font.Black; italic: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: board.seasonTab ? "Season points  " + Progress.seasonPoints(board.p) + "  ·  "
                                    + Object.keys(board.p.season.tiers || {}).length + " / " + Progress.SEASON_TIERS.length + " rewards"
                  : (board.set ? "Bounty in this set  " : "Your bounty  ") + Progress.format(Progress.totalBounty(board.p, board.set))
                    + (!board.set && Progress.title(board.p) ? "  ·  " + Progress.title(board.p) : "")
            color: "#fff6e0"
            font { pixelSize: 20; weight: Font.Black }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var s: board.p.stats
            readonly property var ss: Progress.setStats(board.p, board.setId)
            visible: !board.seasonTab
            text: board.set
                  ? ss.packs + " packs  ·  " + ss.boxes + " boxes  ·  " + ss.cases + " cases  ·  "
                    + Math.floor(ss.completion * 100) + "% of the set  ·  worth " + Progress.format(ss.value)
                  : s.packs + " packs  ·  " + s.boxes + " boxes  ·  " + s.cases + " cases  ·  "
                    + s.focus + " focus sessions  ·  " + s.sold + " cards sold for " + Progress.format(s.soldValue)
                    + "  ·  day " + board.p.streak.count + " streak"
            color: "#9aa0ad"
            font.pixelSize: 14
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !board.set
            text: "Collection worth " + Progress.format(board.p.stats.value || 0) + "  →  passive income "
                  + Progress.format(Progress.incomePerMinute(board.p)) + "/min, up to "
                  + Progress.format(Progress.incomeDailyCap(board.p)) + " a day"
            color: "#7fd1b9"
            font { pixelSize: 14; weight: Font.Bold }
        }
        Flow {   // the boards: overall, then one per set
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(board.width * 0.9, (board.setIds.length + 1) * 92)
            spacing: 6
            topPadding: 6
            PillButton {
                text: "Overall"
                fontSize: 12
                accent: board.set === "" ? "#ffd56b" : "#7a8090"
                onClicked: board.set = ""
            }
            PillButton {
                text: "Season"
                fontSize: 12
                accent: board.seasonTab ? "#ffd56b" : "#c8a0ff"
                onClicked: board.set = "season"
            }
            Repeater {
                model: board.setIds
                PillButton {
                    required property string modelData
                    readonly property int got: Progress.setBoard(board.p, modelData).filter(x => !!board.p.achievements[x.id]).length
                    text: modelData + (got ? "  " + got : "")
                    fontSize: 12
                    accent: board.set === modelData ? "#ffd56b" : got ? "#c8a96a" : "#7a8090"
                    onClicked: board.set = modelData
                }
            }
        }
    }

    // ---- today's bounties ------------------------------------------------------------
    Column {
        id: daily
        x: board.width * 0.05
        y: header.y + header.height + 36
        width: Math.min(420, board.width * 0.28)
        spacing: 14

        Text {
            text: "Today's bounties"
            color: "#ffd56b"
            font { pixelSize: 18; weight: Font.Black }
        }
        Repeater {
            model: board.p.bounties.list || []
            Rectangle {
                required property var modelData
                width: daily.width
                height: bountyColumn.height + 24
                radius: 10
                color: modelData.done ? "#163626" : "#151b2c"
                border.color: modelData.done ? "#6fdc8c" : "#2c3550"
                Column {
                    id: bountyColumn
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 6
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: (parent.parent.modelData.done ? "✓  " : "") + Progress.bountyText(parent.parent.modelData)
                        color: "#e8e8ee"
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: "#22283a"
                        Rectangle {
                            readonly property var b: parent.parent.parent.modelData
                            width: parent.width * Math.min(1, b.progress / b.goal)
                            height: parent.height
                            radius: 3
                            color: b.done ? "#6fdc8c" : "#ffd56b"
                        }
                    }
                    Text {
                        readonly property var b: parent.parent.modelData
                        text: (b.kind === "income" ? Progress.format(b.progress) + " / " + Progress.format(b.goal) : b.progress + " / " + b.goal)
                              + "   ·   reward " + Progress.bountyRewardText(b)
                        color: "#9aa0ad"
                        font.pixelSize: 12
                    }
                }
            }
        }
        Text {
            width: daily.width
            wrapMode: Text.WordWrap
            text: "New bounties every day. Earn berries by being at your computer, finishing focus sessions on the desktop widget, keeping your daily streak and selling duplicates in the binder."
            color: "#7a8090"
            font.pixelSize: 12
        }

        // ---- berries: where they came from and went (the ledger) ----
        Text {
            topPadding: 8
            text: "Berries"
            color: "#ffd56b"
            font { pixelSize: 18; weight: Font.Black }
        }
        Grid {
            id: ledger
            readonly property real now: Date.now()
            readonly property var periods: [Progress.ledger(board.p, 1, now), Progress.ledger(board.p, 7, now), Progress.ledger(board.p, 0, now)]
            // rows: [label, side, key] -- a key of "" is that side's total; only rows with something in them
            readonly property var rows: {
                var out = [["Earned", "earn", ""]];
                Progress.EARNINGS.forEach(e => { if (periods[2].earn[e[0]]) out.push([e[1], "earn", e[0]]); });
                out.push(["Spent", "spend", ""]);
                Progress.SPENDING.forEach(e => { if (periods[2].spend[e[0]]) out.push([e[1], "spend", e[0]]); });
                out.push(["Net", "net", ""]);
                return out;
            }
            function amount(period, row) {
                var t = periods[period];
                if (row[1] === "net") return Progress.ledgerSum(t.earn) - Progress.ledgerSum(t.spend);
                return row[2] ? t[row[1]][row[2]] || 0 : Progress.ledgerSum(t[row[1]]);
            }
            function short(n) {
                var a = Math.abs(n), sign = n < 0 ? "-" : "";
                return a >= 1e6 ? sign + "฿" + (a / 1e6).toFixed(a >= 1e8 ? 0 : 1) + "M"
                     : a >= 1e4 ? sign + "฿" + Math.round(a / 1e3) + "k" : sign + Progress.format(a);
            }
            columns: 4
            columnSpacing: 10
            rowSpacing: 3
            width: daily.width

            Repeater {
                model: ["", "Today", "7 days", "All time"]
                Text {
                    required property string modelData
                    required property int index
                    width: index === 0 ? daily.width - 3 * 70 - 30 : 70
                    horizontalAlignment: index === 0 ? Text.AlignLeft : Text.AlignRight
                    text: modelData
                    color: "#7a8090"
                    font { pixelSize: 12; weight: Font.Bold }
                }
            }
            Repeater {
                model: ledger.rows.length * 4
                Text {
                    required property int index
                    readonly property var row: ledger.rows[Math.floor(index / 4)]
                    readonly property int col: index % 4
                    readonly property bool total: row[2] === ""
                    readonly property real value: col ? ledger.amount(col - 1, row) : 0
                    width: col === 0 ? daily.width - 3 * 70 - 30 : 70
                    horizontalAlignment: col === 0 ? Text.AlignLeft : Text.AlignRight
                    elide: Text.ElideRight
                    text: col === 0 ? (total ? row[0] : "   " + row[0]) : ledger.short(value)
                    color: !total ? "#c8ccd6"
                           : row[1] === "earn" ? "#7fd1b9" : row[1] === "spend" ? "#ff9a7a" : value >= 0 ? "#ffd56b" : "#ff8a7a"
                    font { pixelSize: 12; weight: total ? Font.Black : Font.Normal }
                }
            }
        }
        Text {
            width: daily.width
            wrapMode: Text.WordWrap
            readonly property var free: Progress.ledger(board.p, 0, Date.now()).free
            text: "Counted since " + ((board.p.ledger || {}).since || "today")
                  + (Progress.ledgerSum(free) ? "  ·  free packs opened: " + Progress.ledgerSum(free) : "")
            color: "#7a8090"
            font.pixelSize: 11
        }
    }

    // ---- the season: this week's event and bounties, the month's goals and rewards ----
    Flickable {
        id: season
        visible: board.seasonTab
        anchors {
            left: daily.right; leftMargin: board.width * 0.04
            right: parent.right; rightMargin: board.width * 0.04
            top: daily.top
            bottom: parent.bottom; bottomMargin: 44
        }
        contentHeight: seasonCol.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        readonly property real now: Date.now()
        readonly property var event: Progress.currentEvent(board.p)
        readonly property string sid: board.p.season.id || Progress.monthOf(now)
        readonly property var goals: Progress.seasonGoals(sid)
        readonly property int daysLeft: {
            var d = new Date(now), end = new Date(d.getFullYear(), d.getMonth() + 1, 1);
            return Math.max(1, Math.ceil((end.getTime() - now) / 86400000));
        }

        Column {
            id: seasonCol
            width: season.width
            spacing: 12

            Rectangle {   // this week's event
                width: parent.width
                height: eventCol.height + 24
                radius: 10
                color: "#1b1530"
                border.color: "#c8a0ff"
                Column {
                    id: eventCol
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 4
                    Text {
                        text: season.event ? "This week: " + season.event.name : "This week's event starts with your next session"
                        color: "#c8a0ff"
                        font { pixelSize: 18; weight: Font.Black }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: !!season.event
                        text: season.event ? season.event.text + "  ·  until Sunday night" : ""
                        color: "#e8e8ee"
                        font.pixelSize: 14
                    }
                }
            }

            Text {
                text: "This week's bounties"
                color: "#ffd56b"
                font { pixelSize: 18; weight: Font.Black }
            }
            Repeater {
                model: board.p.weekly.list || []
                Rectangle {
                    required property var modelData
                    width: seasonCol.width
                    height: 54
                    radius: 10
                    color: modelData.done ? "#163626" : "#151b2c"
                    border.color: modelData.done ? "#6fdc8c" : "#2c3550"
                    Text {
                        x: 14; y: 9
                        text: (modelData.done ? "✓  " : "") + Progress.weeklyText(modelData)
                        color: "#e8e8ee"
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 14 }
                        y: 9
                        text: (modelData.kind === "active" ? Math.floor(modelData.progress / 60) + " / " + Math.round(modelData.goal / 60) + " h"
                                                            : modelData.progress + " / " + modelData.goal)
                              + "  ·  " + Progress.weeklyRewardText(modelData)
                        color: "#9aa0ad"
                        font.pixelSize: 13
                    }
                    Rectangle {
                        x: 14; y: 36
                        width: parent.width - 28
                        height: 6
                        radius: 3
                        color: "#22283a"
                        Rectangle {
                            width: parent.width * Math.min(1, modelData.progress / modelData.goal)
                            height: parent.height
                            radius: 3
                            color: modelData.done ? "#6fdc8c" : "#ffd56b"
                        }
                    }
                }
            }

            Text {
                topPadding: 8
                text: "The season's reward track  ·  " + season.daysLeft + " day" + (season.daysLeft > 1 ? "s" : "") + " left"
                color: "#ffd56b"
                font { pixelSize: 18; weight: Font.Black }
            }
            Row {
                spacing: 8
                Repeater {
                    model: Progress.SEASON_TIERS
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool reached: !!(board.p.season.tiers || {})[index]
                        width: (seasonCol.width - 32) / 5
                        height: 84
                        radius: 8
                        color: reached ? "#2a2410" : "#151b2c"
                        border.color: reached ? "#ffd56b" : index >= 3 ? "#c8a0ff" : "#2c3550"
                        Column {
                            x: 10; y: 8
                            width: parent.width - 20
                            spacing: 3
                            Text {
                                text: (parent.parent.reached ? "✓ " : "") + modelData.pts + " points"
                                color: parent.parent.reached ? "#ffd56b" : "#e8e8ee"
                                font { pixelSize: 14; weight: Font.Black }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                text: Progress.seasonTierText(modelData, season.sid)
                                color: "#9aa0ad"
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Text {
                topPadding: 8
                text: "Goals  ·  " + Progress.seasonPoints(board.p) + " / " + season.goals.reduce((n, g) => n + g.pts, 0) + " points"
                color: "#ffd56b"
                font { pixelSize: 18; weight: Font.Black }
            }
            Flow {
                width: parent.width
                spacing: 10
                Repeater {
                    model: season.goals
                    Rectangle {
                        required property var modelData
                        readonly property bool reached: !!(board.p.season.done || {})[modelData.id]
                        readonly property int have: Math.min(modelData.goal, Progress.seasonCount(board.p, modelData.id))
                        width: (seasonCol.width - 20) / 3
                        height: 74
                        radius: 8
                        color: reached ? "#163626" : "#151b2c"
                        border.color: reached ? "#6fdc8c" : "#2c3550"
                        Text {
                            x: 12; y: 10
                            width: parent.width - 24
                            elide: Text.ElideRight
                            text: (parent.reached ? "✓  " : "") + modelData.text
                            color: "#e8e8ee"
                            font { pixelSize: 13; weight: Font.Bold }
                        }
                        Text {
                            x: 12; y: 32
                            text: parent.have + " / " + modelData.goal + "  ·  " + modelData.pts + " points"
                            color: "#9aa0ad"
                            font.pixelSize: 12
                        }
                        Rectangle {
                            x: 12; y: 54
                            width: parent.width - 24
                            height: 5
                            radius: 2.5
                            color: "#22283a"
                            Rectangle {
                                width: parent.width * parent.parent.have / modelData.goal
                                height: parent.height
                                radius: 2.5
                                color: parent.parent.reached ? "#6fdc8c" : "#c8a0ff"
                            }
                        }
                    }
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: Object.keys(board.p.seasons || {}).length > 0
                text: "Past seasons: " + Object.keys(board.p.seasons || {}).sort().reverse()
                          .map(k => Progress.arcOf(k).name + " " + k + " (" + board.p.seasons[k].points + " points)").join("  ·  ")
                color: "#7a8090"
                font.pixelSize: 12
            }
        }
    }

    // ---- wanted posters ----------------------------------------------------------------
    GridView {
        id: posters
        visible: !board.seasonTab
        anchors {
            left: daily.right; leftMargin: board.width * 0.04
            right: parent.right; rightMargin: board.width * 0.04
            top: daily.top
            bottom: parent.bottom; bottomMargin: 44
        }
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 190)))
        cellHeight: 250
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: board.shown

        delegate: Item {
            required property var modelData
            readonly property string got: board.p.achievements[modelData.id] || ""
            readonly property bool legendary: modelData.bounty >= 1e9   // the really hard ones
            width: posters.cellWidth
            height: posters.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: 3
                color: parent.got ? (parent.legendary ? "#f3dd8e" : "#ead9ae") : "#1a1f2e"
                border.color: parent.got ? "#5a4325" : parent.legendary ? "#8a6a2a" : "#2c3550"
                border.width: parent.legendary ? 3 : 2
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 4
                    readonly property var a: parent.parent.modelData
                    readonly property bool got: parent.parent.got !== ""
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "WANTED"
                        color: parent.got ? "#3b2a16" : parent.parent.parent.legendary ? "#8a6a2a" : "#3a4258"
                        font { pixelSize: 24; weight: Font.Black; family: "serif"; letterSpacing: 2 }
                    }
                    Rectangle {   // where the portrait would be
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.55
                        height: 44
                        color: parent.got ? "#d8c28f" : "#141927"
                        border.color: parent.got ? "#5a4325" : "#2c3550"
                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.got ? "★" : "?"
                            color: parent.parent.got ? "#7a4e10" : "#3a4258"
                            font { pixelSize: 26; weight: Font.Black }
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: parent.a.title.toUpperCase()
                        color: parent.got ? "#3b2a16" : "#9aa0ad"
                        font { pixelSize: 13; weight: Font.Black; family: "serif" }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: parent.a.text
                        color: parent.got ? "#5a4325" : "#7a8090"
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Progress.formatBounty(parent.a.bounty)
                        color: parent.got ? "#3b2a16" : "#4a5370"
                        font { pixelSize: 16; weight: Font.Black; family: "serif" }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.got ? parent.parent.parent.got : (parent.a.reward ? "+" + Progress.format(parent.a.reward) : "")
                        color: parent.got ? "#7a4e10" : "#4a5370"
                        font.pixelSize: 11
                    }
                    Rectangle {   // a locked poster's progress
                        readonly property real f: Progress.posterFraction(parent.a, board.p)
                        visible: !parent.got && !!parent.a.count
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.8
                        height: 4
                        radius: 2
                        color: "#22283a"
                        Rectangle {
                            width: parent.width * parent.f
                            height: parent.height
                            radius: 2
                            color: "#ffd56b"
                        }
                    }
                    Text {
                        visible: !parent.got && !!parent.a.count
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Progress.posterProgress(parent.a, board.p)
                        color: "#7a8090"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: (board.seasonTab ? "A new season every month, a new event every week" : board.gotCount + " / " + board.shown.length + " posters on this board")
              + "   ·   ← →: switch board   ·   W or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}

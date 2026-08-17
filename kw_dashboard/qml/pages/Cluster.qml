import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "../"

// Main "at a glance" page: cluster header, CPU/MEM/PODS/NETWORK cards on the
// left, a live NODES table on the right. Lives on screen almost all the
// time, so every value that can move (percentages, rates, bar widths)
// eases into place instead of snapping.
Rectangle {
    id: page
    width: 1280
    height: 720
    color: Theme.bg

    // ---- helpers -----------------------------------------------------

    function numColor(pct) {
        if (pct >= 88) return Theme.crit
        if (pct >= 70) return Theme.warn
        return Theme.fg
    }

    function fmtRate(bytesPerSec) {
        var v = bytesPerSec || 0
        if (v >= 1e6) return (v / 1e6).toFixed(1) + " MB/s"
        if (v >= 1e3) return (v / 1e3).toFixed(1) + " KB/s"
        return Math.round(v) + " B/s"
    }

    readonly property string clusterState: bridge.stale ? "STALE"
        : (bridge.alerts && bridge.alerts.length > 0 ? "ALERT" : "OK")
    readonly property color clusterStateColor: clusterState === "OK" ? Theme.ok
        : (clusterState === "ALERT" ? Theme.crit : Theme.warn)

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: page.clockText = Qt.formatTime(new Date(), "hh:mm") }

    // ---- reusable bits -------------------------------------------------

    // Elevation used to come from QtGraphicalEffects' DropShadow applied via
    // layer.enabled/layer.effect on the Rectangle the card content lived
    // inside. That effect needs a GL shader; under the offscreen software
    // rendering backend it silently paints nothing, and because
    // layer.enabled turns the WHOLE item (including every child placed
    // inside it) into that one broken texture, the entire card body — not
    // just the shadow — vanished. Faked here instead with a plain solid
    // rectangle offset behind the card face: no shader, so content is
    // guaranteed to render regardless of backend. Content-bearing children
    // are declared directly inside CardBg (Item's default "data" property),
    // stacking on top of the shadow and face rectangles beneath them.
    component CardBg: Item {
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 6
            radius: 10
            color: "#40000000"
        }
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Theme.panel
            border.color: Theme.border
            border.width: 1
            antialiasing: true
        }
    }

    // Antialiased area sparkline: smoothed line + fading gradient fill,
    // driven straight off a bridge history array.
    component Sparkline: Canvas {
        id: spark
        property var history: []
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onHistoryChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var pts = history
            if (!pts || pts.length < 2) return

            var w = width, h = height
            var step = w / (pts.length - 1)

            function y(v) { return h - (Math.max(0, Math.min(100, v)) / 100) * h }

            var grad = ctx.createLinearGradient(0, 0, 0, h)
            grad.addColorStop(0, Qt.rgba(0.223, 0.529, 0.898, 0.34))
            grad.addColorStop(1, Qt.rgba(0.223, 0.529, 0.898, 0))

            ctx.beginPath()
            ctx.moveTo(0, y(pts[0]))
            for (var i = 1; i < pts.length; i++)
                ctx.lineTo(i * step, y(pts[i]))
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()

            ctx.beginPath()
            ctx.moveTo(0, y(pts[0]))
            for (var j = 1; j < pts.length; j++)
                ctx.lineTo(j * step, y(pts[j]))
            ctx.strokeStyle = Theme.accent
            ctx.lineWidth = 2.5
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
        }

        // Fewer than 2 points can't plot a line — an empty canvas reads as
        // "flat, unchanging real data" rather than "not enough data yet",
        // so say so explicitly instead of leaving it blank.
        Text {
            anchors.centerIn: parent
            visible: !spark.history || spark.history.length < 2
            text: "collecting…"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
        }
    }

    component MiniBar: Item {
        id: bar
        property real pct: 0
        property color fillColor: Theme.ok
        implicitWidth: 64
        implicitHeight: 8
        Rectangle { anchors.fill: parent; radius: 4; color: Theme.border }
        Rectangle {
            radius: 4
            color: bar.fillColor
            height: parent.height
            width: Math.max(0, Math.min(1, bar.pct / 100)) * parent.width
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    component MetricLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.small
        font.letterSpacing: 2
        color: Theme.fg
    }

    // ---- header ---------------------------------------------------------

    Rectangle {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 64
        color: Theme.panel
        border.color: Theme.border
        border.width: 0

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }

        RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Text {
                text: "KM01"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                font.letterSpacing: 1.5
                font.bold: true
                color: Theme.fgBright
            }
            Text {
                text: "k3s · " + bridge.nodes.length + (bridge.nodes.length === 1 ? " node · " : " nodes · ")
                    + bridge.podsRunning + (bridge.podsRunning === 1 ? " pod" : " pods")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                color: Theme.fg
            }
        }

        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 26

            RowLayout {
                spacing: 10
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: page.clusterStateColor
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: page.clusterState
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    font.letterSpacing: 1
                    color: page.clusterStateColor
                }
            }

            Text {
                text: page.clockText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                color: Theme.fgBright
            }
        }
    }

    // ---- content --------------------------------------------------------

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }
        anchors.margins: 16
        spacing: 12

        // -- left column: CPU + PODS --------------------------------------
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 274
            spacing: 12

            CardBg {
                id: cpuCard
                Layout.preferredWidth: 274
                Layout.preferredHeight: 280

                property real display: bridge.clusterCpu
                Behavior on display { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                MetricLabel { id: cpuLabel; text: "CPU"; anchors { left: parent.left; top: parent.top; margins: 18 } }
                Text {
                    anchors { left: parent.left; top: cpuLabel.bottom; leftMargin: 18; topMargin: 6 }
                    text: Math.round(cpuCard.display) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.big
                    color: Theme.fgBright
                }
                Text {
                    id: cpuPeak
                    anchors { left: parent.left; bottom: cpuSpark.top; leftMargin: 18; bottomMargin: 8 }
                    text: "peak " + Math.round(bridge.cpuPeak) + "% · 5 min"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    color: Theme.fg
                }
                Sparkline {
                    id: cpuSpark
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 100
                    history: bridge.cpuHistory
                }
            }

            CardBg {
                id: podsCard
                Layout.preferredWidth: 274
                Layout.fillHeight: true

                MetricLabel { id: podsLabel; text: "PODS"; anchors { left: parent.left; top: parent.top; margins: 18 } }
                Text {
                    anchors { left: parent.left; top: podsLabel.bottom; leftMargin: 18; topMargin: 6 }
                    text: bridge.podsRunning
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.big
                    color: Theme.fgBright
                }

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    spacing: 0

                    Repeater {
                        model: [
                            { label: "pending", value: bridge.pendingPods, warn: false },
                            { label: "unhealthy", value: bridge.unhealthyPods, warn: bridge.unhealthyPods > 0 },
                            { label: "restarts", value: bridge.totalRestarts, warn: false }
                        ]
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#222220" }
                            Text {
                                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: Theme.fg
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                                text: modelData.value
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: modelData.warn ? Theme.warn : Theme.fgBright
                            }
                        }
                    }
                }
            }
        }

        // -- second column: MEMORY + NETWORK -------------------------------
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 274
            spacing: 12

            CardBg {
                id: memCard
                Layout.preferredWidth: 274
                Layout.preferredHeight: 280

                property real display: bridge.clusterMem
                Behavior on display { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                MetricLabel { id: memLabel; text: "MEMORY"; anchors { left: parent.left; top: parent.top; margins: 18 } }
                Text {
                    anchors { left: parent.left; top: memLabel.bottom; leftMargin: 18; topMargin: 6 }
                    text: Math.round(memCard.display) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.big
                    color: Theme.fgBright
                }
                Text {
                    anchors { left: parent.left; bottom: memSpark.top; leftMargin: 18; bottomMargin: 8 }
                    text: "peak " + Math.round(bridge.memPeak) + "% · 5 min"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    color: Theme.fg
                }
                Sparkline {
                    id: memSpark
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 100
                    history: bridge.memHistory
                }
            }

            CardBg {
                id: netCard
                Layout.preferredWidth: 274
                Layout.fillHeight: true

                readonly property real maxRate: Math.max(bridge.netRx, bridge.netTx, 1) * 1.25

                MetricLabel { id: netLabel; text: "NETWORK"; anchors { left: parent.left; top: parent.top; margins: 18 } }

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: netLabel.bottom; margins: 18 }
                    spacing: 10

                    Text { text: "RX"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text {
                        text: page.fmtRate(bridge.netRx)
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        color: Theme.fgBright
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.border
                        Rectangle {
                            radius: 4
                            height: parent.height
                            width: Math.max(0, Math.min(1, bridge.netRx / netCard.maxRate)) * parent.width
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    Item { Layout.preferredHeight: 6 }

                    Text { text: "TX"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text {
                        text: page.fmtRate(bridge.netTx)
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        color: Theme.fgBright
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.border
                        Rectangle {
                            radius: 4
                            height: parent.height
                            width: Math.max(0, Math.min(1, bridge.netTx / netCard.maxRate)) * parent.width
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // -- NODES table --------------------------------------------------
        CardBg {
            id: nodesCard
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property int readyCount: {
                var c = 0
                for (var i = 0; i < bridge.nodes.length; i++)
                    if (bridge.nodes[i].ready) c++
                return c
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20

                    Text {
                        text: "NODES"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.small
                        font.letterSpacing: 2
                        color: Theme.fgBright
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: nodesCard.readyCount + " / " + bridge.nodes.length + " ready"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.small
                        color: Theme.fg
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 8

                    Text { Layout.preferredWidth: 132; text: "NODE"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text { Layout.preferredWidth: 112; text: "CPU"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text { Layout.preferredWidth: 112; text: "MEM"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text { Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight; text: "°C"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text { Layout.preferredWidth: 88; horizontalAlignment: Text.AlignRight; text: "PODS"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                    Text { Layout.preferredWidth: 96; horizontalAlignment: Text.AlignRight; text: "STATE"; font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: Theme.fg }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#222220" }

                ListView {
                    id: nodesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: bridge.nodes
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: row
                        width: nodesList.width
                        height: 66

                        readonly property var node: modelData
                        readonly property bool isDown: !node.ready
                        readonly property color sevColor: isDown ? Theme.crit : Theme.stateColor(node.worstPct)
                        readonly property bool isWarnRow: !isDown && sevColor === Theme.warn
                        readonly property bool isCritRow: isDown || sevColor === Theme.crit

                        Rectangle {
                            anchors.fill: parent
                            color: row.isCritRow ? Qt.rgba(1, 0.549, 0.549, 0.07)
                                : (row.isWarnRow ? Qt.rgba(0.980, 0.698, 0.098, 0.05) : "transparent")
                        }
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 4
                            visible: row.isCritRow || row.isWarnRow
                            color: row.isCritRow ? Theme.crit : Theme.warn
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#1c1c1b" }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 8

                            Text {
                                Layout.preferredWidth: 132
                                text: row.node.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: row.isDown ? Theme.crit : Theme.fgBright
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                Layout.preferredWidth: 112
                                spacing: 10
                                visible: !row.isDown
                                MiniBar { pct: row.node.cpuPct; fillColor: Theme.stateColor(row.node.cpuPct) }
                                Text { text: Math.round(row.node.cpuPct); font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: page.numColor(row.node.cpuPct) }
                            }
                            Text {
                                Layout.preferredWidth: 112
                                visible: row.isDown
                                text: "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: Theme.fg
                            }

                            RowLayout {
                                Layout.preferredWidth: 112
                                spacing: 10
                                visible: !row.isDown
                                MiniBar { pct: row.node.memPct; fillColor: Theme.stateColor(row.node.memPct) }
                                Text { text: Math.round(row.node.memPct); font.family: Theme.fontFamily; font.pixelSize: Theme.small; color: page.numColor(row.node.memPct) }
                            }
                            Text {
                                Layout.preferredWidth: 112
                                visible: row.isDown
                                text: "—"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: Theme.fg
                            }

                            Text {
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignRight
                                text: (row.isDown || row.node.tempC < 0) ? "—" : Math.round(row.node.tempC)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: Theme.fg
                            }
                            Text {
                                Layout.preferredWidth: 88
                                horizontalAlignment: Text.AlignRight
                                text: row.node.pods
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: row.isDown ? Theme.fg : Theme.fgBright
                            }
                            Text {
                                Layout.preferredWidth: 96
                                horizontalAlignment: Text.AlignRight
                                text: row.isDown ? "DOWN" : (row.node.cordoned ? "CORD" : "ready")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.small
                                color: row.isDown ? Theme.crit : (row.node.cordoned ? Theme.warn : Theme.fg)
                            }
                        }

                        TapHandler {
                            onTapped: bridge.pushView("nodeDetail", { "node": row.node.name })
                        }
                    }
                }
            }
        }
    }
}

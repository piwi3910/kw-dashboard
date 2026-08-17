import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../"

// Cluster overview: a Grafana-style observability panel grid (design 5a).
// Supersedes the earlier console-grid layout. Panel geometry mirrors
// 5a.html's pixel grid exactly (it sums to precisely 1280x720); internal
// type sizes are scaled up past 5a's ~11-13px labels to this project's
// legibility floor, which means fewer visible rows in the dense tables —
// see the task report for exact numbers.
Rectangle {
    id: page
    width: 1280
    height: 720
    color: Theme.bg

    // ---- bridge-optional fields (guarded — may not exist yet) -----------
    readonly property var nodeCpuSeries: bridge.nodeCpuSeries || []
    readonly property var netRxSeries: bridge.netRxSeries || []
    readonly property var netTxSeries: bridge.netTxSeries || []
    readonly property string timeRangeLabel: bridge.timeRangeLabel || "Last 1 hour"
    readonly property int alertsFiring: (bridge.alertsFiring !== undefined && bridge.alertsFiring !== null)
        ? bridge.alertsFiring : ((bridge.alerts || []).length)

    readonly property var nodes: bridge.nodes || []
    readonly property int readyCount: {
        var c = 0
        for (var i = 0; i < nodes.length; i++) if (nodes[i].ready) c++
        return c
    }
    readonly property int notReadyCount: nodes.length - readyCount
    readonly property int cordonedCount: {
        var c = 0
        for (var i = 0; i < nodes.length; i++) if (nodes[i].cordoned) c++
        return c
    }

    // warn/crit thresholds used by the gauge and the "over threshold" tint
    // in the CPU-by-node legend table — kept local to this page since they
    // are 5a's own gauge markers (70/85), distinct from Theme.stateColor's
    // general 70/88 split used elsewhere in the app.
    readonly property real warnThreshold: 70
    readonly property real critThreshold: 85

    function fmtRate(bytesPerSec) {
        var v = bytesPerSec || 0
        if (v >= 1e6) return (v / 1e6).toFixed(1) + " MB/s"
        if (v >= 1e3) return (v / 1e3).toFixed(1) + " KB/s"
        return Math.round(v) + " B/s"
    }

    function fmtRateNoUnit(bytesPerSec) {
        var v = bytesPerSec || 0
        if (v >= 1e6) return (v / 1e6).toFixed(1)
        if (v >= 1e3) return (v / 1e3).toFixed(1)
        return Math.round(v).toString()
    }

    function seriesColor(i) {
        var c = Theme.seriesColors
        return c[i % c.length]
    }

    function fmtTime(ts) {
        if (ts === undefined || ts === null) return ""
        var ms = ts > 1e12 ? ts : ts * 1000
        return Qt.formatDateTime(new Date(ms), "hh:mm")
    }

    // ---- shared bits ------------------------------------------------------

    // Elevation would normally come from a QtGraphicalEffects DropShadow via
    // layer.enabled — that shader can't run under the offscreen/software
    // backend and layer.enabled blanks the WHOLE subtree when it fails, so
    // panels are a plain bordered rectangle instead (no shader, guaranteed
    // to render).
    component PanelBg: Rectangle {
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: 3
        clip: true
    }

    // Panel with a titled header strip (used by the four "real" panels;
    // the stat row cards skip this and lay out their own compact content).
    component Panel: PanelBg {
        id: panel
        property string title: ""
        property string subtitle: ""
        readonly property real headerH: 30
        default property alias content: body.data

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: panel.headerH
            color: "transparent"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.bgAlt }
            Text {
                text: panel.title
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelTitle
                font.bold: true
            }
            Text {
                text: panel.subtitle
                visible: panel.subtitle.length > 0
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
        }
        Item {
            id: body
            clip: true
            anchors {
                left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                topMargin: panel.headerH; leftMargin: 10; rightMargin: 10; bottomMargin: 6
            }
        }
    }

    component MiniBar: Item {
        id: bar
        property real pct: 0
        property color fillColor: Theme.ok
        implicitWidth: 90
        implicitHeight: 10
        Rectangle { anchors.fill: parent; radius: 3; color: Theme.border }
        Rectangle {
            radius: 3
            color: bar.fillColor
            height: parent.height
            width: Math.max(0, Math.min(1, bar.pct / 100)) * parent.width
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    // Single-series area sparkline used by the stat cards. Handles empty,
    // single-point and all-equal-value histories: an all-equal history is
    // drawn as a flat line through the MIDDLE of the 0-100 band rather than
    // pinned to the bottom, since the value it represents (a percentage) is
    // never renormalised against its own min/max — it always maps directly
    // onto the fixed 0-100 axis, so a genuinely-zero series is the only one
    // that ever touches the bottom.
    component Sparkline: Canvas {
        id: spark
        property var history: []
        property color lineColor: Theme.ok
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onHistoryChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onLineColorChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var pts = history
            if (!pts || pts.length < 2) return

            var w = width, h = height
            function y(v) { return h - (Math.max(0, Math.min(100, v)) / 100) * h }
            var step = pts.length > 1 ? w / (pts.length - 1) : w

            var grad = ctx.createLinearGradient(0, 0, 0, h)
            var c = spark.lineColor
            grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.32))
            grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0))

            ctx.beginPath()
            ctx.moveTo(0, y(pts[0]))
            for (var i = 1; i < pts.length; i++) ctx.lineTo(i * step, y(pts[i]))
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()

            ctx.beginPath()
            ctx.moveTo(0, y(pts[0]))
            for (var j = 1; j < pts.length; j++) ctx.lineTo(j * step, y(pts[j]))
            ctx.strokeStyle = spark.lineColor
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
        }

        Text {
            anchors.centerIn: parent
            visible: !spark.history || spark.history.length < 2
            text: "collecting…"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }

    // ---- breadcrumb bar (0-44) --------------------------------------------

    Rectangle {
        id: breadcrumb
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 44
        color: Theme.bgAlt
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }

        RowLayout {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 8
            Text { text: "kw"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { text: "kubernetes"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { text: "cluster overview"; color: Theme.fgBright; font.bold: true; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }

        // Display-only chips: the bridge exposes a fixed time-range label
        // and refresh interval; tapping them intentionally does nothing —
        // building a working picker was explicitly out of scope for this
        // page.
        RowLayout {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 6

            Rectangle {
                implicitWidth: chipTime.implicitWidth + 20; implicitHeight: 28
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipTime; anchors.centerIn: parent; text: "⏱ " + page.timeRangeLabel; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle {
                implicitWidth: chipRefresh.implicitWidth + 20; implicitHeight: 28
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipRefresh; anchors.centerIn: parent; text: "⟳ 10s"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle {
                implicitWidth: 34; implicitHeight: 28
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "−"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
        }
    }

    // ---- filter row (44-82) ------------------------------------------------

    Rectangle {
        id: filterBar
        anchors { left: parent.left; right: parent.right; top: breadcrumb.bottom }
        height: 38
        color: Theme.bg
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.panel }

        RowLayout {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 18

            Repeater {
                model: [
                    { label: "cluster", value: "km01" },
                    { label: "namespace", value: "All" },
                    { label: "node", value: "All" }
                ]
                delegate: RowLayout {
                    spacing: 7
                    Text { text: modelData.label; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Rectangle {
                        implicitWidth: chipVal.implicitWidth + 18; implicitHeight: 26
                        color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                        Text { id: chipVal; anchors.centerIn: parent; text: modelData.value + "  ▾"; color: Theme.fgBright; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    }
                }
            }
        }

        RowLayout {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle { width: 8; height: 8; radius: 4; color: Theme.crit }
            Text {
                text: page.alertsFiring + (page.alertsFiring === 1 ? " alert firing" : " alerts firing")
                color: Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
        }
    }

    // ---- stat row (90-182) -------------------------------------------------

    Item {
        id: statRow
        anchors { left: parent.left; right: parent.right; top: filterBar.bottom; topMargin: 8; leftMargin: 8; rightMargin: 8 }
        height: 92

        readonly property real colW: (width - 3 * 8) / 4

        // CPU utilisation
        PanelBg {
            x: 0; width: statRow.colW; height: 92
            readonly property real display: bridge.clusterCpu
            readonly property color c: Theme.stateColor(display)
            Text {
                id: cpuLbl
                text: "CPU utilisation"
                anchors { left: parent.left; top: parent.top; margins: 8 }
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                anchors { left: parent.left; top: cpuLbl.bottom; leftMargin: 8; topMargin: 2 }
                text: parent.display.toFixed(1) + "%"
                color: parent.c
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }
            Sparkline {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 26
                history: bridge.cpuHistory
                lineColor: parent.c
            }
        }

        // Memory utilisation
        PanelBg {
            x: statRow.colW + 8; width: statRow.colW; height: 92
            readonly property real display: bridge.clusterMem
            readonly property color c: Theme.stateColor(display)
            Text {
                id: memLbl
                text: "Memory utilisation"
                anchors { left: parent.left; top: parent.top; margins: 8 }
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                anchors { left: parent.left; top: memLbl.bottom; leftMargin: 8; topMargin: 2 }
                text: parent.display.toFixed(1) + "%"
                color: parent.c
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }
            Sparkline {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 26
                history: bridge.memHistory
                lineColor: parent.c
            }
        }

        // Pods running
        PanelBg {
            x: (statRow.colW + 8) * 2; width: statRow.colW; height: 92
            Text {
                id: podsLbl
                text: "Pods running"
                anchors { left: parent.left; top: parent.top; margins: 8 }
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                anchors { left: parent.left; top: podsLbl.bottom; leftMargin: 8; topMargin: 2 }
                text: bridge.podsRunning
                color: Theme.fgBright
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }
            Text {
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                text: bridge.pendingPods + " pending" + (bridge.unhealthyPods > 0 ? " · " + bridge.unhealthyPods + " failing" : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
                // Whole caption reads in crit once there's a failure — the
                // word "failing" is always present in the string, so colour
                // is never the only signal.
                color: bridge.unhealthyPods > 0 ? Theme.crit : Theme.dim
            }
        }

        // Nodes ready — the mockup's row of 8 tiny colour-only chips would
        // be hue-alone state at ~4px wide, well under the legibility floor
        // and impossible to pair with a label at that size. Replaced with a
        // textual breakdown ("N ready" / "N not ready") that carries the
        // same information with words, not just colour.
        PanelBg {
            x: (statRow.colW + 8) * 3; width: statRow.colW; height: 92
            readonly property color c: page.notReadyCount > 0 ? Theme.crit : (page.cordonedCount > 0 ? Theme.warn : Theme.ok)
            Text {
                id: nodesLbl
                text: "Nodes ready"
                anchors { left: parent.left; top: parent.top; margins: 8 }
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                anchors { left: parent.left; top: nodesLbl.bottom; leftMargin: 8; topMargin: 2 }
                text: page.readyCount + " / " + page.nodes.length
                color: parent.c
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                spacing: 6
                Text { text: page.readyCount + " ready"; color: Theme.ok; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                Text {
                    visible: page.notReadyCount + page.cordonedCount > 0
                    text: "· " + (page.notReadyCount + page.cordonedCount) + " not ready"
                    color: page.notReadyCount > 0 ? Theme.crit : Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
            }
        }
    }

    // ---- row 2: CPU-by-node chart + Cluster CPU gauge (190-466) ----------

    Item {
        id: row2
        anchors { left: parent.left; right: parent.right; top: statRow.bottom; topMargin: 8; leftMargin: 8; rightMargin: 8 }
        height: 276

        Panel {
            id: cpuChartPanel
            x: 0; width: 946; height: 276
            title: "CPU usage by node"

            readonly property var series: page.nodeCpuSeries
            readonly property bool hasData: series.length > 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 6

                // -- chart --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 106
                    spacing: 4

                    Item {
                        id: yAxis
                        Layout.preferredWidth: 42
                        Layout.fillHeight: true
                        Repeater {
                            model: ["100%", "75%", "50%", "25%", "0%"]
                            delegate: Text {
                                width: yAxis.width
                                // fractional y so each label lines up with the
                                // matching gridline the canvas draws at h*g/4
                                y: (index / 4) * (yAxis.height - height)
                                text: modelData
                                color: Theme.dimmer
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.tableText
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    Canvas {
                        id: chartCanvas
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        antialiasing: true
                        renderStrategy: Canvas.Cooperative

                        readonly property var series: cpuChartPanel.series
                        onSeriesChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width, h = height

                            // gridlines
                            ctx.strokeStyle = Theme.border
                            ctx.lineWidth = 1
                            for (var g = 0; g <= 4; g++) {
                                var gy = h * g / 4
                                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                            }

                            // dashed reference threshold (visual reference at 75%,
                            // matching the design's dashed line — not tied to a
                            // specific alert rule the bridge doesn't expose).
                            var ty = h * (1 - 75 / 100)
                            ctx.save()
                            ctx.strokeStyle = Theme.crit
                            ctx.globalAlpha = 0.5
                            ctx.setLineDash([5, 5])
                            ctx.beginPath(); ctx.moveTo(0, ty); ctx.lineTo(w, ty); ctx.stroke()
                            ctx.restore()

                            var s = chartCanvas.series
                            if (!s || s.length === 0) return

                            function yOf(v) { return h - (Math.max(0, Math.min(100, v)) / 100) * h }

                            for (var i = 0; i < s.length; i++) {
                                var pts = s[i].points || []
                                ctx.strokeStyle = page.seriesColor(i)
                                ctx.lineWidth = 2
                                ctx.lineJoin = "round"
                                ctx.lineCap = "round"
                                if (pts.length === 0) {
                                    continue
                                } else if (pts.length === 1) {
                                    var yy = yOf(pts[0][1])
                                    ctx.beginPath(); ctx.moveTo(w * 0.5 - 8, yy); ctx.lineTo(w * 0.5 + 8, yy); ctx.stroke()
                                } else {
                                    var step = w / (pts.length - 1)
                                    ctx.beginPath()
                                    ctx.moveTo(0, yOf(pts[0][1]))
                                    for (var j = 1; j < pts.length; j++) ctx.lineTo(j * step, yOf(pts[j][1]))
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: !cpuChartPanel.hasData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "no data"
                    color: Theme.dimmer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.glance
                }

                // -- x-axis time labels --
                RowLayout {
                    visible: cpuChartPanel.hasData
                    Layout.fillWidth: true
                    Layout.leftMargin: 46
                    Layout.preferredHeight: 16

                    readonly property var firstPts: (cpuChartPanel.series.length > 0 ? (cpuChartPanel.series[0].points || []) : [])
                    readonly property real t0: firstPts.length > 0 ? firstPts[0][0] : 0
                    readonly property real t1: firstPts.length > 0 ? firstPts[firstPts.length - 1][0] : 0

                    Repeater {
                        model: 5
                        delegate: Text {
                            Layout.fillWidth: true
                            horizontalAlignment: index === 0 ? Text.AlignLeft : (index === 4 ? Text.AlignRight : Text.AlignHCenter)
                            readonly property real t: parent.t0 + (parent.t1 - parent.t0) * (index / 4)
                            text: page.fmtTime(t)
                            color: Theme.dimmer
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                    }
                }

                // -- legend header --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    Text { Layout.fillWidth: true; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: "min"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: "max"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }

                ListView {
                    id: legendList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: cpuChartPanel.series
                    delegate: Item {
                        width: legendList.width
                        height: 26
                        readonly property bool over: modelData.max !== undefined && modelData.max >= page.warnThreshold

                        Rectangle { anchors.fill: parent; color: over ? Qt.rgba(0.910, 0.702, 0.255, 0.08) : "transparent" }

                        RowLayout {
                            anchors.fill: parent
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                RowLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 7
                                    Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(index) }
                                    Text { text: modelData.name || ""; color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                                }
                            }
                            Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: (modelData.min !== undefined ? modelData.min.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: (modelData.max !== undefined ? modelData.max.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: (modelData.mean !== undefined ? modelData.mean.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: (modelData.last !== undefined ? modelData.last.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        }
                    }
                }
            }
        }

        // -- Cluster CPU gauge --
        Panel {
            id: gaugePanel
            x: 954; width: 310; height: 276
            title: "Cluster CPU"

            readonly property real value: Math.max(0, Math.min(100, bridge.clusterCpu))
            readonly property color valColor: value >= page.critThreshold ? Theme.crit
                : (value >= page.warnThreshold ? Theme.warn : Theme.ok)

            Item {
                id: gaugeArea
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                width: 200; height: 200

                Canvas {
                    id: gaugeCanvas
                    anchors.fill: parent
                    antialiasing: true
                    renderStrategy: Canvas.Cooperative

                    readonly property real value: gaugePanel.value
                    readonly property color valColor: gaugePanel.valColor
                    onValueChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2, cy = height / 2
                        var r = Math.min(width, height) / 2 - 14
                        var sw = 16
                        var startA = 135 * Math.PI / 180
                        var endA = 405 * Math.PI / 180
                        var valA = startA + (endA - startA) * (gaugeCanvas.value / 100)

                        ctx.lineCap = "round"

                        ctx.beginPath()
                        ctx.arc(cx, cy, r, startA, endA, false)
                        ctx.strokeStyle = Theme.border
                        ctx.lineWidth = sw
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.arc(cx, cy, r, startA, valA, false)
                        ctx.strokeStyle = gaugeCanvas.valColor
                        ctx.lineWidth = sw
                        ctx.stroke()

                        // threshold ticks
                        function tick(pct, color) {
                            var a = startA + (endA - startA) * (pct / 100)
                            var x1 = cx + Math.cos(a) * (r - sw / 2 - 3)
                            var y1 = cy + Math.sin(a) * (r - sw / 2 - 3)
                            var x2 = cx + Math.cos(a) * (r + sw / 2 + 3)
                            var y2 = cy + Math.sin(a) * (r + sw / 2 + 3)
                            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2)
                            ctx.strokeStyle = color; ctx.lineWidth = 3; ctx.stroke()
                        }
                        tick(page.warnThreshold, Theme.warn)
                        tick(page.critThreshold, Theme.crit)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: gaugePanel.value.toFixed(1)
                        color: Theme.fgBright
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.gaugeNumber
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "percent"
                        color: Theme.dim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.tableText
                    }
                }
            }

            RowLayout {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                Text { text: "0"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Item { Layout.fillWidth: true }
                Text { text: page.warnThreshold.toFixed(0) + " warn"; color: Theme.warn; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Item { Layout.fillWidth: true }
                Text { text: page.critThreshold.toFixed(0) + " crit"; color: Theme.crit; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Item { Layout.fillWidth: true }
                Text { text: "100"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            }
        }
    }

    // ---- row 3: Node status table + Network throughput (474-712) ---------

    Item {
        id: row3
        anchors { left: parent.left; right: parent.right; top: row2.bottom; topMargin: 8; leftMargin: 8; rightMargin: 8 }
        height: 238

        Panel {
            id: nodeTablePanel
            x: 0; width: 946; height: 238
            title: "Node status"
            subtitle: page.nodes.length + " rows"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    Text { Layout.preferredWidth: 150; text: "node"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 96; text: "state"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.fillWidth: true; text: "cpu"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.fillWidth: true; text: "memory"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; text: "temp"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; text: "pods"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "uptime"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bgAlt }

                // Touch-target decision: 5a's node rows are ~23px tall,
                // far below this panel's 60px touch-target floor. Rather
                // than ship an untappably-small hit target or fake a
                // bigger one that visually overlaps neighbours, each row
                // IS the full 60px tap target and the table scrolls — you
                // see fewer rows at once (see task report) but every row
                // you can see is fully, honestly tappable.
                ListView {
                    id: nodeList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: page.nodes

                    delegate: Item {
                        id: nodeRow
                        width: nodeList.width
                        height: Theme.touchMin

                        readonly property var node: modelData
                        readonly property string state: !node.ready ? "notready" : (node.cordoned ? "cordon" : "ready")
                        readonly property color stateColor: state === "notready" ? Theme.crit : (state === "cordon" ? Theme.warn : Theme.ok)

                        Rectangle {
                            anchors.fill: parent
                            color: nodeRow.state === "notready" ? Qt.rgba(0.890, 0.416, 0.416, 0.07)
                                : (nodeRow.state === "cordon" ? Qt.rgba(0.910, 0.702, 0.255, 0.05) : "transparent")
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.bgAlt }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 4

                            Text {
                                Layout.preferredWidth: 150
                                text: node.name
                                color: nodeRow.state === "notready" ? Theme.crit : Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.tableText
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.preferredWidth: 96
                                Layout.fillHeight: true
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: statePill.implicitWidth + 14; implicitHeight: 24
                                    radius: 3
                                    color: Qt.rgba(nodeRow.stateColor.r, nodeRow.stateColor.g, nodeRow.stateColor.b, 0.16)
                                    Text { id: statePill; anchors.centerIn: parent; text: nodeRow.state; color: nodeRow.stateColor; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: nodeRow.state !== "notready"
                                MiniBar { pct: node.cpuPct; fillColor: Theme.stateColor(node.cpuPct) }
                                Text { text: Math.round(node.cpuPct); color: node.cpuPct >= 70 ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: nodeRow.state === "notready"
                                text: "no data"
                                color: Theme.dimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.tableText
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: nodeRow.state !== "notready"
                                MiniBar { pct: node.memPct; fillColor: Theme.stateColor(node.memPct) }
                                Text { text: Math.round(node.memPct); color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: nodeRow.state === "notready"
                                text: "no data"
                                color: Theme.dimmer
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.tableText
                            }

                            Text {
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignRight
                                text: (nodeRow.state === "notready" || node.tempC < 0) ? "—" : Math.round(node.tempC) + "°"
                                color: node.tempC >= 60 ? Theme.warn : Theme.fgMuted
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.tableText
                            }
                            Text {
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignRight
                                text: node.pods
                                color: Theme.fgMuted
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.tableText
                            }
                            Text {
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignRight
                                text: (node.uptimeDays === null || node.uptimeDays === undefined) ? "—" : Math.round(node.uptimeDays) + "d"
                                color: nodeRow.state === "notready" ? Theme.crit : Theme.dim
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.tableText
                            }
                        }

                        TapHandler {
                            onTapped: bridge.pushView("nodeDetail", { "node": nodeRow.node.name })
                        }
                    }
                }
            }
        }

        // -- Network throughput --
        Panel {
            id: netPanel
            x: 954; width: 310; height: 238
            title: "Network throughput"

            readonly property var rxSeries: page.netRxSeries
            readonly property var txSeries: page.netTxSeries
            readonly property bool hasData: rxSeries.length > 0 || txSeries.length > 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 6

                Canvas {
                    id: netCanvas
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    antialiasing: true
                    renderStrategy: Canvas.Cooperative

                    readonly property var rx: netPanel.rxSeries
                    readonly property var tx: netPanel.txSeries
                    onRxChanged: requestPaint()
                    onTxChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var w = width, h = height

                        ctx.strokeStyle = Theme.border
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(0, h / 3); ctx.lineTo(w, h / 3); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(0, 2 * h / 3); ctx.lineTo(w, 2 * h / 3); ctx.stroke()

                        var rxPts = (netCanvas.rx.length > 0 ? (netCanvas.rx[0].points || []) : [])
                        var txPts = (netCanvas.tx.length > 0 ? (netCanvas.tx[0].points || []) : [])
                        if (rxPts.length === 0 && txPts.length === 0) return

                        var maxV = 1
                        var all = rxPts.concat(txPts)
                        for (var k = 0; k < all.length; k++) maxV = Math.max(maxV, all[k][1])
                        maxV *= 1.15

                        function draw(pts, color) {
                            if (pts.length === 0) return
                            function yOf(v) { return h - (Math.max(0, v) / maxV) * h }
                            ctx.strokeStyle = color
                            ctx.lineWidth = 2
                            ctx.lineJoin = "round"
                            if (pts.length === 1) {
                                var yy = yOf(pts[0][1])
                                ctx.beginPath(); ctx.moveTo(w * 0.5 - 8, yy); ctx.lineTo(w * 0.5 + 8, yy); ctx.stroke()
                                return
                            }
                            var step = w / (pts.length - 1)
                            ctx.beginPath()
                            ctx.moveTo(0, yOf(pts[0][1]))
                            for (var j = 1; j < pts.length; j++) ctx.lineTo(j * step, yOf(pts[j][1]))
                            ctx.stroke()
                        }
                        draw(rxPts, page.seriesColor(1))
                        draw(txPts, page.seriesColor(3))
                    }
                }

                Text {
                    visible: !netPanel.hasData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "no history · " + page.fmtRate(bridge.netRx) + " rx, " + page.fmtRate(bridge.netTx) + " tx"
                    color: Theme.dimmer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Text { Layout.fillWidth: true; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 76; horizontalAlignment: Text.AlignRight; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    RowLayout { Layout.fillWidth: true; spacing: 7; Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(1) } Text { text: "rx"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText } }
                    Text { Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: netPanel.rxSeries.length > 0 ? page.fmtRateNoUnit(netPanel.rxSeries[0].mean) : "—"; color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 76; horizontalAlignment: Text.AlignRight; text: page.fmtRate(netPanel.rxSeries.length > 0 ? netPanel.rxSeries[0].last : bridge.netRx); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    RowLayout { Layout.fillWidth: true; spacing: 7; Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(3) } Text { text: "tx"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText } }
                    Text { Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: netPanel.txSeries.length > 0 ? page.fmtRateNoUnit(netPanel.txSeries[0].mean) : "—"; color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 76; horizontalAlignment: Text.AlignRight; text: page.fmtRate(netPanel.txSeries.length > 0 ? netPanel.txSeries[0].last : bridge.netTx); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }
            }
        }
    }
}

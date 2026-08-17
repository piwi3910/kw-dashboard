import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../"

// Cluster overview: a Grafana-style observability panel grid (design 5a).
// Every panel lays out its content with Column/RowLayout (never absolute
// anchors for stacked text) so nothing can visually collide, and every
// panel's root Rectangle clips its own children to its own bounds.
//
// Grid is NOT 5a's literal pixel grid any more: fitting all 8 node rows at
// a usable (~33px) height inside a fixed 720px page required reclaiming
// space from the chrome (breadcrumb/filter bars) and trimming the hero
// chart + gauge row. See the row-3 section below for the exact numbers.
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
    // Same source (node.ready) feeds BOTH the big ratio and the textual
    // breakdown below it, so they can never disagree.
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

    // ---- shared bits ------------------------------------------------------

    // Elevation would normally come from a QtGraphicalEffects DropShadow via
    // layer.enabled — that shader can't run under the offscreen/software
    // backend and layer.enabled blanks the WHOLE subtree when it fails, so
    // panels are a plain bordered rectangle instead (no shader, guaranteed
    // to render). clip: true so nothing a panel draws can ever bleed past
    // its own edge into a neighbour.
    component PanelBg: Rectangle {
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: 3
        clip: true
    }

    // Panel with a titled header strip. Title row, a 1px separator and the
    // content area are three siblings inside ONE ColumnLayout, so the
    // content area can never be positioned on top of the title — that was
    // the previous (buggy) version's mistake, where the header was a
    // separately-anchored Rectangle and the body an independently-anchored
    // Item with a hand-computed topMargin.
    component Panel: PanelBg {
        id: panel
        property string title: ""
        property string subtitle: ""
        default property alias content: contentArea.data

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: panel.title
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.panelTitle
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    visible: panel.subtitle.length > 0
                    text: panel.subtitle
                    color: Theme.dimmer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bgAlt }
            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 4
                Layout.bottomMargin: 6
            }
        }
    }

    // Stat-row card: label / big value / free bottom slot, stacked via
    // ColumnLayout so the value and whatever goes in the bottom slot
    // (sparkline or caption text) can never be drawn on top of each other.
    component StatCard: PanelBg {
        id: card
        property string label: ""
        property string valueText: ""
        property color valueColor: Theme.fgBright
        default property alias bottomContent: bottomSlot.data

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Text {
                Layout.preferredHeight: 22
                text: card.label
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                Layout.preferredHeight: 38
                text: card.valueText
                color: card.valueColor
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }
            Item {
                id: bottomSlot
                Layout.fillWidth: true
                Layout.fillHeight: true
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
    // drawn as a flat line through the position its value actually maps to
    // on the fixed 0-100 axis (never renormalised against its own min/max),
    // so only a genuinely-zero series ever touches the bottom.
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

    // ==== chrome: breadcrumb (0-40) + filter (40-74) ========================

    Rectangle {
        id: breadcrumb
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 40
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
        // and refresh interval; tapping them intentionally does nothing.
        RowLayout {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 6

            Rectangle {
                implicitWidth: chipTime.implicitWidth + 20; implicitHeight: 26
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipTime; anchors.centerIn: parent; text: "⏱ " + page.timeRangeLabel; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle {
                implicitWidth: chipRefresh.implicitWidth + 20; implicitHeight: 26
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipRefresh; anchors.centerIn: parent; text: "⟳ 10s"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle {
                implicitWidth: 32; implicitHeight: 26
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "−"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
        }
    }

    Rectangle {
        id: filterBar
        anchors { left: parent.left; right: parent.right; top: breadcrumb.bottom }
        height: 34
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
                        implicitWidth: chipVal.implicitWidth + 18; implicitHeight: 24
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

    // ==== stat row (80-176) =================================================

    Item {
        id: statRow
        anchors { left: parent.left; right: parent.right; top: filterBar.bottom; topMargin: 6; leftMargin: 8; rightMargin: 8 }
        height: 96

        readonly property real colW: (width - 3 * 8) / 4

        // CPU utilisation
        StatCard {
            id: cpuCard
            x: 0; width: statRow.colW; height: 96
            readonly property real display: bridge.clusterCpu
            readonly property color c: Theme.stateColor(display)
            label: "CPU utilisation"
            valueText: display.toFixed(1) + "%"
            valueColor: c
            Sparkline { anchors.fill: parent; history: bridge.cpuHistory; lineColor: cpuCard.c }
        }

        // Memory utilisation
        StatCard {
            id: memCard
            x: statRow.colW + 8; width: statRow.colW; height: 96
            readonly property real display: bridge.clusterMem
            readonly property color c: Theme.stateColor(display)
            label: "Memory utilisation"
            valueText: display.toFixed(1) + "%"
            valueColor: c
            Sparkline { anchors.fill: parent; history: bridge.memHistory; lineColor: memCard.c }
        }

        // Pods running
        StatCard {
            x: (statRow.colW + 8) * 2; width: statRow.colW; height: 96
            label: "Pods running"
            valueText: String(bridge.podsRunning)
            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: bridge.pendingPods + " pending" + (bridge.unhealthyPods > 0 ? " · " + bridge.unhealthyPods + " failing" : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
                // Whole caption reads in crit once there's a failure — the
                // word "failing" is always present in the string, so
                // colour is never the only signal.
                color: bridge.unhealthyPods > 0 ? Theme.crit : Theme.dim
            }
        }

        // Nodes ready — the mockup's row of 8 tiny colour-only chips would
        // be hue-alone state at ~4px wide, well under the legibility floor
        // and impossible to pair with a label at that size. Replaced with
        // a textual breakdown, computed from the SAME per-node fields as
        // the ratio above it, so the two can never contradict each other.
        StatCard {
            x: (statRow.colW + 8) * 3; width: statRow.colW; height: 96
            readonly property color c: page.notReadyCount > 0 ? Theme.crit : (page.cordonedCount > 0 ? Theme.warn : Theme.ok)
            label: "Nodes ready"
            valueText: page.readyCount + " / " + page.nodes.length
            valueColor: c
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 6
                Text { text: page.readyCount + " ready"; color: Theme.ok; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                Text {
                    visible: page.notReadyCount > 0
                    text: "· " + page.notReadyCount + " not ready"
                    color: Theme.crit
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    visible: page.cordonedCount > 0
                    text: "· " + page.cordonedCount + " cordoned"
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
            }
        }
    }

    // ==== row 2: CPU-by-node chart + Cluster CPU gauge (182-384) ===========

    Item {
        id: row2
        anchors { left: parent.left; right: parent.right; top: statRow.bottom; topMargin: 6; leftMargin: 8; rightMargin: 8 }
        height: 202

        Panel {
            id: cpuChartPanel
            x: 0; width: 946; height: 202
            title: "CPU usage by node"

            readonly property var series: page.nodeCpuSeries
            readonly property bool hasData: series.length > 0
            // Auto-range the y-axis to the data instead of a fixed 0-100%
            // scale, which crushed normal (single-digit-percent) load onto
            // the bottom edge. Floor of 20 and 30% headroom keep an
            // all-equal/flat series drawn through the middle of the band
            // rather than pinned to the very top or bottom.
            readonly property real axisMax: {
                var s = series, m = 0
                for (var i = 0; i < s.length; i++)
                    if (s[i].max !== undefined) m = Math.max(m, s[i].max)
                return Math.max(20, Math.ceil(m * 1.3))
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    spacing: 4

                    Item {
                        id: yAxis
                        Layout.preferredWidth: 38
                        Layout.fillHeight: true
                        Text {
                            anchors { top: parent.top; right: parent.right }
                            text: Math.round(cpuChartPanel.axisMax) + "%"
                            color: Theme.dimmer
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                        Text {
                            anchors { bottom: parent.bottom; right: parent.right }
                            text: "0%"
                            color: Theme.dimmer
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                    }

                    Canvas {
                        id: chartCanvas
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        antialiasing: true
                        renderStrategy: Canvas.Cooperative

                        readonly property var series: cpuChartPanel.series
                        readonly property real axisMax: cpuChartPanel.axisMax
                        onSeriesChanged: requestPaint()
                        onAxisMaxChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width, h = height

                            ctx.strokeStyle = Theme.border
                            ctx.lineWidth = 1
                            ctx.beginPath(); ctx.moveTo(0, 0.5); ctx.lineTo(w, 0.5); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(0, h - 0.5); ctx.lineTo(w, h - 0.5); ctx.stroke()

                            function yOf(v) { return h - (Math.max(0, Math.min(chartCanvas.axisMax, v)) / chartCanvas.axisMax) * h }

                            // dashed threshold reference — only drawn when
                            // it actually falls within the visible range.
                            if (page.warnThreshold <= chartCanvas.axisMax) {
                                var ty = yOf(page.warnThreshold)
                                ctx.save()
                                ctx.strokeStyle = Theme.crit
                                ctx.globalAlpha = 0.5
                                ctx.setLineDash([5, 5])
                                ctx.beginPath(); ctx.moveTo(0, ty); ctx.lineTo(w, ty); ctx.stroke()
                                ctx.restore()
                            }

                            var s = chartCanvas.series
                            if (!s || s.length === 0) return

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

                        Text {
                            anchors.centerIn: parent
                            visible: !cpuChartPanel.hasData
                            text: "no data"
                            color: Theme.dimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.glance
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 10
                    Text { Layout.fillWidth: true; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "min"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "max"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }

                ListView {
                    id: legendList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: cpuChartPanel.series

                    // Empty series must read as an explicit "no data" row,
                    // never a bare header with nothing under it.
                    Text {
                        anchors.centerIn: parent
                        visible: legendList.count === 0
                        text: "no data"
                        color: Theme.dimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.tableText
                    }

                    delegate: Item {
                        width: legendList.width
                        height: 24
                        readonly property bool over: modelData.max !== undefined && modelData.max >= page.warnThreshold

                        Rectangle { anchors.fill: parent; color: over ? Qt.rgba(0.910, 0.702, 0.255, 0.08) : "transparent" }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 10
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                RowLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 7
                                    // Same colour for a series' line and its
                                    // legend dash, so they can be matched.
                                    Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(index) }
                                    Text { text: modelData.name || ""; color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                                }
                            }
                            Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: (modelData.min !== undefined ? modelData.min.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: (modelData.max !== undefined ? modelData.max.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: (modelData.mean !== undefined ? modelData.mean.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                            Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: (modelData.last !== undefined ? modelData.last.toFixed(1) : "—"); color: over ? Theme.warn : Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        }
                    }
                }
            }
        }

        // -- Cluster CPU gauge --
        Panel {
            id: gaugePanel
            x: 954; width: 310; height: 202
            title: "Cluster CPU"

            readonly property real value: Math.max(0, Math.min(100, bridge.clusterCpu))
            readonly property color valColor: value >= page.critThreshold ? Theme.crit
                : (value >= page.warnThreshold ? Theme.warn : Theme.ok)

            ColumnLayout {
                anchors.fill: parent
                spacing: 6

                Item {
                    id: gaugeArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // one continuous background arc + one continuous value
                    // arc, both from the SAME start angle, same centre and
                    // radius, so the value arc always reads as a sweep
                    // continuing seamlessly out of the background track.
                    Canvas {
                        id: gaugeCanvas
                        readonly property real side: Math.min(gaugeArea.width, gaugeArea.height)
                        width: side
                        height: side
                        anchors.centerIn: parent
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
                            var r = width / 2 - 14
                            var sw = 14
                            var startA = 135 * Math.PI / 180
                            var endA = 405 * Math.PI / 180
                            var valA = startA + (endA - startA) * (gaugeCanvas.value / 100)

                            // flat (butt) caps: a short value arc at a low
                            // reading must still look like it CONTINUES the
                            // background ring, not a rounded, detached pill
                            // sitting on top of it.
                            ctx.lineCap = "butt"

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

                            // warn/crit ticks sit directly on the arc path.
                            function tick(pct, color) {
                                var a = startA + (endA - startA) * (pct / 100)
                                var x1 = cx + Math.cos(a) * (r - sw / 2 - 2)
                                var y1 = cy + Math.sin(a) * (r - sw / 2 - 2)
                                var x2 = cx + Math.cos(a) * (r + sw / 2 + 2)
                                var y2 = cy + Math.sin(a) * (r + sw / 2 + 2)
                                ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2)
                                ctx.strokeStyle = color; ctx.lineWidth = 3; ctx.lineCap = "butt"; ctx.stroke()
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
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
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
    }

    // ==== row 3: Node status table + Network throughput (390-720) =========
    //
    // Touch-target decision (round 2): fitting all 8 nodes without
    // scrolling needs ~33px rows given the fixed 720px page and the space
    // the chrome/hero row above already uses — well under the 60px floor.
    // Consciously relaxed here: seeing every node at a glance beats a
    // bigger tap target on a wall panel, and 33px (~5.2mm) is still a
    // usable finger target. Rows stay tappable; the ListView still scrolls
    // for clusters with more than fit.
    Item {
        id: row3
        anchors { left: parent.left; right: parent.right; top: row2.bottom; topMargin: 6; leftMargin: 8; rightMargin: 8 }
        height: 330

        readonly property int nodeRowH: 33

        Panel {
            id: nodeTablePanel
            x: 0; width: 946; height: row3.height
            title: "Node status"
            subtitle: page.nodes.length + " rows"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 4
                    Text { Layout.preferredWidth: 150; text: "node"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 96; text: "state"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.fillWidth: true; text: "cpu"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.fillWidth: true; text: "memory"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; text: "temp"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight; text: "pods"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "uptime"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bgAlt }

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
                        height: row3.nodeRowH

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
                                    implicitWidth: statePill.implicitWidth + 14; implicitHeight: 22
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
            x: 954; width: 310; height: row3.height
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
                    Layout.fillHeight: true
                    antialiasing: true
                    renderStrategy: Canvas.Cooperative

                    readonly property var rx: netPanel.rxSeries
                    readonly property var tx: netPanel.txSeries
                    onRxChanged: requestPaint()
                    onTxChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

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

                    Text {
                        anchors.centerIn: parent
                        visible: !netPanel.hasData
                        text: "no history\n" + page.fmtRate(bridge.netRx) + " rx, " + page.fmtRate(bridge.netTx) + " tx"
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.dimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.tableText
                    }
                }

                // Wide, explicitly-spaced columns: earlier round's 56/76px
                // columns overlapped for real-world values like
                // "1410.6 MB/s" — mean/last now get generous fixed widths.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    spacing: 10
                    Text { Layout.fillWidth: true; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    Text { Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 10
                    RowLayout { Layout.fillWidth: true; spacing: 7; Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(1) } Text { text: "rx"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText } }
                    Text { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: netPanel.rxSeries.length > 0 ? page.fmtRateNoUnit(netPanel.rxSeries[0].mean) : "—"; color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                    Text { Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight; text: page.fmtRate(netPanel.rxSeries.length > 0 ? netPanel.rxSeries[0].last : bridge.netRx); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 10
                    RowLayout { Layout.fillWidth: true; spacing: 7; Rectangle { width: 10; height: 3; radius: 1; color: page.seriesColor(3) } Text { text: "tx"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText } }
                    Text { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: netPanel.txSeries.length > 0 ? page.fmtRateNoUnit(netPanel.txSeries[0].mean) : "—"; color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                    Text { Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight; text: page.fmtRate(netPanel.txSeries.length > 0 ? netPanel.txSeries[0].last : bridge.netTx); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText; elide: Text.ElideRight }
                }
            }
        }
    }
}

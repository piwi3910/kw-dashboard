import QtQuick 2.15
import "../"

// Cluster overview: Grafana-style panel grid (design 5a).
//
// ROUND-3 REWRITE — WHY THE STRUCTURE IS EXPLICIT, NOT LAYOUT-BASED
// -----------------------------------------------------------------
// Rounds 1 and 2 built every panel out of `component Panel: Rectangle {
// ... default property alias content: contentArea.data }` plus nested
// Column/RowLayouts. Two defects came directly out of that and were
// measured off the device render (see task-5a-fix3-report.md):
//
//  1. The default-property alias never reparented anything. The Panel's
//     OWN internal ColumnLayout is itself a default child of the very
//     alias it contains, so QML cannot honour the assignment and leaves
//     ALL default children — internals and caller content alike — on the
//     panel root. Proof from the render: the hero chart's y-axis gutter
//     text sat at x=10/y=182 (panel origin) instead of x=18/y=216
//     (contentArea origin), and the plot canvas' own top axis line landed
//     exactly on the panel's top border. Every panel therefore drew its
//     body over its own title bar.
//
//  2. `Layout.fillHeight` defaults to TRUE for items that are themselves
//     layouts. The legend ListView's two siblings in the chart column
//     were both RowLayouts, so they filled by default and swallowed all
//     leftover height; the ListView, whose preferred/minimum height is 0,
//     got 0px. Header row visible, zero data rows. Proof: the legend
//     header rendered at y=352..377 with the panel bottom at y=383.
//
// So: no default-property aliases, no nested layouts for structure, no
// ListView where content-sized rows are wanted. The page is 1280x720 and
// fixed, so every panel is positioned and sized in explicit pixels that
// are written down and summed in the height-budget comments below. A
// Column+Repeater gives content-sized rows whose total height is a
// number I can add up; `clip: true` on every frame and every plot means
// nothing can escape into a neighbour even if a value surprises us.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges are absolute:
//   breadcrumb   0   .. 34   (34)
//   filter bar   34  .. 62   (28)
//   stat row     66  .. 146  (80)
//   row 2        150 .. 364  (214)  hero chart + CPU gauge
//   row 3        368 .. 684  (316)  node table + network
//   page dots    688 .. 704         drawn by Main.qml at z:100 — row 3
//                                   stops at 684, so 4px clear of them.
// Columns: 8px page gutter; left column x 8 w 946 (8..954), right column
// x 962 w 310 (962..1272). 946 + 8 + 310 = 1264 = 1280 - 2*8.
Rectangle {
    id: page
    width: 1280
    height: 720
    color: Theme.bg

    // ---- geometry constants (single source of truth for the budget) -------
    readonly property int pad: 8
    readonly property int colLeftX: 8
    readonly property int colLeftW: 946
    readonly property int colRightX: 962
    readonly property int colRightW: 310
    readonly property int titleBarH: 28      // every panel's title strip
    readonly property int contentTop: 33     // titleBarH + 1px rule + 4px

    // ---- bridge-optional fields (guarded — may not exist yet) ------------
    readonly property var nodeCpuSeries: bridge.nodeCpuSeries || []
    readonly property var netRxSeries: bridge.netRxSeries || []
    readonly property var netTxSeries: bridge.netTxSeries || []
    readonly property string timeRangeLabel: bridge.timeRangeLabel || "Last 1 hour"
    readonly property int alertsFiring: (bridge.alertsFiring !== undefined && bridge.alertsFiring !== null)
        ? bridge.alertsFiring : ((bridge.alerts || []).length)

    readonly property var nodes: bridge.nodes || []
    // Same source (node.ready / node.cordoned) feeds BOTH the big ratio and
    // the textual breakdown beside it, so the two can never disagree.
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

    // 5a's own gauge markers, distinct from Theme.stateColor's 70/88 split.
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

    function num(v) { return (v === undefined || v === null) ? "—" : v.toFixed(1) }

    // ---- shared bits ------------------------------------------------------
    //
    // NOTE: neither of these declares a default property alias. Children
    // written inside a PanelFrame/CardFrame instance land on the frame root
    // itself, in frame-local coordinates — which is exactly what the
    // explicit-y layout below wants, and is the one behaviour that cannot
    // silently fail. layer.enabled / QtGraphicalEffects are deliberately
    // absent (no GL backend on the device; they blank the subtree).

    component CardFrame: Rectangle {
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: 3
        clip: true
    }

    // Titled panel: a fixed 28px title strip, a 1px rule, then free space
    // from y=29 down. Callers place their content at y >= page.contentTop.
    component PanelFrame: Rectangle {
        id: frame
        property string title: ""
        property string note: ""
        // Local copy of the title-strip height: an inline component must not
        // rely on seeing ids from the enclosing document's scope, so nothing
        // in here reaches out to `page`.
        readonly property int titleH: 28

        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        radius: 3
        clip: true

        Text {
            x: 10
            y: 0
            width: frame.width - 20 - (frame.note.length > 0 ? noteText.width + 10 : 0)
            height: frame.titleH
            verticalAlignment: Text.AlignVCenter
            text: frame.title
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelTitle
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            id: noteText
            visible: frame.note.length > 0
            y: 0
            height: frame.titleH
            anchors.right: frame.right
            anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: frame.note
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
        Rectangle {
            x: 1
            y: frame.titleH
            width: frame.width - 2
            height: 1
            color: Theme.bgAlt
        }
    }

    component MiniBar: Item {
        id: bar
        property real pct: 0
        property color fillColor: Theme.ok
        implicitWidth: 100
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

    // Single-series area sparkline for the stat cards. Normalised against a
    // fixed 0-100 axis, so an all-equal history draws through the height its
    // value actually maps to and only a genuinely-zero series hugs the floor.
    component Sparkline: Canvas {
        id: spark
        property var history: []
        property color lineColor: Theme.ok
        antialiasing: true
        clip: true
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
            var step = w / (pts.length - 1)

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
    }

    // ==== chrome: breadcrumb 0..34 =========================================

    Rectangle {
        id: breadcrumb
        x: 0
        y: 0
        width: page.width
        height: 34
        color: Theme.bgAlt
        clip: true
        Rectangle { x: 0; y: 33; width: parent.width; height: 1; color: Theme.border }

        Row {
            x: 14
            height: 34
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "kw"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "kubernetes"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "cluster overview"; color: Theme.fgBright; font.bold: true; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }

        // Display-only chips: the bridge exposes a fixed time-range label and
        // refresh interval; tapping them intentionally does nothing.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            height: 34
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: chipTime.implicitWidth + 20; height: 26
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipTime; anchors.centerIn: parent; text: "⏱ " + page.timeRangeLabel; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: chipRefresh.implicitWidth + 20; height: 26
                color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                Text { id: chipRefresh; anchors.centerIn: parent; text: "⟳ 10s"; color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            }
        }
    }

    // ==== chrome: filter bar 34..62 ========================================

    Rectangle {
        id: filterBar
        x: 0
        y: 34
        width: page.width
        height: 28
        color: Theme.bg
        clip: true
        Rectangle { x: 0; y: 27; width: parent.width; height: 1; color: Theme.panel }

        Row {
            x: 14
            height: 28
            spacing: 18

            Repeater {
                model: [
                    { label: "cluster", value: "km01" },
                    { label: "namespace", value: "All" },
                    { label: "node", value: "All" }
                ]
                delegate: Row {
                    height: 28
                    spacing: 7
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: chipVal.implicitWidth + 18; height: 24
                        color: Theme.panelAlt; border.color: Theme.border; border.width: 1; radius: 3
                        Text { id: chipVal; anchors.centerIn: parent; text: modelData.value + "  ▾"; color: Theme.fgBright; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            height: 28
            spacing: 8
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.crit }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.alertsFiring + (page.alertsFiring === 1 ? " alert firing" : " alerts firing")
                color: Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
        }
    }

    // ==== stat row 66..146 (h 80) =========================================
    //
    // Card height budget (80): label 4..26 | value 26..60 | caption 60..80.
    // Glyph ink: label 20px font baseline y=24 -> ink 10..24; value 36px
    // mono baseline y=56 -> ink 30..56; caption 20px baseline y=80 -> ink
    // 66..80. No two bands touch, so nothing can overlap. Cards that
    // carry a sparkline instead of a caption put it at 61..79.
    Repeater {
        model: 4
        delegate: CardFrame {
            id: statCard
            x: page.pad + index * (310 + 8)
            y: 66
            width: 310
            height: 80

            readonly property int slot: index
            readonly property real cpu: bridge.clusterCpu
            readonly property real mem: bridge.clusterMem

            // per-slot content, resolved once so nothing is bound twice
            readonly property string cardLabel: slot === 0 ? "CPU utilisation"
                : slot === 1 ? "Memory utilisation"
                : slot === 2 ? "Pods running" : "Nodes ready"
            readonly property string cardValue: slot === 0 ? cpu.toFixed(1) + "%"
                : slot === 1 ? mem.toFixed(1) + "%"
                : slot === 2 ? String(bridge.podsRunning)
                : (page.readyCount + " / " + page.nodes.length)
            readonly property color cardColor: slot === 0 ? Theme.stateColor(cpu)
                : slot === 1 ? Theme.stateColor(mem)
                : slot === 2 ? Theme.fgBright
                : (page.notReadyCount > 0 ? Theme.crit
                    : (page.cordonedCount > 0 ? Theme.warn : Theme.ok))

            Text {
                x: 10; y: 4; width: 290; height: 22
                verticalAlignment: Text.AlignVCenter
                text: statCard.cardLabel
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
                elide: Text.ElideRight
            }
            Text {
                x: 10; y: 26; width: 290; height: 34
                verticalAlignment: Text.AlignVCenter
                text: statCard.cardValue
                color: statCard.cardColor
                font.family: Theme.monoFamily
                font.pixelSize: Theme.statNumber
            }

            // slots 0/1: sparkline strip, no caption in that band.
            Sparkline {
                visible: statCard.slot < 2
                x: 1; y: 61; width: 308; height: 18
                history: statCard.slot === 0 ? bridge.cpuHistory : bridge.memHistory
                lineColor: statCard.cardColor
            }
            Text {
                visible: statCard.slot < 2 && (statCard.slot === 0 ? (bridge.cpuHistory || []).length < 2
                                                               : (bridge.memHistory || []).length < 2)
                x: 10; y: 60; width: 290; height: 20
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: "collecting…"
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }

            // slot 2: pods caption. The words "pending"/"failing" always
            // appear, so the crit tint is never the only signal.
            Text {
                visible: statCard.slot === 2
                x: 10; y: 60; width: 290; height: 20
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: bridge.pendingPods + " pending" + (bridge.unhealthyPods > 0 ? " · " + bridge.unhealthyPods + " failing" : "")
                color: bridge.unhealthyPods > 0 ? Theme.crit : Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
                elide: Text.ElideLeft
            }

            // slot 3: nodes breakdown. 5a's row of ~4px colour-only chips
            // would be hue-alone state below the legibility floor, so it is
            // a word-paired breakdown instead, computed from the SAME
            // per-node fields as the "8 / 8" above it. Sits in its own
            // 60..80 band, well clear of the ratio's 30..56 ink.
            Row {
                visible: statCard.slot === 3
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 60
                height: 20
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: page.readyCount + " ready"; color: Theme.ok; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.notReadyCount > 0
                    text: "· " + page.notReadyCount + " not ready"
                    color: Theme.crit
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.cordonedCount > 0
                    text: "· " + page.cordonedCount + " cordoned"
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
            }
        }
    }

    // ==== row 2a: hero "CPU usage by node" 150..364 (h 214) ===============
    //
    // Panel height budget (214):
    //   title bar        0 ..  28   (28)
    //   1px rule        28 ..  29   (1)
    //   body           33 .. 210   (177)   [4px pad above and below]
    //   slack         210 .. 214   (4)
    // Body is split HORIZONTALLY, not vertically: an 8-row legend stacked
    // under the plot needs 21 + 8*19 = 173px, which would leave the plot
    // 4px. Side-by-side, the plot gets the full 177px and the legend gets
    // all 8 rows at the 20px dense-text floor.
    //   gutter  x   8 ..  58  (50)   y-axis labels only, right-aligned
    //   plot    x  62 .. 528  (466)  clipped canvas, axes drawn inside
    //   legend  x 538 .. 938  (400)  header 33..54, rows 55..207 (8 x 19)
    // Legend columns inside that 400px, dash 0(10) then name 16(136) then
    // min 152(62) max 214(62) mean 276(62) last 338(62) = 400. The name gets
    // 136px because a full node name ("master-11", "worker-21") is 9 chars
    // of 20px IBM Plex Sans at ~11px average advance = ~100px; 136 clears
    // that with 36px spare, so no name is ever truncated. The numeric cells
    // need only 5 mono chars ("100.0" = 5 x 12 = 60px), so 62px each is
    // enough and right-alignment keeps every column under its header.
    // 8 + 50 + 4 + 466 + 10 + 400 + 8 = 946 = panel width.
    PanelFrame {
        id: heroPanel
        x: page.colLeftX
        y: 150
        width: page.colLeftW
        height: 214
        title: "CPU usage by node"

        readonly property var series: page.nodeCpuSeries
        readonly property bool hasData: series.length > 0
        readonly property int rowH: 19
        readonly property int maxRows: 8
        // When there are more series than slots, the last slot becomes the
        // "+N more" note, so the note can never be drawn over a data row.
        readonly property int shownRows: series.length > maxRows ? maxRows - 1 : maxRows

        // Auto-ranged y-axis: a fixed 0-100% scale crushed real single-digit
        // load onto the floor. Floor of 20 and 30% headroom keep a flat
        // series inside the band rather than pinned to an edge.
        readonly property real axisMax: {
            var s = series, m = 0
            for (var i = 0; i < s.length; i++)
                if (s[i].max !== undefined) m = Math.max(m, s[i].max)
            return Math.max(20, Math.ceil(m * 1.3))
        }

        // --- y-axis gutter: three labels, each in its own 26px band inside
        // --- a reserved 50px column. Nothing here can reach the title bar.
        Item {
            id: heroGutter
            x: 8
            y: page.contentTop
            width: 50
            height: 177
            clip: true

            Text {
                x: 0; y: 0; width: 50; height: 26
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: Math.round(heroPanel.axisMax) + "%"
                color: Theme.dimmer
                font.family: Theme.monoFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 75; width: 50; height: 26
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: Math.round(heroPanel.axisMax / 2) + "%"
                color: Theme.dimmer
                font.family: Theme.monoFamily
                font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 151; width: 50; height: 26
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: "0%"
                color: Theme.dimmer
                font.family: Theme.monoFamily
                font.pixelSize: Theme.tableText
            }
        }

        // --- plot: clipped, so a stray coordinate cannot leave this box.
        Canvas {
            id: heroPlot
            x: 62
            y: page.contentTop
            width: 466
            height: 177
            clip: true
            antialiasing: true
            renderStrategy: Canvas.Cooperative

            readonly property var series: heroPanel.series
            readonly property real axisMax: heroPanel.axisMax
            onSeriesChanged: requestPaint()
            onAxisMaxChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height

                ctx.strokeStyle = Theme.border
                ctx.lineWidth = 1
                var gy = [0.5, Math.round(h / 2) + 0.5, h - 0.5]
                for (var g = 0; g < gy.length; g++) {
                    ctx.beginPath(); ctx.moveTo(0, gy[g]); ctx.lineTo(w, gy[g]); ctx.stroke()
                }

                function yOf(v) {
                    return h - (Math.max(0, Math.min(heroPlot.axisMax, v)) / heroPlot.axisMax) * h
                }

                // dashed warn reference — only when it is inside the range.
                if (page.warnThreshold <= heroPlot.axisMax) {
                    var ty = yOf(page.warnThreshold)
                    ctx.save()
                    ctx.strokeStyle = Theme.crit
                    ctx.globalAlpha = 0.5
                    ctx.setLineDash([5, 5])
                    ctx.beginPath(); ctx.moveTo(0, ty); ctx.lineTo(w, ty); ctx.stroke()
                    ctx.restore()
                }

                var s = heroPlot.series
                if (!s || s.length === 0) return

                for (var i = 0; i < s.length; i++) {
                    var pts = s[i].points || []
                    if (pts.length === 0) continue
                    ctx.strokeStyle = page.seriesColor(i)
                    ctx.lineWidth = 2
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    if (pts.length === 1) {
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
                visible: !heroPanel.hasData
                text: "no data"
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.glance
            }
        }

        // --- legend: a Column of Repeater rows, so the total height is
        // --- literally maxRows * rowH and cannot collapse to zero the way
        // --- a fillHeight ListView did. Header band 33..54, rows 55..207.
        Item {
            id: heroLegend
            x: 538
            y: page.contentTop
            width: 400
            height: 177
            clip: true

            // header row (legend-local y 0..21)
            Item {
                x: 0; y: 0; width: 400; height: 21
                Text { x: 0;   y: 0; width: 146; height: 21; verticalAlignment: Text.AlignVCenter; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                Text { x: 152; y: 0; width: 62;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "min";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 214; y: 0; width: 62;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "max";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 276; y: 0; width: 62;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 338; y: 0; width: 62;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle { x: 0; y: 21; width: 400; height: 1; color: Theme.bgAlt }

            Column {
                id: heroLegendRows
                x: 0
                y: 22
                width: 400
                spacing: 0

                Repeater {
                    model: heroPanel.series

                    delegate: Item {
                        id: lrow
                        width: 400
                        height: heroPanel.rowH
                        visible: index < heroPanel.shownRows

                        readonly property bool over: modelData.max !== undefined && modelData.max >= page.warnThreshold
                        readonly property color txt: over ? Theme.warn : Theme.fgMuted

                        Rectangle {
                            anchors.fill: parent
                            color: lrow.over ? Qt.rgba(0.910, 0.702, 0.255, 0.08) : "transparent"
                        }
                        // series line colour, so a legend row can be matched
                        // to its line; the node NAME carries the identity.
                        Rectangle {
                            x: 0; y: (heroPanel.rowH - 3) / 2
                            width: 10; height: 3; radius: 1
                            color: page.seriesColor(index)
                        }
                        Text {
                            x: 16; y: 0; width: 136; height: heroPanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.name || ""
                            color: lrow.txt
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tableText
                            // ElideMiddle, never ElideRight: the trailing
                            // digits are what identify the node, so they must
                            // survive even if a name ever exceeds 136px.
                            elide: Text.ElideMiddle
                        }
                        Text { x: 152; y: 0; width: 62; height: heroPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.num(modelData.min);  color: lrow.txt; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 214; y: 0; width: 62; height: heroPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.num(modelData.max);  color: lrow.txt; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 276; y: 0; width: 62; height: heroPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.num(modelData.mean); color: lrow.txt; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 338; y: 0; width: 62; height: heroPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.num(modelData.last); color: lrow.over ? Theme.warn : Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    }
                }
            }

            // Never a bare header with nothing under it.
            Text {
                x: 0; y: 30; width: 400; height: 24
                verticalAlignment: Text.AlignVCenter
                visible: !heroPanel.hasData
                text: "no data"
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
            // Explicit rather than silent truncation if a cluster ever has
            // more series than the 8 rows the budget reserves.
            Text {
                x: 0; y: 22 + (heroPanel.maxRows - 1) * heroPanel.rowH
                width: 400; height: heroPanel.rowH
                verticalAlignment: Text.AlignVCenter
                visible: heroPanel.series.length > heroPanel.maxRows
                text: "+ " + (heroPanel.series.length - heroPanel.shownRows) + " more"
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
        }
    }

    // ==== row 2b: Cluster CPU gauge 150..364 (h 214) ======================
    //
    // Panel height budget (214):
    //   title bar    0 ..  28
    //   1px rule    28 ..  29
    //   gauge      33 .. 178  (145 square, centred — the arc can never
    //                          reach the title strip)
    //   axis row  182 .. 206  (24)
    //   slack     206 .. 214
    PanelFrame {
        id: gaugePanel
        x: page.colRightX
        y: 150
        width: page.colRightW
        height: 214
        title: "Cluster CPU"

        readonly property real value: Math.max(0, Math.min(100, bridge.clusterCpu))
        readonly property color valColor: value >= page.critThreshold ? Theme.crit
            : (value >= page.warnThreshold ? Theme.warn : Theme.ok)

        Item {
            id: gaugeArea
            x: 8
            y: page.contentTop
            width: 294
            height: 145
            clip: true

            Canvas {
                id: gaugeCanvas
                width: 145
                height: 145
                anchors.centerIn: parent
                antialiasing: true
                renderStrategy: Canvas.Cooperative

                readonly property real value: gaugePanel.value
                readonly property color valColor: gaugePanel.valColor
                onValueChanged: requestPaint()
                onValColorChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2, cy = height / 2
                    var sw = 14
                    var r = width / 2 - sw
                    var startA = 135 * Math.PI / 180
                    var endA = 405 * Math.PI / 180
                    var valA = startA + (endA - startA) * (gaugeCanvas.value / 100)

                    // butt caps: a short value arc must read as a CONTINUATION
                    // of the track, not a detached rounded pill on top of it.
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

                    function tick(pct, color) {
                        var a = startA + (endA - startA) * (pct / 100)
                        var x1 = cx + Math.cos(a) * (r - sw / 2 - 2)
                        var y1 = cy + Math.sin(a) * (r - sw / 2 - 2)
                        var x2 = cx + Math.cos(a) * (r + sw / 2 + 2)
                        var y2 = cy + Math.sin(a) * (r + sw / 2 + 2)
                        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2)
                        ctx.strokeStyle = color; ctx.lineWidth = 3; ctx.stroke()
                    }
                    tick(page.warnThreshold, Theme.warn)
                    tick(page.critThreshold, Theme.crit)
                }
            }

            // Readout: two fixed bands inside the gauge area, so the number
            // and its unit can never land on each other or on the title.
            Text {
                x: 0; y: 42; width: 294; height: 50
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: gaugePanel.value.toFixed(1)
                color: Theme.fgBright
                font.family: Theme.monoFamily
                font.pixelSize: Theme.gaugeNumber
            }
            Text {
                x: 0; y: 92; width: 294; height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "percent"
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tableText
            }
        }

        // 5a's gauge only looks like it labels along the arc; its HTML puts
        // these four in a plain row underneath. Explicit x/width so the
        // named thresholds cannot collide at any string length.
        Text { x: 8;   y: 182; width: 24; height: 24; verticalAlignment: Text.AlignVCenter; text: "0"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
        Text { x: 74;  y: 182; width: 88; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: page.warnThreshold.toFixed(0) + " warn"; color: Theme.warn; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
        Text { x: 170; y: 182; width: 88; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: page.critThreshold.toFixed(0) + " crit"; color: Theme.crit; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
        Text { x: 262; y: 182; width: 40; height: 24; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "100"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
    }

    // ==== row 3a: Node status table 368..684 (h 316) ======================
    //
    // Panel height budget (316):
    //   title bar     0 ..  28
    //   1px rule     28 ..  29
    //   col header   29 ..  54  (25)
    //   1px rule     54 ..  55
    //   rows         55 .. 311  (8 x 32 = 256)
    //   slack       311 .. 316  (5)
    // Panel bottom is 368 + 316 = 684; Main.qml's page dots start at 688,
    // so the last row clears them by 4px + the 5px slack.
    //
    // 32px rows are under the 60px touch floor. Consciously relaxed: on a
    // wall panel, seeing every node at a glance beats a bigger tap target,
    // and 32px (~5mm) is still a usable finger target. Every visible row is
    // fully tappable through to the read-only node detail view.
    //
    // Column x budget (panel-local, 8..938):
    //   node 8 (150) | state 158 (100) | cpu 258 (214) | mem 472 (214)
    //   | temp 686 (76,r) | pods 762 (76,r) | uptime 838 (100,r)
    PanelFrame {
        id: nodePanel
        x: page.colLeftX
        y: 368
        width: page.colLeftW
        height: 316
        title: "Node status"
        note: page.nodes.length + " rows"

        readonly property int rowH: 32
        readonly property int maxRows: 8
        // Last slot becomes the "+N more" note when the cluster has more
        // nodes than slots, so the note never lands on a data row.
        readonly property int shownRows: page.nodes.length > maxRows ? maxRows - 1 : maxRows

        Item {
            x: 0; y: 29; width: nodePanel.width; height: 25
            Text { x: 8;   y: 0; width: 150; height: 25; verticalAlignment: Text.AlignVCenter; text: "node";   color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 158; y: 0; width: 100; height: 25; verticalAlignment: Text.AlignVCenter; text: "state";  color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 258; y: 0; width: 214; height: 25; verticalAlignment: Text.AlignVCenter; text: "cpu";    color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 472; y: 0; width: 214; height: 25; verticalAlignment: Text.AlignVCenter; text: "memory"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 686; y: 0; width: 76;  height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "temp";   color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 762; y: 0; width: 76;  height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "pods";   color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 838; y: 0; width: 100; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "uptime"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: nodePanel.width - 2; height: 1; color: Theme.bgAlt }

        Item {
            id: nodeRowsArea
            x: 0; y: 55; width: nodePanel.width; height: 261
            clip: true

            Column {
                width: parent.width
                spacing: 0

                Repeater {
                    model: page.nodes

                    delegate: Item {
                        id: nodeRow
                        width: nodeRowsArea.width
                        height: nodePanel.rowH
                        visible: index < nodePanel.shownRows

                        readonly property var node: modelData
                        readonly property string state: !node.ready ? "notready" : (node.cordoned ? "cordon" : "ready")
                        readonly property color stateColor: state === "notready" ? Theme.crit
                            : (state === "cordon" ? Theme.warn : Theme.ok)
                        readonly property bool down: state === "notready"

                        Rectangle {
                            anchors.fill: parent
                            color: nodeRow.down ? Qt.rgba(0.890, 0.416, 0.416, 0.07)
                                : (nodeRow.state === "cordon" ? Qt.rgba(0.910, 0.702, 0.255, 0.05) : "transparent")
                        }
                        Rectangle { x: 0; y: nodePanel.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                        Text {
                            x: 8; y: 0; width: 150; height: nodePanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: nodeRow.node.name
                            color: nodeRow.down ? Theme.crit : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tableText
                            elide: Text.ElideRight
                        }

                        // Text pill, not a bare colour: the state word is the
                        // accessibility guarantee, the tint only reinforces.
                        Rectangle {
                            x: 158
                            y: (nodePanel.rowH - 24) / 2
                            width: statePill.implicitWidth + 14
                            height: 24
                            radius: 3
                            color: Qt.rgba(nodeRow.stateColor.r, nodeRow.stateColor.g, nodeRow.stateColor.b, 0.16)
                            Text {
                                id: statePill
                                anchors.centerIn: parent
                                text: nodeRow.state
                                color: nodeRow.stateColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.tableText
                            }
                        }

                        MiniBar {
                            visible: !nodeRow.down
                            x: 258; y: (nodePanel.rowH - 10) / 2
                            width: 100; height: 10
                            pct: nodeRow.node.cpuPct
                            fillColor: Theme.stateColor(nodeRow.node.cpuPct)
                        }
                        Text {
                            visible: !nodeRow.down
                            x: 366; y: 0; width: 60; height: nodePanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: Math.round(nodeRow.node.cpuPct)
                            color: nodeRow.node.cpuPct >= 70 ? Theme.warn : Theme.fgMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                        Text {
                            visible: nodeRow.down
                            x: 258; y: 0; width: 214; height: nodePanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: "no data"
                            color: Theme.dimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tableText
                        }

                        MiniBar {
                            visible: !nodeRow.down
                            x: 472; y: (nodePanel.rowH - 10) / 2
                            width: 100; height: 10
                            pct: nodeRow.node.memPct
                            fillColor: Theme.stateColor(nodeRow.node.memPct)
                        }
                        Text {
                            visible: !nodeRow.down
                            x: 580; y: 0; width: 60; height: nodePanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: Math.round(nodeRow.node.memPct)
                            color: Theme.fgMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                        Text {
                            visible: nodeRow.down
                            x: 472; y: 0; width: 214; height: nodePanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: "no data"
                            color: Theme.dimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tableText
                        }

                        Text {
                            x: 686; y: 0; width: 76; height: nodePanel.rowH
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            text: (nodeRow.down || nodeRow.node.tempC < 0) ? "—" : Math.round(nodeRow.node.tempC) + "°"
                            color: nodeRow.node.tempC >= 60 ? Theme.warn : Theme.fgMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                        Text {
                            x: 762; y: 0; width: 76; height: nodePanel.rowH
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            text: nodeRow.node.pods
                            color: Theme.fgMuted
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }
                        Text {
                            x: 838; y: 0; width: 100; height: nodePanel.rowH
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            text: (nodeRow.node.uptimeDays === null || nodeRow.node.uptimeDays === undefined)
                                ? "—" : Math.round(nodeRow.node.uptimeDays) + "d"
                            color: nodeRow.down ? Theme.crit : Theme.dim
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.tableText
                        }

                        // read-only: navigates to the node detail view only.
                        TapHandler {
                            onTapped: bridge.pushView("nodeDetail", { "node": nodeRow.node.name })
                        }
                    }
                }
            }
        }

        // Explicit rather than silent truncation past the 8-row budget.
        Text {
            visible: page.nodes.length > nodePanel.maxRows
            x: 8
            y: 55 + (nodePanel.maxRows - 1) * nodePanel.rowH
            width: 300; height: nodePanel.rowH
            verticalAlignment: Text.AlignVCenter
            text: "+ " + (page.nodes.length - nodePanel.shownRows) + " more nodes"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }

    // ==== row 3b: Network throughput 368..684 (h 316) ====================
    //
    // Panel height budget (316):
    //   title bar     0 ..  28
    //   1px rule     28 ..  29
    //   chart        33 .. 223  (190, clipped)
    //   legend hdr  229 .. 251  (22)
    //   rx row      253 .. 279  (26)
    //   tx row      281 .. 307  (26)
    //   slack       307 .. 316  (9)
    // Column x budget (panel-local, 8..302):
    //   series 8 (66) | mean 82 (90,r) | last 192 (110,r)
    // Right edges 172 and 302 already put each value under its own header;
    // the series column gives up 18px so the widest "mean" (60px, ending at
    // 172) and the widest "last" ("1410.6 MB/s", 132px... clamped by elide
    // to the 110px cell starting at 192) are 20px apart instead of 8, so
    // "23.6" and "10.8 MB/s" can no longer read as one run of digits.
    PanelFrame {
        id: netPanel
        x: page.colRightX
        y: 368
        width: page.colRightW
        height: 316
        title: "Network throughput"

        readonly property var rxSeries: page.netRxSeries
        readonly property var txSeries: page.netTxSeries
        readonly property bool hasData: rxSeries.length > 0 || txSeries.length > 0

        Canvas {
            id: netCanvas
            x: 8
            y: page.contentTop
            width: 294
            height: 190
            clip: true
            antialiasing: true
            renderStrategy: Canvas.Cooperative

            readonly property var rx: netPanel.rxSeries
            readonly property var tx: netPanel.txSeries
            onRxChanged: requestPaint()
            onTxChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height

                ctx.strokeStyle = Theme.border
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(0, Math.round(h / 3) + 0.5); ctx.lineTo(w, Math.round(h / 3) + 0.5); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(0, Math.round(2 * h / 3) + 0.5); ctx.lineTo(w, Math.round(2 * h / 3) + 0.5); ctx.stroke()

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

        // Wide, explicitly-placed columns: a real value like "1410.6 MB/s"
        // needs the full 110px "last" column not to collide with "mean".
        Item {
            x: 0; y: 229; width: netPanel.width; height: 22
            Text { x: 8;   y: 0; width: 66;  height: 22; verticalAlignment: Text.AlignVCenter; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 82;  y: 0; width: 90;  height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            Text { x: 192; y: 0; width: 110; height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
        }

        Repeater {
            model: 2
            delegate: Item {
                id: nrow
                x: 0
                y: 253 + index * 28
                width: netPanel.width
                height: 26

                readonly property var s: index === 0 ? netPanel.rxSeries : netPanel.txSeries
                readonly property real live: index === 0 ? bridge.netRx : bridge.netTx

                Rectangle {
                    x: 8; y: 11; width: 10; height: 3; radius: 1
                    color: page.seriesColor(index === 0 ? 1 : 3)
                }
                Text {
                    x: 24; y: 0; width: 50; height: 26
                    verticalAlignment: Text.AlignVCenter
                    text: index === 0 ? "rx" : "tx"
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 82; y: 0; width: 90; height: 26
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: nrow.s.length > 0 ? page.fmtRateNoUnit(nrow.s[0].mean) : "—"
                    color: Theme.fgMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideLeft
                }
                Text {
                    x: 192; y: 0; width: 110; height: 26
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: page.fmtRate(nrow.s.length > 0 ? nrow.s[0].last : nrow.live)
                    color: Theme.fgBright
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideLeft
                }
            }
        }
    }
}

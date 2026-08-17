import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// Pulse — network throughput and per-namespace memory, in the 5a
// observability idiom (breadcrumb + bordered panels + axis gutters +
// min/max/mean/last legends). Structure copied from Cluster.qml: explicit
// pixel geometry, no nested layouts, `clip: true` on every plot and list.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb     0 ..  34  (34)
//   gap           34 ..  42  (8)
//   stat row      42 .. 122  (80)   4 cards x 310, gaps 8
//   net panel    126 .. 404  (278)  left column
//   ns mem panel 408 .. 684  (276)  left column
//   events panel 126 .. 684  (558)  right column, full remaining height
//   page dots    688 .. 704         drawn by Main.qml at z:100 — content
//                                   stops at 684, 4px clear.
// Columns: 8px gutter; left x 8 w 946, right x 962 w 310 (ends 1272).
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property int pad: 8
    readonly property int colLeftX: 8
    readonly property int colLeftW: 946
    readonly property int colRightX: 962
    readonly property int colRightW: 310
    readonly property int contentTop: 33

    readonly property var netRxSeries: bridge.netRxSeries || []
    readonly property var netTxSeries: bridge.netTxSeries || []
    readonly property var nsMemSeries: bridge.nsMemSeries || []
    readonly property var events: bridge.events || []
    readonly property string timeRangeLabel: bridge.timeRangeLabel || "Last 1 hour"

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: page.clockText = Qt.formatTime(new Date(), "hh:mm") }

    readonly property int warnCount: {
        var n = 0
        for (var i = 0; i < page.events.length; i++) if (page.events[i].warning) n++
        return n
    }

    function fmtRate(v) {
        var b = v || 0
        if (b >= 1e6) return (b / 1e6).toFixed(1) + " MB/s"
        if (b >= 1e3) return (b / 1e3).toFixed(1) + " KB/s"
        return Math.round(b) + " B/s"
    }
    function fmtRateShort(v) {
        var b = v || 0
        if (b >= 1e6) return (b / 1e6).toFixed(1) + "M"
        if (b >= 1e3) return (b / 1e3).toFixed(1) + "K"
        return Math.round(b) + ""
    }
    function fmtMemShort(v) {
        var b = v || 0
        if (b >= 1e9) return (b / 1e9).toFixed(1) + "G"
        if (b >= 1e6) return Math.round(b / 1e6) + "M"
        if (b >= 1e3) return Math.round(b / 1e3) + "K"
        return Math.round(b) + ""
    }
    function seriesColor(i) {
        var c = Theme.seriesColors
        return c[i % c.length]
    }

    // Shared plot painter: one polyline per series against a fixed max, with
    // three horizontal guides. Single-point series draw a short level dash so
    // "one sample so far" never looks like "no data".
    function paintSeries(ctx, w, h, list, maxV, colorFn) {
        ctx.reset()
        ctx.strokeStyle = Theme.border
        ctx.lineWidth = 1
        var gy = [0.5, Math.round(h / 2) + 0.5, h - 0.5]
        for (var g = 0; g < gy.length; g++) {
            ctx.beginPath(); ctx.moveTo(0, gy[g]); ctx.lineTo(w, gy[g]); ctx.stroke()
        }
        if (!list || list.length === 0 || maxV <= 0) return
        for (var i = 0; i < list.length; i++) {
            var pts = list[i].points || []
            if (pts.length === 0) continue
            ctx.strokeStyle = colorFn(i)
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            if (pts.length === 1) {
                var yy = h - (Math.max(0, Math.min(maxV, pts[0][1])) / maxV) * h
                ctx.beginPath(); ctx.moveTo(w * 0.5 - 8, yy); ctx.lineTo(w * 0.5 + 8, yy); ctx.stroke()
            } else {
                var step = w / (pts.length - 1)
                ctx.beginPath()
                ctx.moveTo(0, h - (Math.max(0, Math.min(maxV, pts[0][1])) / maxV) * h)
                for (var j = 1; j < pts.length; j++)
                    ctx.lineTo(j * step, h - (Math.max(0, Math.min(maxV, pts[j][1])) / maxV) * h)
                ctx.stroke()
            }
        }
    }

    function axisMax(list) {
        var m = 0
        for (var i = 0; i < list.length; i++)
            if (list[i].max !== undefined) m = Math.max(m, list[i].max)
        return m > 0 ? m * 1.2 : 1
    }

    // ==== breadcrumb 0..34 ================================================
    PageHeader {
        id: header
        crumb: "pulse"
        chips: [
            { "text": "⏱ " + page.timeRangeLabel },
            { "text": "🕘 " + page.clockText },
            { "text": page.warnCount + (page.warnCount === 1 ? " warn event" : " warn events"),
              "color": page.warnCount > 0 ? Theme.warn : Theme.fgMuted }
        ]
    }

    // ==== stat row 42..122 (h 80) ========================================
    StatCard {
        x: page.pad; y: 42; width: 310; height: 80
        label: "Network receive"
        value: page.fmtRate(bridge.netRx)
        valueColor: Theme.fgBright
        note: page.netRxSeries.length > 0 ? "mean " + page.fmtRate(page.netRxSeries[0].mean) : "collecting…"
    }
    StatCard {
        x: page.pad + 318; y: 42; width: 310; height: 80
        label: "Network transmit"
        value: page.fmtRate(bridge.netTx)
        valueColor: Theme.fgBright
        note: page.netTxSeries.length > 0 ? "mean " + page.fmtRate(page.netTxSeries[0].mean) : "collecting…"
    }
    StatCard {
        x: page.pad + 636; y: 42; width: 310; height: 80
        label: "Warning events"
        value: String(page.warnCount)
        valueColor: page.warnCount > 0 ? Theme.warn : Theme.fgBright
        note: "of " + page.events.length + " recent"
        noteColor: Theme.dim
    }
    StatCard {
        x: page.pad + 954; y: 42; width: 310; height: 80
        label: "Pods running"
        value: String(bridge.podsRunning)
        note: bridge.pendingPods + " pending" + (bridge.unhealthyPods > 0 ? " · " + bridge.unhealthyPods + " failing" : "")
        noteColor: bridge.unhealthyPods > 0 ? Theme.crit : Theme.dim
    }

    // ==== network throughput 126..404 (h 278) ============================
    //
    // Panel height budget (278):
    //   title bar     0 ..  28
    //   1px rule     28 ..  29
    //   plot         33 .. 183  (150, clipped)
    //   legend hdr  187 .. 209  (22)
    //   rx row      211 .. 237  (26)
    //   tx row      239 .. 265  (26)
    //   slack       265 .. 278  (13)
    // Column x budget (panel-local): gutter 8 (64, right-aligned) |
    //   plot 76 (862) -> 938. Legend: swatch 8 | name 24 (110) |
    //   min 140 (150,r) | max 294 (150,r) | mean 448 (150,r) | last 602 (150,r)
    Panel {
        id: netPanel
        x: page.colLeftX
        y: 126
        width: page.colLeftW
        height: 278
        title: "Network throughput"
        note: page.timeRangeLabel

        readonly property var list: {
            var out = []
            if (page.netRxSeries.length > 0) out.push(page.netRxSeries[0])
            if (page.netTxSeries.length > 0) out.push(page.netTxSeries[0])
            return out
        }
        readonly property bool hasData: list.length > 0
        readonly property real maxV: page.axisMax(list)

        Item {
            x: 8; y: page.contentTop; width: 64; height: 150
            clip: true
            Text {
                x: 0; y: 0; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: page.fmtRateShort(netPanel.maxV)
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 62; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: page.fmtRateShort(netPanel.maxV / 2)
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 124; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: "0"
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
        }

        Canvas {
            id: netPlot
            x: 76; y: page.contentTop; width: 862; height: 150
            clip: true
            antialiasing: true
            renderStrategy: Canvas.Cooperative

            readonly property var list: netPanel.list
            readonly property real maxV: netPanel.maxV
            onListChanged: requestPaint()
            onMaxVChanged: requestPaint()
            onWidthChanged: requestPaint()

            onPaint: page.paintSeries(getContext("2d"), width, height, netPlot.list, netPlot.maxV,
                                      function (i) { return page.seriesColor(i === 0 ? 1 : 3) })

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

        Item {
            x: 0; y: 187; width: netPanel.width; height: 22
            Text { x: 24;  y: 0; width: 110; height: 22; verticalAlignment: Text.AlignVCenter; text: "series"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 140; y: 0; width: 150; height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "min";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            Text { x: 294; y: 0; width: 150; height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "max";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            Text { x: 448; y: 0; width: 150; height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            Text { x: 602; y: 0; width: 150; height: 22; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 209; width: netPanel.width - 2; height: 1; color: Theme.bgAlt }

        Repeater {
            model: 2
            delegate: Item {
                id: nrow
                x: 0
                y: 211 + index * 28
                width: netPanel.width
                height: 26

                readonly property var s: index === 0 ? page.netRxSeries : page.netTxSeries
                readonly property real live: index === 0 ? bridge.netRx : bridge.netTx
                readonly property bool has: s.length > 0

                Rectangle { x: 8; y: 11; width: 10; height: 3; radius: 1; color: page.seriesColor(index === 0 ? 1 : 3) }
                Text {
                    x: 24; y: 0; width: 110; height: 26
                    verticalAlignment: Text.AlignVCenter
                    text: index === 0 ? "receive" : "transmit"
                    color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText
                }
                Text { x: 140; y: 0; width: 150; height: 26; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: nrow.has ? page.fmtRate(nrow.s[0].min) : "—";  color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 294; y: 0; width: 150; height: 26; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: nrow.has ? page.fmtRate(nrow.s[0].max) : "—";  color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 448; y: 0; width: 150; height: 26; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: nrow.has ? page.fmtRate(nrow.s[0].mean) : "—"; color: Theme.fgMuted; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 602; y: 0; width: 150; height: 26; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.fmtRate(nrow.has ? nrow.s[0].last : nrow.live); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            }
        }
    }

    // ==== memory by namespace 408..684 (h 276) ===========================
    //
    // Panel height budget (276):
    //   title bar     0 ..  28
    //   1px rule     28 ..  29
    //   body         33 .. 270  (237)
    //   slack       270 .. 276  (6)
    // Body split horizontally so an 8-row legend and the plot both get their
    // full height (the same reason Cluster's hero chart does it this way):
    //   gutter  x   8 ..  72  (64,r)
    //   plot    x  76 .. 416  (340, clipped)
    //   legend  x 426 .. 938  (512) header 0..21, rows 22..174 (8 x 19)
    // Legend columns (legend-local): swatch 0 | name 16 (200) |
    //   min 220 (70,r) | max 294 (70,r) | mean 368 (70,r) | last 442 (70,r)
    // Namespace names get 200px at 20px sans (~19 chars) so the name that
    // distinguishes one series from another is never elided away.
    Panel {
        id: nsPanel
        x: page.colLeftX
        y: 408
        width: page.colLeftW
        height: 276
        title: "Memory by namespace"
        note: page.nsMemSeries.length + " series"

        readonly property var list: page.nsMemSeries
        readonly property bool hasData: list.length > 0
        readonly property real maxV: page.axisMax(list)
        readonly property int rowH: 19
        readonly property int maxRows: 8
        readonly property int shownRows: list.length > maxRows ? maxRows - 1 : maxRows

        Item {
            x: 8; y: page.contentTop; width: 64; height: 237
            clip: true
            Text {
                x: 0; y: 0; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: page.fmtMemShort(nsPanel.maxV)
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 105; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: page.fmtMemShort(nsPanel.maxV / 2)
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
            Text {
                x: 0; y: 211; width: 64; height: 26
                horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                text: "0"
                color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText
            }
        }

        Canvas {
            id: nsPlot
            x: 76; y: page.contentTop; width: 340; height: 237
            clip: true
            antialiasing: true
            renderStrategy: Canvas.Cooperative

            readonly property var list: nsPanel.list
            readonly property real maxV: nsPanel.maxV
            onListChanged: requestPaint()
            onMaxVChanged: requestPaint()
            onWidthChanged: requestPaint()

            onPaint: page.paintSeries(getContext("2d"), width, height, nsPlot.list, nsPlot.maxV, page.seriesColor)

            Text {
                anchors.centerIn: parent
                visible: !nsPanel.hasData
                text: "no data"
                color: Theme.dimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.glance
            }
        }

        Item {
            id: nsLegend
            x: 426; y: page.contentTop; width: 512; height: 237
            clip: true

            Item {
                x: 0; y: 0; width: 512; height: 21
                Text { x: 16;  y: 0; width: 200; height: 21; verticalAlignment: Text.AlignVCenter; text: "namespace"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
                Text { x: 220; y: 0; width: 70;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "min";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 294; y: 0; width: 70;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "max";  color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 368; y: 0; width: 70;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "mean"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                Text { x: 442; y: 0; width: 70;  height: 21; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "last"; color: Theme.dimmer; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
            }
            Rectangle { x: 0; y: 21; width: 512; height: 1; color: Theme.bgAlt }

            Column {
                x: 0; y: 22; width: 512; spacing: 0

                Repeater {
                    model: nsPanel.list

                    delegate: Item {
                        width: 512
                        height: nsPanel.rowH
                        visible: index < nsPanel.shownRows

                        Rectangle { x: 0; y: (nsPanel.rowH - 3) / 2; width: 10; height: 3; radius: 1; color: page.seriesColor(index) }
                        Text {
                            x: 16; y: 0; width: 200; height: nsPanel.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.name || ""
                            color: Theme.fgMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText
                            elide: Text.ElideRight
                        }
                        Text { x: 220; y: 0; width: 70; height: nsPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.fmtMemShort(modelData.min);  color: Theme.fgMuted;  font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 294; y: 0; width: 70; height: nsPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.fmtMemShort(modelData.max);  color: Theme.fgMuted;  font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 368; y: 0; width: 70; height: nsPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.fmtMemShort(modelData.mean); color: Theme.fgMuted;  font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                        Text { x: 442; y: 0; width: 70; height: nsPanel.rowH; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: page.fmtMemShort(modelData.last); color: Theme.fgBright; font.family: Theme.monoFamily; font.pixelSize: Theme.tableText }
                    }
                }
            }

            Text {
                x: 16; y: 30; width: 300; height: 24
                verticalAlignment: Text.AlignVCenter
                visible: !nsPanel.hasData
                text: "no data"
                color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText
            }
            Text {
                x: 16; y: 22 + (nsPanel.maxRows - 1) * nsPanel.rowH
                width: 300; height: nsPanel.rowH
                verticalAlignment: Text.AlignVCenter
                visible: nsPanel.list.length > nsPanel.maxRows
                text: "+ " + (nsPanel.list.length - nsPanel.shownRows) + " more namespaces"
                color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText
            }
        }
    }

    // ==== recent events 126..684 (h 558) =================================
    //
    // Panel height budget (558):
    //   title bar     0 ..  28
    //   1px rule     28 ..  29
    //   list         33 .. 554  (521, clipped, scrolls: 58px rows -> ~9 fit)
    //   slack       554 .. 558  (4)
    // Rows are two lines (reason + namespace/object) so nothing is elided to
    // the point of being unidentifiable. "warn" is spelled out, never a hue.
    Panel {
        id: eventsPanel
        x: page.colRightX
        y: 126
        width: page.colRightW
        height: 558
        title: "Recent events"
        note: page.events.length + (page.events.length > 9 ? " · scroll" : "")

        ListView {
            id: eventList
            x: 8
            y: page.contentTop
            width: eventsPanel.width - 16
            height: 521
            clip: true
            spacing: 0
            model: page.events
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            delegate: Item {
                width: eventList.width - 12
                height: 58

                Rectangle { x: 0; y: 57; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 0; y: 2; width: parent.width - 66; height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.reason
                    color: modelData.warning ? Theme.warn : Theme.fgBright
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }
                Text {
                    x: parent.width - 60; y: 2; width: 60; height: 24
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    visible: modelData.warning
                    text: "warn"
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 0; y: 28; width: parent.width; height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.namespace + "/" + modelData.obj
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideMiddle
                }
            }
        }

        Text {
            x: 10; y: 60; width: eventsPanel.width - 20; height: 26
            visible: page.events.length === 0
            text: "no recent events"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }
}

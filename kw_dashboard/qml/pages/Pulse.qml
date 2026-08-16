import QtQuick 2.15
import "../"

// Throughput + CPU trend + recent-events feed. Content is distributed down
// the FULL panel height on purpose — an earlier cut wasted the bottom half.
Item {
    id: root
    anchors.fill: parent

    Text {
        id: title
        text: "PULSE"
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
    }

    Text {
        id: clock
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 24

        function refresh() { text = Qt.formatTime(new Date(), "hh:mm") }
        Component.onCompleted: refresh()
        Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.refresh() }
    }

    // ---- stat row: NET RX / NET TX / WARN EVENTS ----------------------
    Row {
        id: stats
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.topMargin: 28
        anchors.leftMargin: 24
        spacing: 64

        Column {
            spacing: 4
            Text {
                text: (root.netRxMB).toFixed(1) + " MB/s"
                color: Theme.fgBright
                font.family: Theme.fontFamily
                font.pixelSize: Theme.huge
            }
            Text { text: "NET RX"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.small }
        }
        Column {
            spacing: 4
            Text {
                text: (root.netTxMB).toFixed(1) + " MB/s"
                color: Theme.fgBright
                font.family: Theme.fontFamily
                font.pixelSize: Theme.huge
            }
            Text { text: "NET TX"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.small }
        }
        Column {
            spacing: 4
            Text {
                text: root.warnCount
                color: root.warnCount > 0 ? Theme.warn : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.huge
            }
            Text { text: "WARN EVENTS"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.small }
        }
    }

    readonly property real netRxMB: bridge.netRx / 1e6
    readonly property real netTxMB: bridge.netTx / 1e6
    readonly property int warnCount: {
        var n = 0
        var evs = bridge.events || []
        for (var i = 0; i < evs.length; i++) if (evs[i].warning) n++
        return n
    }

    // ---- CPU sparkline, given real vertical room -----------------------
    Item {
        id: sparkArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: stats.bottom
        anchors.topMargin: 32
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: 160

        Canvas {
            id: spark
            anchors.fill: parent
            property var hist: bridge.cpuHistory || []
            onHistChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var h = hist
                if (h.length < 2) return
                var w = width, ht = height
                ctx.strokeStyle = Theme.accent
                ctx.lineWidth = 3
                ctx.beginPath()
                for (var i = 0; i < h.length; i++) {
                    var x = (i / (h.length - 1)) * w
                    var y = ht - (Math.max(0, Math.min(100, h[i])) / 100) * ht
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
            }
        }
    }

    // ---- recent events, fills the rest of the panel --------------------
    Text {
        id: feedTitle
        text: "RECENT EVENTS"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.small
        anchors.left: parent.left
        anchors.top: sparkArea.bottom
        anchors.topMargin: 24
        anchors.leftMargin: 24
    }

    ListView {
        id: feed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: feedTitle.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.topMargin: 8
        clip: true
        spacing: 4
        model: bridge.events || []
        boundsBehavior: Flickable.StopAtBounds

        delegate: Row {
            spacing: 16
            width: feed.width
            height: 34

            Text {
                text: modelData.reason
                color: modelData.warning ? Theme.warn : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                width: 260
                elide: Text.ElideRight
            }
            Text {
                text: modelData.namespace + "/" + modelData.obj
                color: modelData.warning ? Theme.warn : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                elide: Text.ElideRight
                width: feed.width - 280
            }
        }
    }
}

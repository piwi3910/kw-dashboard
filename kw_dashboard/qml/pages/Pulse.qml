import QtQuick 2.15
import "../"

// Throughput + CPU trend + recent-events feed. Content is distributed down
// the FULL panel height on purpose — an earlier cut wasted the bottom half.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.bg

    PageHeader {
        id: header
        title: "PULSE"
        rightText: root.clockText
    }

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.clockText = Qt.formatTime(new Date(), "hh:mm") }

    // ---- stat row: NET RX / NET TX / WARN EVENTS ----------------------
    // Values use Theme.big rather than Theme.huge: at huge (120px) the two
    // "N.N MB/s" strings alone run past 1280px combined with the WARN
    // EVENTS column, pushing it off the right edge. Theme.big keeps the
    // row comfortably inside the 1280px canvas with room to spare.
    Row {
        id: stats
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.topMargin: 28
        anchors.leftMargin: 24
        spacing: 64

        Column {
            spacing: 4
            Text {
                text: (root.netRxMB).toFixed(1) + " MB/s"
                color: Theme.fgBright
                font.family: Theme.fontFamily
                font.pixelSize: Theme.big
            }
            Text { text: "NET RX"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.small }
        }
        Column {
            spacing: 4
            Text {
                text: (root.netTxMB).toFixed(1) + " MB/s"
                color: Theme.fgBright
                font.family: Theme.fontFamily
                font.pixelSize: Theme.big
            }
            Text { text: "NET TX"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.small }
        }
        Column {
            spacing: 4
            Text {
                text: root.warnCount
                color: root.warnCount > 0 ? Theme.warn : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.big
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
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var h = hist
                if (h.length < 2) return
                var w = width, ht = height
                ctx.strokeStyle = Theme.accent
                ctx.lineWidth = 3
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
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

        // A history array too short to plot (<2 points) used to leave the
        // Canvas blank, which reads as a flat/dead line rather than "no
        // data" — call it out explicitly instead.
        Text {
            anchors.centerIn: parent
            visible: spark.hist.length < 2
            text: "no data yet"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
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

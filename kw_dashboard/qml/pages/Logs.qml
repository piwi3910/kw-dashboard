import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// Container logs: three aligned columns — dim timestamp, colour-coded level,
// message — framed in the same panel chrome as every other page.
//
// Theme.mono (20px) is the ONE deliberate exception to the 26px glanceable
// floor: 26px monospace fits only ~78 columns across 1264px, which turns
// every real log line into a wrapped mess. Reading logs is a lean-in
// activity. Lines WRAP; the view never scrolls horizontally.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb    0 ..  84  (84, holds Main.qml's back button)
//   gap          84 ..  88  (4)
//   log panel    88 .. 600  (512)
//   gap         600 .. 612  (12)
//   controls    612 .. 672  (60, both >= touch floor)
// Panel height budget (512):
//   title bar     0 ..  28
//   1px rule     28 ..  29
//   list         33 .. 506  (473, clipped, rows are content-sized)
//   slack       506 .. 512  (6)
// Column x budget (list-local, rows are list width - 12 for the scrollbar):
//   ts 0 (tsW, measured) | level tsW+14 (levelW) | message (rest, wrapped)
// Both leading columns are sized, not hardcoded:
//   * tsW is a TextMetrics measurement of "00:00:00.000" — the timestamp is
//     rendered as TIME OF DAY only. The full ISO stamp did not fit and elided
//     to "2026-08-17T13:10:05.959…", which spent 290px to hide the one part
//     that matters. On a live tail every line is from today, so the date is
//     noise. The underlying data is untouched; this is display only.
//   * levelW collapses to 0 when NO line in the buffer parses a leading level
//     word, and the message column absorbs it. Real logs from this cluster
//     carry severity INSIDE the message (`[RUNNER … INFO Terminal]`), which is
//     the application's own format — we refuse to guess severity from a
//     substring (mis-reporting it would be worse than not showing it), so the
//     column would otherwise sit empty and waste ~250px. Whenever at least one
//     line does have a real leading level, the column comes back at full width
//     so the levels stay aligned with each other.
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property string ns: bridge.viewParams.ns || ""
    readonly property string podName: bridge.viewParams.pod || ""
    readonly property string container: bridge.viewParams.container || ""

    property bool loaded: false
    property bool live: true
    property var lines: []

    // A failed fetch and an empty container must never look the same.
    readonly property var errs: bridge.errors || ({})
    readonly property string fetchError: (loaded && lines.length === 0 && errs["kube"]) ? String(errs["kube"]) : ""

    // One regex, used both for the per-row split and for the "does anything in
    // this buffer have a level at all?" question below, so the column can never
    // disagree with the rows it is sizing for.
    // Built with `new RegExp` rather than a literal: a binding that starts with
    // `/` is asking the QML parser to disambiguate regex from division.
    readonly property var levelRe: new RegExp("^(\\S+)\\s+(INFO|WARN|ERROR|DEBUG)\\s+(.*)$")

    // Computed over the WHOLE buffer rather than just the rows on screen: a
    // width that changed as you scrolled would make the columns jump under the
    // reader's eye, which is worse than the wasted space it saves.
    readonly property bool hasLevels: {
        for (var i = 0; i < page.lines.length; i++)
            if (page.levelRe.test(page.lines[i])) return true
        return false
    }
    readonly property int tsW: Math.ceil(tsMetrics.width) + 2
    readonly property int levelW: hasLevels ? 70 : 0
    readonly property int msgX: tsW + 14 + (levelW > 0 ? levelW + 14 : 0)

    TextMetrics {
        id: tsMetrics
        font.family: Theme.monoFamily
        font.pixelSize: Theme.mono
        text: "00:00:00.000"
    }

    // Time of day, milliseconds kept (log lines land inside the same second
    // often enough that dropping them would lose the ordering cue). A stamp
    // that is not ISO-with-a-T is shown as-is rather than mangled.
    function fmtTime(ts) {
        var m = /T(\d{2}:\d{2}:\d{2})(\.\d{1,3})?/.exec(ts)
        return m ? m[1] + (m[2] ? m[2] : "") : ts
    }

    function refreshLines() {
        page.lines = bridge.logLines() || []
        if (page.live) Qt.callLater(function () { logList.positionViewAtEnd() })
    }

    function onLogsFetched(fns, fpod, fcontainer) {
        if (fns === page.ns && fpod === page.podName && fcontainer === page.container) {
            page.loaded = true
            page.refreshLines()
        }
    }

    Component.onCompleted: {
        refreshLines()
        bridge.logsFetched.connect(onLogsFetched)
    }
    Component.onDestruction: bridge.logsFetched.disconnect(onLogsFetched)

    PageHeader {
        id: header
        height: 84
        crumbX: 104
        parentCrumb: page.podName
        crumb: page.container.length > 0 ? page.container : "logs"
        chips: [
            { "text": page.ns },
            { "text": page.live ? "following" : "paused", "color": page.live ? Theme.ok : Theme.dim }
        ]
    }

    Panel {
        id: logPanel
        x: 8
        y: 88
        width: 1264
        height: 512
        title: "Container logs"
        note: !page.loaded ? "loading…" : (page.lines.length + " lines")
        noteColor: page.fetchError.length > 0 ? Theme.crit : Theme.dimmer

        ListView {
            id: logList
            visible: page.loaded && page.lines.length > 0
            x: 8
            y: logPanel.contentTop
            width: logPanel.width - 16
            height: 473
            clip: true
            spacing: 2
            model: page.lines
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            // Dragging away from the tail pauses follow; LIVE resumes it.
            onMovementStarted: if (!atYEnd) page.live = false

            delegate: Item {
                id: lrow
                width: logList.width - 12
                height: Math.max(26, msgText.contentHeight)

                readonly property var parsed: {
                    // Kubelet prefixes "<RFC3339> <raw line>"; the container's
                    // own text may or may not carry a level word.
                    var m = page.levelRe.exec(modelData)
                    if (m) return { "ts": m[1], "level": m[2], "msg": m[3] }
                    var sp = modelData.indexOf(" ")
                    if (sp < 0) return { "ts": modelData, "level": "", "msg": "" }
                    return { "ts": modelData.slice(0, sp), "level": "", "msg": modelData.slice(sp + 1) }
                }
                readonly property color levelColor: parsed.level === "ERROR" ? Theme.crit
                    : (parsed.level === "WARN" ? Theme.warn : Theme.dim)

                Text {
                    x: 0; y: 0; width: page.tsW; height: 26
                    text: page.fmtTime(lrow.parsed.ts)
                    color: Theme.dim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.mono
                    elide: Text.ElideRight
                }
                Text {
                    visible: page.levelW > 0
                    x: page.tsW + 14; y: 0; width: page.levelW; height: 26
                    text: lrow.parsed.level
                    color: lrow.levelColor
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.mono
                }
                Text {
                    id: msgText
                    x: page.msgX; y: 0
                    width: lrow.width - page.msgX
                    text: lrow.parsed.msg
                    color: Theme.fg
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.mono
                    wrapMode: Text.Wrap
                }
            }
        }

        // ---- loading / error / empty, all inside the panel body ----------
        Text {
            visible: !page.loaded
            x: 10; y: 200; width: logPanel.width - 20; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "loading…"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
        Text {
            visible: page.fetchError.length > 0
            x: 10; y: 200; width: logPanel.width - 20; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "log fetch failed"
            color: Theme.crit
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
        Text {
            visible: page.fetchError.length > 0
            x: 10; y: 246; width: logPanel.width - 20; height: 30
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: page.fetchError
            color: Theme.dim
            font.family: Theme.monoFamily
            font.pixelSize: Theme.mono
            elide: Text.ElideRight
        }
        Text {
            visible: page.loaded && page.lines.length === 0 && page.fetchError.length === 0
            x: 10; y: 200; width: logPanel.width - 20; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "no log lines received"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
    }

    // ==== controls 612..672 ==============================================
    Rectangle {
        id: scrollUpBtn
        x: 1066
        y: 612
        width: 90
        height: 60
        radius: 3
        color: Theme.panelAlt
        border.color: Theme.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "↑"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.glance
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                page.live = false
                logList.contentY = Math.max(0, logList.contentY - 300)
            }
        }
    }

    Rectangle {
        id: liveBtn
        x: 1166
        y: 612
        width: 90
        height: 60
        radius: 3
        color: Theme.panelAlt
        border.color: page.live ? Theme.ok : Theme.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "LIVE"
            color: page.live ? Theme.ok : Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.glance
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                page.live = true
                logList.positionViewAtEnd()
            }
        }
    }

    Text {
        x: 8; y: 612; width: 1000; height: 60
        verticalAlignment: Text.AlignVCenter
        text: "read-only tail · scroll up to pause following, LIVE to resume"
        color: Theme.dimmer
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
        elide: Text.ElideRight
    }
}

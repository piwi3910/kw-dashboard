import QtQuick 2.15
import "../"

// Three aligned columns: dim timestamp, colour-coded level, then message.
// The one deliberate exception to the 26px floor — mono/20px fits ~78
// columns, and reading logs is a lean-in activity. Lines wrap, never scroll
// horizontally.
Item {
    id: root
    anchors.fill: parent

    readonly property string ns: bridge.viewParams.ns || ""
    readonly property string podName: bridge.viewParams.pod || ""
    readonly property string container: bridge.viewParams.container || ""
    property bool loaded: false
    property bool live: true
    property var lines: []

    function refreshLines() {
        root.lines = bridge.logLines() || []
        if (root.live) Qt.callLater(function () { list.positionViewAtEnd() })
    }

    function onLogsFetched(fns, fpod, fcontainer) {
        if (fns === root.ns && fpod === root.podName && fcontainer === root.container) {
            root.loaded = true
            root.refreshLines()
        }
    }

    Component.onCompleted: {
        refreshLines()
        bridge.logsFetched.connect(onLogsFetched)
    }
    Component.onDestruction: bridge.logsFetched.disconnect(onLogsFetched)

    Text {
        id: title
        text: root.podName + "/" + root.container
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.small
        anchors.left: parent.left
        anchors.leftMargin: 110
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.top: parent.top
        anchors.topMargin: 24
        elide: Text.ElideRight
    }

    // ---- loading / empty states -----------------------------------------
    Text {
        visible: !root.loaded
        anchors.centerIn: parent
        text: "loading…"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
    }

    Text {
        visible: root.loaded && root.lines.length === 0
        anchors.centerIn: parent
        text: "no log lines received"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
    }

    // ---- log lines ---------------------------------------------------
    ListView {
        id: list
        visible: root.loaded && root.lines.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 20
        anchors.topMargin: 12
        anchors.bottomMargin: 84
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.lines

        // Manual scroll pauses follow; jumping back to LIVE resumes it.
        onMovementStarted: if (!atYEnd) root.live = false

        delegate: Row {
            width: list.width
            height: implicitHeight
            spacing: 14

            readonly property var parsed: {
                // Kubelet timestamps lines as "<RFC3339> <raw line>"; the
                // container's own text may or may not carry a level word.
                var m = /^(\S+)\s+(INFO|WARN|ERROR|DEBUG)\s+(.*)$/.exec(modelData)
                if (m) return {ts: m[1], level: m[2], msg: m[3]}
                var sp = modelData.indexOf(" ")
                if (sp < 0) return {ts: modelData, level: "", msg: ""}
                return {ts: modelData.slice(0, sp), level: "", msg: modelData.slice(sp + 1)}
            }

            function levelColor(lvl) {
                if (lvl === "ERROR") return Theme.crit
                if (lvl === "WARN") return Theme.warn
                return Theme.dim
            }

            Text {
                text: parsed.ts
                color: Theme.dim
                font.family: Theme.monoFamily
                font.pixelSize: Theme.mono
                width: 300
                elide: Text.ElideRight
            }
            Text {
                text: parsed.level
                color: levelColor(parsed.level)
                font.family: Theme.monoFamily
                font.pixelSize: Theme.mono
                width: 70
            }
            Text {
                text: parsed.msg
                color: Theme.fg
                font.family: Theme.monoFamily
                font.pixelSize: Theme.mono
                width: list.width - 300 - 70 - 28
                wrapMode: Text.Wrap
            }
        }
    }

    // ---- scroll-up + LIVE controls, both >= touchMin --------------------
    Rectangle {
        id: scrollUpBtn
        width: 90
        height: Theme.touchMin
        radius: 8
        color: Theme.panelAlt
        anchors.right: liveBtn.left
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20

        Text {
            anchors.centerIn: parent
            text: "↑"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.live = false
                list.contentY = Math.max(0, list.contentY - 300)
            }
        }
    }

    Rectangle {
        id: liveBtn
        width: 90
        height: Theme.touchMin
        radius: 8
        color: Theme.panelAlt
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20

        Text {
            anchors.centerIn: parent
            text: "LIVE"
            color: root.live ? Theme.ok : Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.live = true
                list.positionViewAtEnd()
            }
        }
    }
}

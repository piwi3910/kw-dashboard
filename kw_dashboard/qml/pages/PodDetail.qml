import QtQuick 2.15
import "../"

// Pod facts, then one tappable "logs: <container>" row per container.
// Every container is listed — a cap here would make sidecar logs unreachable.
Item {
    id: root
    anchors.fill: parent

    readonly property string ns: bridge.viewParams.ns || ""
    readonly property string podName: bridge.viewParams.pod || ""
    readonly property var pod: {
        var ps = bridge.pods || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].namespace === root.ns && ps[i].name === root.podName) return ps[i]
        return null
    }
    readonly property var facts: root.pod ? [
        {label: "PHASE", value: root.pod.phase, color: Theme.fgBright},
        {label: "READY", value: root.pod.ready + "/" + root.pod.total, color: Theme.fgBright},
        {label: "RESTARTS", value: String(root.pod.restarts),
         color: root.pod.restarts > 0 ? Theme.crit : Theme.fgBright},
        {label: "NODE", value: root.pod.node, color: Theme.fgBright}
    ] : []

    Text {
        id: title
        text: root.ns + "/" + root.podName
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        anchors.left: parent.left
        anchors.leftMargin: 110
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.top: parent.top
        anchors.topMargin: 24
        elide: Text.ElideRight
    }

    Column {
        id: factColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.topMargin: 28
        anchors.leftMargin: 24
        spacing: 12

        Repeater {
            model: root.facts
            delegate: Row {
                spacing: 24
                Text {
                    text: modelData.label
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    width: 220
                }
                Text {
                    text: modelData.value
                    color: modelData.color
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                }
            }
        }
    }

    ListView {
        id: containerList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: factColumn.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.topMargin: 24
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: root.pod ? root.pod.containers : []

        delegate: Rectangle {
            width: containerList.width
            height: Theme.touchMin
            radius: 8
            color: Theme.panelAlt

            Text {
                text: "logs: " + modelData
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - 80
            }
            Text {
                text: ">"
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    bridge.fetchLogs(root.ns, root.podName, modelData)
                    bridge.pushView("logs", {"ns": root.ns, "pod": root.podName, "container": modelData})
                }
            }
        }
    }
}

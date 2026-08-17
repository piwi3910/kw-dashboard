import QtQuick 2.15
import "../"

// Single node: conditions, CPU/mem/temp, and the pods scheduled on it.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.bg

    readonly property string nodeName: bridge.viewParams.node || ""
    readonly property var node: {
        var ns = bridge.nodes || []
        for (var i = 0; i < ns.length; i++) if (ns[i].name === root.nodeName) return ns[i]
        return null
    }
    readonly property var nodePods: {
        var out = []
        var ps = bridge.pods || []
        for (var i = 0; i < ps.length; i++) if (ps[i].node === root.nodeName) out.push(ps[i])
        return out
    }

    // Header title kept clear of the global back button in Main.qml.
    Text {
        id: title
        text: root.nodeName
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        anchors.left: parent.left
        anchors.leftMargin: 110
        anchors.top: parent.top
        anchors.topMargin: 24
    }

    Text {
        text: root.node ? (root.node.ready ? "READY" : "NOT READY") : ""
        color: root.node && root.node.ready ? Theme.ok : Theme.crit
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.top: parent.top
        anchors.topMargin: 24
    }

    // ---- CPU / MEMORY / TEMP bars ---------------------------------------
    Column {
        id: bars
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.topMargin: 32
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 18

        Repeater {
            model: root.node ? [
                {label: "CPU", pct: root.node.cpuPct, text: Math.round(root.node.cpuPct) + "%"},
                {label: "MEMORY", pct: root.node.memPct, text: Math.round(root.node.memPct) + "%"},
                {label: "TEMP", pct: root.node.tempC < 0 ? 0 : root.node.tempC,
                 text: root.node.tempC < 0 ? "—" : (Math.round(root.node.tempC) + " C")}
            ] : []

            delegate: Row {
                width: bars.width
                height: 30
                spacing: 20

                Text {
                    text: modelData.label
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    width: 160
                    verticalAlignment: Text.AlignVCenter
                    height: parent.height
                }

                Rectangle {
                    width: 700
                    height: 26
                    radius: 6
                    color: Theme.panelAlt
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        height: parent.height
                        radius: 6
                        width: parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100
                        color: Theme.stateColor(modelData.pct)
                        Behavior on width { NumberAnimation { duration: 250 } }
                    }
                }

                Text {
                    text: modelData.text
                    color: Theme.fgBright
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                    verticalAlignment: Text.AlignVCenter
                    height: parent.height
                }
            }
        }
    }

    Text {
        id: podsHeader
        text: root.nodePods.length + (root.nodePods.length === 1 ? " pod" : " pods")
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.small
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.top: bars.bottom
        anchors.topMargin: 24
    }

    ListView {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: podsHeader.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.topMargin: 12
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: root.nodePods

        delegate: Rectangle {
            width: ListView.view.width
            height: 60
            radius: 8
            color: Theme.panelAlt

            Text {
                text: modelData.namespace + "/" + modelData.name
                color: modelData.healthy ? Theme.fg : Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - 160
            }
            Text {
                text: modelData.ready + "/" + modelData.total
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
            }
            MouseArea {
                anchors.fill: parent
                onClicked: bridge.pushView("podDetail", {"ns": modelData.namespace, "pod": modelData.name})
            }
        }
    }
}

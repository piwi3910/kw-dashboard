import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// Namespace list — unhealthy namespaces first and named in crit red. 27
// namespaces on the real cluster and only ~9 rows fit, so this MUST scroll:
// a ListView with a visible scrollbar, never a silently truncated list.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.bg

    readonly property var sortedNamespaces: {
        var list = (bridge.namespaces || []).slice()
        list.sort(function (a, b) {
            if ((a.unhealthy > 0) !== (b.unhealthy > 0))
                return (b.unhealthy > 0) - (a.unhealthy > 0)
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
        })
        return list
    }

    function fmtMem(bytes) {
        if (bytes >= 1e9) return (bytes / 1e9).toFixed(1) + " GB"
        return (bytes / 1e6).toFixed(1) + " MB"
    }

    PageHeader {
        id: header
        title: "NAMESPACES"
        rightText: String(root.sortedNamespaces.length)
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.topMargin: 16
        clip: true
        spacing: 10
        model: root.sortedNamespaces
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOn
            width: 10
        }

        delegate: Rectangle {
            width: list.width - 16
            height: 74
            radius: 10
            color: Theme.panelAlt
            border.color: Theme.border

            Text {
                text: modelData.name
                color: modelData.unhealthy > 0 ? Theme.crit : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                spacing: 32
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: modelData.pods + " pods"
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                }
                Text {
                    text: root.fmtMem(modelData.memBytes)
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.small
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bridge.pushView("namespaceDetail", {"ns": modelData.name})
            }
        }
    }
}

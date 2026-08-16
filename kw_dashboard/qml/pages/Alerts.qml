import QtQuick 2.15
import "../"

// Alertmanager is the source of truth; this panel only shows what's firing
// and can dismiss the on-screen takeover — it can never silence upstream.
Rectangle {
    id: root
    anchors.fill: parent
    color: Theme.bg

    readonly property var alerts: bridge.alerts || []
    readonly property bool empty: alerts.length === 0

    function sevColor(sev) {
        var s = (sev || "").toLowerCase()
        if (s === "critical") return Theme.crit
        if (s === "warning") return Theme.warn
        return Theme.dim
    }

    PageHeader {
        id: header
        title: "ALERTS"
        rightText: Qt.formatTime(new Date(), "hh:mm")

        function refresh() { rightText = Qt.formatTime(new Date(), "hh:mm") }
        Timer { interval: 1000; running: true; repeat: true; onTriggered: header.refresh() }
    }

    // ---- calm "all quiet" state -----------------------------------------
    Column {
        visible: root.empty
        anchors.centerIn: parent
        spacing: 12

        Text {
            text: "all quiet"
            color: Theme.ok
            font.family: Theme.fontFamily
            font.pixelSize: Theme.huge
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "no alerts firing"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ---- firing state: ranked alert list ---------------------------------
    ListView {
        id: list
        visible: !root.empty
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: dismiss.top
        anchors.margins: 24
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        clip: true
        spacing: 14
        boundsBehavior: Flickable.StopAtBounds

        // Cap the visible rows so "+N more" is honest about what's cut —
        // never truncate silently.
        readonly property int maxVisible: 4
        model: root.alerts.slice(0, maxVisible)

        footer: Item {
            width: list.width
            height: root.alerts.length > list.maxVisible ? 44 : 0
            visible: root.alerts.length > list.maxVisible
            Text {
                anchors.centerIn: parent
                text: "+" + (root.alerts.length - list.maxVisible) + " more"
                color: Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
            }
        }

        delegate: Rectangle {
            width: list.width
            height: 140
            radius: 10
            color: Theme.panelAlt

            Rectangle {
                width: 6
                height: parent.height
                radius: 3
                color: root.sevColor(modelData.severity)
                anchors.left: parent.left
            }

            Text {
                text: modelData.name
                color: Theme.fgBright
                font.family: Theme.fontFamily
                font.pixelSize: Theme.body
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.top: parent.top
                anchors.topMargin: 24
            }
            Text {
                text: modelData.summary
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.top: parent.top
                anchors.topMargin: 64
                width: parent.width - 260
                elide: Text.ElideRight
            }
            Text {
                // Severity is always spelled out as text, coloured — never
                // colour alone, so it stays legible to red/green colour-blind viewers.
                text: (modelData.severity || "").toUpperCase()
                color: root.sevColor(modelData.severity)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.top: parent.top
                anchors.topMargin: 24
            }
        }
    }

    // ---- dismiss: clears only the on-screen takeover ----------------------
    Rectangle {
        id: dismiss
        visible: !root.empty
        width: 180
        height: Theme.touchMin
        radius: 10
        color: Theme.panelAlt
        border.color: Theme.border
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24

        Text {
            anchors.centerIn: parent
            text: "DISMISS"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: bridge.clearPreempt()
        }
    }
}

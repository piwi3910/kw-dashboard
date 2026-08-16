import QtQuick 2.15
import "../"

// One namespace's pods, fetched on demand via bridge.fetchPods (async —
// podsFetched(ns, pods) arrives later). Unhealthy pods sort first.
Item {
    id: root
    anchors.fill: parent

    readonly property string ns: bridge.viewParams.ns || ""
    property bool loaded: false
    property var podList: []
    readonly property bool fetchFailed: loaded && podList.length === 0 && !!bridge.errors["kube"]

    readonly property var sortedPods: {
        var list = root.podList.slice()
        list.sort(function (a, b) {
            if (a.healthy !== b.healthy) return a.healthy ? 1 : -1
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
        })
        return list
    }

    function onPodsFetched(fns, pods) {
        if (fns === root.ns) {
            root.loaded = true
            root.podList = pods || []
        }
    }

    Component.onCompleted: {
        bridge.podsFetched.connect(onPodsFetched)
        bridge.fetchPods(root.ns)
    }
    Component.onDestruction: bridge.podsFetched.disconnect(onPodsFetched)

    Text {
        id: title
        text: root.ns
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        anchors.left: parent.left
        anchors.leftMargin: 110
        anchors.top: parent.top
        anchors.topMargin: 24
    }

    // Back affordance: Main.qml's global "‹ Back" button (>=60px, top-left,
    // calls bridge.popView()) already covers this — same pattern as
    // NodeDetail.qml, header text starts at x=110 to stay clear of it.

    // ---- loading / empty / error states ---------------------------------
    Text {
        visible: !root.loaded
        anchors.centerIn: parent
        text: "loading…"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
    }

    Text {
        visible: root.fetchFailed
        anchors.centerIn: parent
        text: "failed to load pods"
        color: Theme.crit
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
    }

    Text {
        visible: root.loaded && !root.fetchFailed && root.podList.length === 0
        anchors.centerIn: parent
        text: "no pods"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
    }

    // ---- pod list, MUST scroll: some namespaces have 30+ pods -----------
    ListView {
        visible: root.loaded && !root.fetchFailed && root.podList.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.topMargin: 16
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: root.sortedPods

        delegate: Rectangle {
            width: ListView.view.width
            height: Theme.touchMin
            radius: 8
            color: Theme.panelAlt

            Text {
                text: modelData.name
                color: modelData.healthy ? Theme.fg : Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: parent.width - 420
            }
            Text {
                text: modelData.phase
                color: modelData.healthy ? Theme.dim : Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.right: restarts.left
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: restarts
                text: modelData.restarts + " restarts"
                color: modelData.restarts > 0 ? Theme.crit : Theme.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.right: ready.left
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: ready
                text: modelData.ready + "/" + modelData.total
                color: modelData.healthy ? Theme.fg : Theme.crit
                font.family: Theme.fontFamily
                font.pixelSize: Theme.small
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bridge.pushView("podDetail", {"ns": root.ns, "pod": modelData.name})
            }
        }
    }
}

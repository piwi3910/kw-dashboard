import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// One namespace's pods, fetched on demand via bridge.fetchPods — ASYNC, the
// podsFetched(ns, pods) signal arrives later. Unhealthy pods sort first.
//
// Same idiom as every other page (breadcrumb + panel + dense table). Not in
// the original six, but it is one tap from Explore, so leaving it on the old
// styling would have kept a visible seam in the product.
//
// An empty namespace and a FAILED fetch must never look the same: the empty
// case says "no pods", the failure says so in crit and names the error.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb    0 ..  84  (84, holds Main.qml's back button)
//   gap          84 ..  88  (4)
//   pods panel   88 .. 684  (596)
// Panel height budget (596):
//   title bar     0 ..  28
//   1px rule     28 ..  29
//   col header   29 ..  54  (25)
//   1px rule     54 ..  55
//   list         55 .. 590  (535, clipped, 33px rows -> 16 fit, scrolls)
//   slack       590 .. 596  (6)
// Column x budget (panel-local, rows are panel width - 12 for the
// scrollbar): pod 8 (560) | phase 576 (170) | ready 754 (100,r)
//   | restarts 862 (160,r) | node 1030 (214) -> ends 1244
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property string ns: bridge.viewParams.ns || ""
    readonly property int rowH: 33

    property bool loaded: false
    property var podList: []

    readonly property var errs: bridge.errors || ({})
    readonly property string fetchError: (loaded && podList.length === 0 && errs["kube"]) ? String(errs["kube"]) : ""

    readonly property var sortedPods: {
        var list = page.podList.slice()
        list.sort(function (a, b) {
            if (a.healthy !== b.healthy) return a.healthy ? 1 : -1
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
        })
        return list
    }

    function onPodsFetched(fns, pods) {
        if (fns === page.ns) {
            page.loaded = true
            page.podList = pods || []
        }
    }

    Component.onCompleted: {
        bridge.podsFetched.connect(onPodsFetched)
        bridge.fetchPods(page.ns)
    }
    Component.onDestruction: bridge.podsFetched.disconnect(onPodsFetched)

    PageHeader {
        id: header
        height: 84
        crumbX: 104
        parentCrumb: "namespaces"
        crumb: page.ns.length > 0 ? page.ns : "namespace"
        chips: [
            { "text": page.loaded ? page.podList.length + " pods" : "loading…",
              "color": page.loaded ? Theme.fgMuted : Theme.warn }
        ]
    }

    Panel {
        id: podsPanel
        x: 8
        y: 88
        width: 1264
        height: 596
        title: "Pods"
        note: !page.loaded ? "loading…"
            : (page.fetchError.length > 0 ? "fetch failed"
               : page.sortedPods.length + " rows" + (page.sortedPods.length > 16 ? " · scroll" : ""))
        noteColor: page.fetchError.length > 0 ? Theme.crit : Theme.dimmer

        Item {
            x: 0; y: 29; width: podsPanel.width; height: 25
            Text { x: 8;    y: 0; width: 560; height: 25; verticalAlignment: Text.AlignVCenter; text: "pod";      color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 576;  y: 0; width: 170; height: 25; verticalAlignment: Text.AlignVCenter; text: "phase";    color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 754;  y: 0; width: 100; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "ready";    color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 862;  y: 0; width: 160; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "restarts"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 1030; y: 0; width: 214; height: 25; verticalAlignment: Text.AlignVCenter; text: "node";     color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: podsPanel.width - 2; height: 1; color: Theme.bgAlt }

        ListView {
            id: podsList
            visible: page.loaded && page.sortedPods.length > 0
            x: 0
            y: 55
            width: podsPanel.width
            height: 535
            clip: true
            spacing: 0
            model: page.sortedPods
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            delegate: Item {
                id: podRow
                width: podsList.width - 12
                height: page.rowH

                readonly property bool bad: !modelData.healthy

                Rectangle {
                    anchors.fill: parent
                    color: podRow.bad ? Qt.rgba(0.890, 0.416, 0.416, 0.07) : "transparent"
                }
                Rectangle { x: 0; y: page.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 8; y: 0; width: 560; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: podRow.bad ? Theme.crit : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideMiddle
                }
                StatePill {
                    x: 576
                    y: (page.rowH - 24) / 2
                    text: (modelData.phase || "unknown").toLowerCase()
                    textColor: podRow.bad ? Theme.crit : Theme.ok
                }
                Text {
                    x: 754; y: 0; width: 100; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.ready + "/" + modelData.total
                    color: podRow.bad ? Theme.crit : Theme.fgMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 862; y: 0; width: 160; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.restarts
                    color: modelData.restarts > 0 ? Theme.warn : Theme.dim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 1030; y: 0; width: 214; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.node
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }

                // read-only: navigates to the pod detail view only.
                TapHandler {
                    onTapped: bridge.pushView("podDetail", { "ns": page.ns, "pod": modelData.name })
                }
            }
        }

        // ---- loading / error / empty, all inside the panel body -----------
        Text {
            visible: !page.loaded
            x: 8; y: 70; width: podsPanel.width - 16; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "loading pods…"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
        Text {
            visible: page.fetchError.length > 0
            x: 8; y: 70; width: podsPanel.width - 16; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "failed to load pods for " + page.ns
            color: Theme.crit
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
        Text {
            visible: page.fetchError.length > 0
            x: 8; y: 116; width: podsPanel.width - 16; height: 30
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: page.fetchError
            color: Theme.dim
            font.family: Theme.monoFamily
            font.pixelSize: Theme.mono
            elide: Text.ElideRight
        }
        Text {
            visible: page.loaded && page.podList.length === 0 && page.fetchError.length === 0
            x: 8; y: 70; width: podsPanel.width - 16; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "no pods in " + page.ns
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
    }
}

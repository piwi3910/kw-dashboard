import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// One pod: a fact panel, then one tappable row per container leading to that
// container's logs. EVERY container is listed (the list scrolls) — a cap here
// would make a sidecar's logs unreachable.
//
// Breadcrumb is 84px so Main.qml's global back button (x 12..92 / y 12..72,
// z:100) sits inside the bar; crumbs start at x=104.
//
// NOTE ON "age": the bridge's pod shape is {name, namespace, node, phase,
// ready, total, restarts, containers, healthy} — there is no age/start-time
// field, so the fifth fact is the container count rather than a column of
// permanent em-dashes. Add age here once the bridge exposes it.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb     0 ..  84  (84, holds Main.qml's back button)
//   gap           84 ..  88  (4)
//   fact panel    88 .. 212  (124)
//   gap          212 .. 216  (4)
//   containers   216 .. 684  (468)
// Fact panel height budget (124):
//   title bar      0 ..  28
//   1px rule      28 ..  29
//   labels        33 ..  55  (22)
//   values        57 ..  91  (34)
//   slack         91 .. 124  (33)
// Five fact columns at x 8 + i*251, each 248 wide -> ends 1260.
// Containers panel height budget (468):
//   title bar      0 ..  28
//   1px rule      28 ..  29
//   col header    29 ..  54  (25)
//   1px rule      54 ..  55
//   list          55 .. 462  (407, clipped, 60px rows -> 6 fit, scrolls)
//   slack        462 .. 468  (6)
// Container rows are 60px, not 33px: each one is a button (it navigates and
// kicks off a log fetch), so it gets the full touch floor.
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property string ns: bridge.viewParams.ns || ""
    readonly property string podName: bridge.viewParams.pod || ""
    readonly property int rowH: 60

    readonly property var pod: {
        var ps = bridge.pods || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].namespace === page.ns && ps[i].name === page.podName) return ps[i]
        return null
    }
    readonly property bool found: pod !== null
    readonly property var containers: found ? (pod.containers || []) : []

    readonly property var facts: found ? [
        { "label": "phase", "value": pod.phase,
          "color": pod.healthy ? Theme.fgBright : Theme.crit, "mono": false },
        { "label": "ready", "value": pod.ready + "/" + pod.total,
          "color": pod.ready === pod.total ? Theme.fgBright : Theme.crit, "mono": true },
        { "label": "restarts", "value": String(pod.restarts),
          "color": pod.restarts > 0 ? Theme.warn : Theme.fgBright, "mono": true },
        { "label": "node", "value": pod.node,
          "color": Theme.accent, "mono": false },
        { "label": "containers", "value": String((pod.containers || []).length),
          "color": Theme.fgBright, "mono": true }
    ] : [
        { "label": "phase", "value": "—", "color": Theme.dimmer, "mono": false },
        { "label": "ready", "value": "—", "color": Theme.dimmer, "mono": true },
        { "label": "restarts", "value": "—", "color": Theme.dimmer, "mono": true },
        { "label": "node", "value": "—", "color": Theme.dimmer, "mono": false },
        { "label": "containers", "value": "—", "color": Theme.dimmer, "mono": true }
    ]

    PageHeader {
        id: header
        height: 84
        crumbX: 104
        parentCrumb: page.ns
        crumb: page.podName.length > 0 ? page.podName : "pod"
        chips: [
            { "text": page.found ? (page.pod.phase || "unknown").toLowerCase() : "not in snapshot",
              "color": page.found ? (page.pod.healthy ? Theme.ok : Theme.crit) : Theme.crit },
            { "text": page.containers.length + " containers" }
        ]
    }

    // ==== fact panel 88..212 (h 124) =====================================
    Panel {
        id: factPanel
        x: 8
        y: 88
        width: 1264
        height: 124
        title: "Pod"
        note: page.found ? "read-only" : "not in the current snapshot"
        noteColor: page.found ? Theme.dimmer : Theme.crit

        Repeater {
            model: page.facts

            delegate: Item {
                x: 8 + index * 251
                y: 0
                width: 248
                height: factPanel.height

                Text {
                    x: 0; y: 33; width: 248; height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.label
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 0; y: 57; width: 248; height: 34
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.value
                    color: modelData.color
                    font.family: modelData.mono ? Theme.monoFamily : Theme.fontFamily
                    font.pixelSize: Theme.glance
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ==== containers 216..684 (h 468) ====================================
    Panel {
        id: containerPanel
        x: 8
        y: 216
        width: 1264
        height: 468
        title: "Containers"
        note: page.containers.length + " total" + (page.containers.length > 6 ? " · scroll" : "")

        Item {
            x: 0; y: 29; width: containerPanel.width; height: 25
            Text { x: 8;   y: 0; width: 880; height: 25; verticalAlignment: Text.AlignVCenter; text: "container"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 990; y: 0; width: 254; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "logs"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: containerPanel.width - 2; height: 1; color: Theme.bgAlt }

        ListView {
            id: containerList
            x: 0
            y: 55
            width: containerPanel.width
            height: 407
            clip: true
            spacing: 0
            model: page.containers
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            delegate: Item {
                width: containerList.width - 12
                height: page.rowH

                Rectangle { x: 0; y: page.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 8; y: 0; width: 880; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.fgBright
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.glance
                    elide: Text.ElideRight
                }
                Text {
                    x: 990; y: 0; width: 254; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: "view logs  ›"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }

                // Kick the async fetch off BEFORE pushing, so the logs view is
                // already waiting on logsFetched when it loads.
                TapHandler {
                    onTapped: {
                        bridge.fetchLogs(page.ns, page.podName, modelData)
                        bridge.pushView("logs", { "ns": page.ns, "pod": page.podName, "container": modelData })
                    }
                }
            }
        }

        Text {
            x: 8; y: 60; width: 800; height: 26
            visible: page.containers.length === 0
            verticalAlignment: Text.AlignVCenter
            text: page.found ? "this pod reports no containers"
                             : "pod " + page.ns + "/" + page.podName + " is not in the current snapshot"
            color: page.found ? Theme.dimmer : Theme.crit
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }
}

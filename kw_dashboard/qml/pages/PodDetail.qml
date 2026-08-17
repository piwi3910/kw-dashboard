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
//   containers   216 .. 216+containersH   CONTENT-SIZED (121 .. 301)
//   gap           4
//   pod events   eventsY .. 684           takes whatever is left
// Fact panel height budget (124):
//   title bar      0 ..  28
//   1px rule      28 ..  29
//   labels        33 ..  55  (22)
//   values        57 ..  91  (34)
//   slack         91 .. 124  (33)
// Five fact columns at x 8 + i*251, each 248 wide -> ends 1260.
//
// Containers panel is sized to its rows, not to the page: a one-container pod
// (the common case here) was leaving ~350px of empty panel below its single
// row, which reads as a broken panel rather than as "that is all there is".
//   containersH = 55 (title + rule + col header + rule) + rows * 60 + 6
//   rows        = min(N, 4), so it never grows past 301 and scrolls instead
// Container rows are 60px, not 33px: each one is a button (it navigates and
// kicks off a log fetch), so it gets the full touch floor.
//
// The reclaimed height goes to a Recent events panel filtered to this pod:
//   eventsY = 216 + containersH + 4  ->  341 (1 container) .. 521 (4+)
//   events panel height = 684 - eventsY  ->  343 .. 163
//   title 28 | rule 1 | list 33 .. h-6 (clipped, 58px two-line rows, scrolls)
// At the worst case (4+ containers) the events list still gets 124px = 2 rows
// and scrolls, so it is never a zero-height list.
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

    readonly property int maxContainerRows: 4
    readonly property int containerRows: Math.max(1, Math.min(containers.length, maxContainerRows))
    readonly property int containersH: 55 + containerRows * rowH + 6
    readonly property int eventsY: 216 + containersH + 4

    // Events for THIS pod: obj is the object's own name, so match it against
    // the pod name inside the pod's namespace. No fuzzy matching — an event
    // for a different object in the same namespace is not this pod's event.
    readonly property var podEvents: {
        var out = []
        var evs = bridge.events || []
        for (var i = 0; i < evs.length; i++)
            if (evs[i].obj === page.podName && evs[i].namespace === page.ns) out.push(evs[i])
        return out
    }

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

    // ==== containers 216.. (content-sized) ===============================
    Panel {
        id: containerPanel
        x: 8
        y: 216
        width: 1264
        height: page.containersH
        title: "Containers"
        note: page.containers.length + " total"
            + (page.containers.length > page.maxContainerRows ? " · scroll" : "")

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
            height: page.containerRows * page.rowH
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

    // ==== recent events for this pod, eventsY..684 =======================
    Panel {
        id: eventsPanel
        x: 8
        y: page.eventsY
        width: 1264
        height: 684 - page.eventsY
        title: "Recent events for this pod"
        note: page.podEvents.length + " matching"

        ListView {
            id: eventList
            visible: page.podEvents.length > 0
            x: 8
            y: eventsPanel.contentTop
            width: eventsPanel.width - 16
            height: eventsPanel.height - eventsPanel.contentTop - 6
            clip: true
            spacing: 0
            model: page.podEvents
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            delegate: Item {
                width: eventList.width - 12
                height: 58

                Rectangle { x: 0; y: 57; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 0; y: 2; width: 300; height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.reason
                    color: modelData.warning ? Theme.warn : Theme.fgBright
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }
                // "warn" as a word: the tint is never the only signal.
                Text {
                    x: 306; y: 2; width: 70; height: 24
                    verticalAlignment: Text.AlignVCenter
                    visible: modelData.warning
                    text: "warn"
                    color: Theme.warn
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 0; y: 28; width: parent.width; height: 24
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.message
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }
            }
        }

        // Explicit, not an empty frame. A pod with nothing recent is normal.
        Text {
            visible: page.podEvents.length === 0
            x: 10; y: eventsPanel.contentTop + 8; width: eventsPanel.width - 20; height: 26
            verticalAlignment: Text.AlignVCenter
            text: "no recent events for this pod"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }
}

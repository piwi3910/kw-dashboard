import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// One node: its six headline facts as stat cards, then every pod scheduled
// on it as a dense table row — same chrome as Cluster.qml's node table.
//
// The breadcrumb bar is 84px here (not 34px) because Main.qml draws the
// global "‹ Back" button at x 12..92 / y 12..72 with z:100; at 84px that
// button sits INSIDE the bar and the crumbs start at x=104, clear of it.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb    0 ..  84  (84, holds Main.qml's back button)
//   gap          84 ..  88  (4)
//   card row     88 .. 168  (80)   6 cards x 204, gaps 8 -> ends x 1272
//   gap         168 .. 172  (4)
//   pods panel  172 .. 684  (512)
// Detail views hide the page dots, but content still stops at 684.
// Pods panel height budget (512):
//   title bar     0 ..  28
//   1px rule     28 ..  29
//   col header   29 ..  54  (25)
//   1px rule     54 ..  55
//   list         55 .. 506  (451, clipped, 33px rows -> 13 fit, scrolls)
//   slack       506 .. 512  (6)
// Column x budget (panel-local, rows are panel width - 12 to clear the
// scrollbar): namespace 8 (240) | pod 256 (510) | phase 774 (170)
//   | ready 952 (110,r) | restarts 1070 (174,r) -> ends 1244
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property int rowH: 33
    readonly property string nodeName: bridge.viewParams.node || ""

    readonly property var node: {
        var ns = bridge.nodes || []
        for (var i = 0; i < ns.length; i++) if (ns[i].name === page.nodeName) return ns[i]
        return null
    }
    readonly property bool found: node !== null

    readonly property var nodePods: {
        var out = []
        var ps = bridge.pods || []
        for (var i = 0; i < ps.length; i++) if (ps[i].node === page.nodeName) out.push(ps[i])
        return out
    }

    readonly property string state: !found ? "unknown"
        : (!node.ready ? "notready" : (node.cordoned ? "cordon" : "ready"))
    readonly property color stateColor: state === "notready" ? Theme.crit
        : (state === "cordon" ? Theme.warn : (state === "ready" ? Theme.ok : Theme.dimmer))
    readonly property bool down: state === "notready" || !found

    function pct(v) { return (v === undefined || v === null) ? "—" : v.toFixed(1) + "%" }

    PageHeader {
        id: header
        height: 84
        crumbX: 104
        parentCrumb: "nodes"
        crumb: page.nodeName.length > 0 ? page.nodeName : "node"
        chips: [
            { "text": page.state, "color": page.stateColor },
            { "text": page.nodePods.length + " pods" }
        ]
    }

    // ==== card row 88..168 (h 80) ========================================
    StatCard {
        x: 8; y: 88; width: 204; height: 80
        label: "state"
        value: page.state
        valueColor: page.stateColor
        monoValue: false
    }
    StatCard {
        x: 220; y: 88; width: 204; height: 80
        label: "cpu"
        value: page.down ? "—" : page.pct(page.node.cpuPct)
        valueColor: page.down ? Theme.dimmer : Theme.stateColor(page.node.cpuPct)
    }
    StatCard {
        x: 432; y: 88; width: 204; height: 80
        label: "memory"
        value: page.down ? "—" : page.pct(page.node.memPct)
        valueColor: page.down ? Theme.dimmer : Theme.stateColor(page.node.memPct)
    }
    // tempC === -1 means "no sensor on this node" — an em-dash, never a 0,
    // which would read as a genuine (and alarming) reading.
    StatCard {
        x: 644; y: 88; width: 204; height: 80
        label: "temp"
        value: (!page.found || page.node.tempC === undefined || page.node.tempC < 0)
            ? "—" : Math.round(page.node.tempC) + "°"
        valueColor: (page.found && page.node.tempC >= 60) ? Theme.warn : Theme.fgBright
        note: (page.found && page.node.tempC < 0) ? "no sensor" : ""
        noteColor: Theme.dimmer
    }
    StatCard {
        x: 856; y: 88; width: 204; height: 80
        label: "pods"
        value: page.found ? String(page.node.pods) : "—"
    }
    StatCard {
        x: 1068; y: 88; width: 204; height: 80
        label: "uptime"
        value: (!page.found || page.node.uptimeDays === undefined || page.node.uptimeDays === null)
            ? "—" : Math.round(page.node.uptimeDays) + "d"
        valueColor: page.down ? Theme.crit : Theme.fgBright
    }

    // ==== pods on this node 172..684 (h 512) =============================
    Panel {
        id: podsPanel
        x: 8
        y: 172
        width: 1264
        height: 512
        title: "Pods on this node"
        note: page.nodePods.length + " rows" + (page.nodePods.length > 13 ? " · scroll" : "")

        Item {
            x: 0; y: 29; width: podsPanel.width; height: 25
            Text { x: 8;    y: 0; width: 240; height: 25; verticalAlignment: Text.AlignVCenter; text: "namespace"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 256;  y: 0; width: 510; height: 25; verticalAlignment: Text.AlignVCenter; text: "pod";       color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 774;  y: 0; width: 170; height: 25; verticalAlignment: Text.AlignVCenter; text: "phase";     color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 952;  y: 0; width: 110; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "ready";    color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 1070; y: 0; width: 174; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "restarts"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: podsPanel.width - 2; height: 1; color: Theme.bgAlt }

        ListView {
            id: podList
            x: 0
            y: 55
            width: podsPanel.width
            height: 451
            clip: true
            spacing: 0
            model: page.nodePods
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 8 }

            delegate: Item {
                id: podRow
                width: podList.width - 12
                height: page.rowH

                readonly property bool bad: !modelData.healthy

                Rectangle {
                    anchors.fill: parent
                    color: podRow.bad ? Qt.rgba(0.890, 0.416, 0.416, 0.07) : "transparent"
                }
                Rectangle { x: 0; y: page.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 8; y: 0; width: 240; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.namespace
                    color: Theme.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }
                Text {
                    x: 256; y: 0; width: 510; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: podRow.bad ? Theme.crit : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideMiddle
                }
                StatePill {
                    x: 774
                    y: (page.rowH - 24) / 2
                    text: (modelData.phase || "unknown").toLowerCase()
                    textColor: podRow.bad ? Theme.crit : Theme.ok
                }
                Text {
                    x: 952; y: 0; width: 110; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.ready + "/" + modelData.total
                    color: podRow.bad ? Theme.crit : Theme.fgMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 1070; y: 0; width: 174; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.restarts
                    color: modelData.restarts > 0 ? Theme.warn : Theme.dim
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }

                // read-only: navigates to the pod detail view only.
                TapHandler {
                    onTapped: bridge.pushView("podDetail", { "ns": modelData.namespace, "pod": modelData.name })
                }
            }
        }

        Text {
            x: 8; y: 60; width: 700; height: 26
            visible: page.nodePods.length === 0
            verticalAlignment: Text.AlignVCenter
            text: page.found ? "no pods scheduled on this node"
                             : "node " + page.nodeName + " is not in the current snapshot"
            color: page.found ? Theme.dimmer : Theme.crit
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

// Explore — every namespace as one dense table row, problems first, in the
// same panel/table chrome as Cluster.qml's node table.
//
// The real cluster has 23-27 namespaces and 17 rows fit, so this is a
// ListView with a scrollbar, NOT a capped Repeater: silent truncation is a
// defect, and unlike Cluster's 8-node table there is no natural cap here.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb    0 ..  34  (34)
//   gap          34 ..  42  (8)
//   panel        42 .. 684  (642)
//   page dots   688 .. 704        content stops at 684, 4px clear.
// Panel height budget (642):
//   title bar     0 ..  28
//   1px rule     28 ..  29
//   col header   29 ..  54  (25)
//   1px rule     54 ..  55
//   list         55 .. 637  (582, clipped, 33px rows -> 17 fit, scrolls)
//   slack       637 .. 642  (5)
// 33px rows are under the 60px touch floor — the same documented trade as
// Cluster's node table: on a wall panel seeing every namespace beats a
// bigger target, and every visible row is fully tappable.
// Column x budget (panel-local, rows are panel width - 12 to clear the
// scrollbar): name 8 (530) | state 546 (170) | pods 724 (130,r)
//   | memory 862 (190,r) | unhealthy 1060 (184,r) -> ends 1244
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property int rowH: 33

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: page.clockText = Qt.formatTime(new Date(), "hh:mm") }

    // Problems first, then alphabetical — the same order the old page used,
    // so an operator's muscle memory for "the broken one is at the top" holds.
    readonly property var namespaces: {
        var list = (bridge.namespaces || []).slice()
        list.sort(function (a, b) {
            if ((a.unhealthy > 0) !== (b.unhealthy > 0))
                return (b.unhealthy > 0) - (a.unhealthy > 0)
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
        })
        return list
    }

    readonly property int unhealthyNs: {
        var n = 0
        for (var i = 0; i < page.namespaces.length; i++) if (page.namespaces[i].unhealthy > 0) n++
        return n
    }

    function fmtMem(bytes) {
        var b = bytes || 0
        if (b >= 1e9) return (b / 1e9).toFixed(1) + " GB"
        if (b >= 1e6) return (b / 1e6).toFixed(1) + " MB"
        return Math.round(b / 1e3) + " KB"
    }

    PageHeader {
        id: header
        crumb: "namespaces"
        chips: [
            { "text": "🕘 " + page.clockText },
            { "text": page.namespaces.length + " namespaces" },
            { "text": page.unhealthyNs + " with problems",
              "color": page.unhealthyNs > 0 ? Theme.crit : Theme.fgMuted }
        ]
    }

    Panel {
        id: nsPanel
        x: 8
        y: 42
        width: 1264
        height: 642
        title: "Namespaces"
        note: page.namespaces.length + " rows · problems first"

        Item {
            x: 0; y: 29; width: nsPanel.width; height: 25
            Text { x: 8;    y: 0; width: 530; height: 25; verticalAlignment: Text.AlignVCenter; text: "namespace"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 546;  y: 0; width: 170; height: 25; verticalAlignment: Text.AlignVCenter; text: "state";     color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 724;  y: 0; width: 130; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "pods";      color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 862;  y: 0; width: 190; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "memory";    color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 1060; y: 0; width: 184; height: 25; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: "unhealthy"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: nsPanel.width - 2; height: 1; color: Theme.bgAlt }

        ListView {
            id: nsList
            x: 0
            y: 55
            width: nsPanel.width
            height: 582
            clip: true
            spacing: 0
            model: page.namespaces
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn; width: 8 }

            delegate: Item {
                id: nsRow
                width: nsList.width - 12
                height: page.rowH

                readonly property bool bad: modelData.unhealthy > 0

                Rectangle {
                    anchors.fill: parent
                    color: nsRow.bad ? Qt.rgba(0.890, 0.416, 0.416, 0.07) : "transparent"
                }
                Rectangle { x: 0; y: page.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                Text {
                    x: 8; y: 0; width: 530; height: page.rowH
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: nsRow.bad ? Theme.crit : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                    elide: Text.ElideRight
                }

                StatePill {
                    x: 546
                    y: (page.rowH - 24) / 2
                    text: nsRow.bad ? "unhealthy" : "ok"
                    textColor: nsRow.bad ? Theme.crit : Theme.ok
                }

                Text {
                    x: 724; y: 0; width: 130; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.pods
                    color: Theme.fgMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 862; y: 0; width: 190; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: page.fmtMem(modelData.memBytes)
                    color: Theme.fgMuted
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }
                Text {
                    x: 1060; y: 0; width: 184; height: page.rowH
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: nsRow.bad ? String(modelData.unhealthy) : "—"
                    color: nsRow.bad ? Theme.crit : Theme.dimmer
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.tableText
                }

                // read-only: navigates into the namespace's pod list only.
                TapHandler {
                    onTapped: bridge.pushView("namespaceDetail", { "ns": modelData.name })
                }
            }
        }

        Text {
            x: 8; y: 60; width: 400; height: 26
            visible: page.namespaces.length === 0
            verticalAlignment: Text.AlignVCenter
            text: "no namespaces reported yet"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }
}

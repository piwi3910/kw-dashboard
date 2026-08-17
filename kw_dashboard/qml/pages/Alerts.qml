import QtQuick 2.15
import "../"

// Alerts — Alertmanager is the source of truth; this page shows what is
// firing and can dismiss the ON-SCREEN takeover only. It can never silence
// anything upstream, and carries no other control.
//
// Severity is always spelled out (CRITICAL / WARNING / INFO) and coloured;
// the word is the accessibility guarantee, the hue only reinforces it.
//
// PAGE HEIGHT BUDGET (1280x720), y ranges absolute:
//   breadcrumb    0 ..  34  (34)
//   gap          34 ..  42  (8)
//   panel        42 .. 604  (562)
//   gap         604 .. 616  (12)
//   dismiss     616 .. 676  (60, >= touch floor)
//   page dots   688 .. 704        content stops at 676, 12px clear.
// Panel height budget (562):
//   title bar     0 ..  28
//   1px rule     28 ..  29
//   col header   29 ..  54  (25)
//   1px rule     54 ..  55
//   rows         55 .. 555  (5 x 100)
//   slack       555 .. 562  (7)
// Rows are a Column+Repeater with a hard 5-slot budget (Cluster's pattern):
// past that the last slot becomes "+N more", so overflow is stated, never
// silent, and the row count can never collapse to zero the way a
// fillHeight ListView did.
// Column x budget (panel-local): severity 8 (170) | alert 186 (1070 for
// name, 1070 for summary underneath) -> ends 1256
Rectangle {
    id: page
    anchors.fill: parent
    color: Theme.bg

    readonly property var alerts: bridge.alerts || []
    readonly property bool empty: alerts.length === 0
    readonly property int rowH: 100
    readonly property int maxRows: 5
    readonly property int shownRows: alerts.length > maxRows ? maxRows - 1 : maxRows

    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: page.clockText = Qt.formatTime(new Date(), "hh:mm") }

    function sevColor(sev) {
        var s = (sev || "").toLowerCase()
        if (s === "critical") return Theme.crit
        if (s === "warning") return Theme.warn
        return Theme.dim
    }

    function sevText(sev) {
        var s = (sev || "").toUpperCase()
        return s.length > 0 ? s : "INFO"
    }

    PageHeader {
        id: header
        crumb: "alerts"
        chips: [
            { "text": "🕘 " + page.clockText },
            { "text": page.alerts.length + " firing",
              "color": page.empty ? Theme.ok : Theme.crit }
        ]
    }

    // ==== firing 42..604 =================================================
    Panel {
        id: firingPanel
        visible: !page.empty
        x: 8
        y: 42
        width: 1264
        height: 562
        title: "Firing alerts"
        note: page.alerts.length + " firing"
        noteColor: Theme.crit

        Item {
            x: 0; y: 29; width: firingPanel.width; height: 25
            Text { x: 8;   y: 0; width: 170;  height: 25; verticalAlignment: Text.AlignVCenter; text: "severity"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
            Text { x: 186; y: 0; width: 1070; height: 25; verticalAlignment: Text.AlignVCenter; text: "alert · summary"; color: Theme.dimmer; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        }
        Rectangle { x: 1; y: 54; width: firingPanel.width - 2; height: 1; color: Theme.bgAlt }

        Column {
            x: 0; y: 55; width: firingPanel.width; spacing: 0

            Repeater {
                model: page.alerts

                delegate: Item {
                    id: arow
                    width: firingPanel.width
                    height: page.rowH
                    visible: index < page.shownRows

                    readonly property color sev: page.sevColor(modelData.severity)

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(arow.sev.r, arow.sev.g, arow.sev.b, 0.06)
                    }
                    Rectangle { x: 0; y: page.rowH - 1; width: parent.width; height: 1; color: Theme.bgAlt }

                    Text {
                        x: 8; y: 0; width: 170; height: page.rowH
                        verticalAlignment: Text.AlignVCenter
                        text: page.sevText(modelData.severity)
                        color: arow.sev
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.tableText
                        font.bold: true
                    }
                    Text {
                        x: 186; y: 10; width: 1070; height: 34
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.name
                        color: Theme.fgBright
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.glance
                        elide: Text.ElideRight
                    }
                    Text {
                        x: 186; y: 50; width: 1070; height: 40
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.summary
                        color: Theme.dim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.tableText
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Text {
            visible: page.alerts.length > page.maxRows
            x: 8
            y: 55 + (page.maxRows - 1) * page.rowH
            width: 600; height: page.rowH
            verticalAlignment: Text.AlignVCenter
            text: "+ " + (page.alerts.length - page.shownRows) + " more firing in Alertmanager"
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }

    // ==== all quiet 42..604 ==============================================
    //
    // A deliberate, framed statement rather than an empty void (design 1e):
    // the same panel chrome as the firing state, so the page does not change
    // shape when the last alert clears.
    //   all quiet   200 .. 290  (Theme.big 64)
    //   subtitle    296 .. 336
    //   footnote    344 .. 374
    Panel {
        id: quietPanel
        visible: page.empty
        x: 8
        y: 42
        width: 1264
        height: 562
        title: "Alert status"
        note: "0 firing"
        noteColor: Theme.ok

        Text {
            x: 0; y: 200; width: quietPanel.width; height: 90
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "all quiet"
            color: Theme.ok
            font.family: Theme.fontFamily
            font.pixelSize: Theme.big
        }
        Text {
            x: 0; y: 296; width: quietPanel.width; height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "no alerts firing"
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.body
        }
        Text {
            x: 0; y: 344; width: quietPanel.width; height: 30
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "Alertmanager reports nothing firing · checked " + page.clockText
            color: Theme.dimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
    }

    // ==== dismiss 616..676 ===============================================
    //
    // Dismisses the on-screen takeover ONLY — this app cannot silence
    // Alertmanager, so the label never says "acknowledge" or "silence".
    Rectangle {
        id: dismiss
        visible: !page.empty
        x: 1076
        y: 616
        width: 180
        height: 60
        radius: 3
        color: Theme.panelAlt
        border.color: Theme.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "DISMISS"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.glance
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: bridge.clearPreempt()
        }
    }

    Text {
        visible: !page.empty
        x: 8; y: 616; width: 1000; height: 60
        verticalAlignment: Text.AlignVCenter
        text: "DISMISS clears the on-screen takeover only — alerts stay firing in Alertmanager."
        color: Theme.dimmer
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
    }
}

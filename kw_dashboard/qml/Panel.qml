import QtQuick 2.15

// Bordered, rounded panel with a fixed 28px title strip, a 1px rule, then
// free space from y=29 down. This is Cluster.qml's inline `PanelFrame`
// lifted into a file so the other six pages share the exact same chrome.
//
// DELIBERATELY NO `default property alias`: an alias that does not reparent
// leaves caller content on the panel root drawing OVER the title bar (the
// bug that shipped once). Children written inside a Panel { } instance land
// on this Rectangle in panel-local coordinates, which is exactly what the
// explicit-pixel layouts want and is the one behaviour that cannot silently
// fail. Callers place their content at y >= contentTop and wrap any list in
// an Item with `clip: true`.
//
// No layer.enabled / QtGraphicalEffects anywhere: there is no GL backend on
// the device and they blank the whole subtree.
Rectangle {
    id: frame

    property string title: ""
    property string note: ""
    property color noteColor: Theme.dimmer

    readonly property int titleH: 28
    readonly property int contentTop: 33

    color: Theme.panel
    border.color: Theme.border
    border.width: 1
    radius: 3
    clip: true

    Text {
        x: 10
        y: 0
        width: frame.width - 20 - (frame.note.length > 0 ? noteText.width + 10 : 0)
        height: frame.titleH
        verticalAlignment: Text.AlignVCenter
        text: frame.title
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.panelTitle
        font.bold: true
        elide: Text.ElideRight
    }

    Text {
        id: noteText
        visible: frame.note.length > 0
        y: 0
        height: frame.titleH
        anchors.right: frame.right
        anchors.rightMargin: 10
        verticalAlignment: Text.AlignVCenter
        text: frame.note
        color: frame.noteColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
    }

    Rectangle {
        x: 1
        y: frame.titleH
        width: frame.width - 2
        height: 1
        color: Theme.bgAlt
    }
}

import QtQuick 2.15

// Cluster.qml's table state pill: the WORD is the accessibility guarantee,
// the tint only reinforces it. ok/crit sit close in luminance by design, so
// no state anywhere in this app may be carried by hue alone.
Rectangle {
    id: pill

    property string text: ""
    property color textColor: Theme.ok

    implicitWidth: label.implicitWidth + 14
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight
    radius: 3
    color: Qt.rgba(pill.textColor.r, pill.textColor.g, pill.textColor.b, 0.16)

    Text {
        id: label
        anchors.centerIn: parent
        text: pill.text
        color: pill.textColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
    }
}

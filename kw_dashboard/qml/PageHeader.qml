import QtQuick 2.15

// Shared header band for the non-Cluster top-level pages (Pulse, Explore,
// Alerts): title left, one line of contextual text right — same band
// geometry as Cluster.qml's hand-rolled header so all four pages read as
// one product instead of three bare floating labels.
Rectangle {
    id: header
    property string title: ""
    property alias rightText: rightLabel.text
    property color rightColor: Theme.dim

    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: 64
    color: Theme.panel

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.border }

    Text {
        text: header.title
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        font.bold: true
        font.letterSpacing: 1.5
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: rightLabel
        color: header.rightColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.body
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
    }
}

import QtQuick 2.15

// One stat card from the 5a stat row: label band, glanceable value band,
// optional caption band. Same three-band budget Cluster.qml uses, so cards
// on other pages line up with the cluster page's row:
//   label 4..26 | value 26..60 | caption 60..80
// Numerals are IBM Plex Mono (monoValue, the default); words such as a node
// state use IBM Plex Sans at the 26px glance size instead.
Rectangle {
    id: card

    property string label: ""
    property string value: "—"
    property color valueColor: Theme.fgBright
    property bool monoValue: true
    property string note: ""
    property color noteColor: Theme.dim

    width: 310
    height: 80
    color: Theme.panel
    border.color: Theme.border
    border.width: 1
    radius: 3
    clip: true

    Text {
        x: 10; y: 4; width: card.width - 20; height: 22
        verticalAlignment: Text.AlignVCenter
        text: card.label
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
        elide: Text.ElideRight
    }

    Text {
        x: 10; y: 26; width: card.width - 20; height: 34
        verticalAlignment: Text.AlignVCenter
        text: card.value
        color: card.valueColor
        font.family: card.monoValue ? Theme.monoFamily : Theme.fontFamily
        font.pixelSize: card.monoValue ? Theme.statNumber : Theme.glance
        font.bold: !card.monoValue
        elide: Text.ElideRight
    }

    Text {
        visible: card.note.length > 0
        x: 10; y: 60; width: card.width - 20; height: 20
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        text: card.note
        color: card.noteColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tableText
        elide: Text.ElideLeft
    }
}

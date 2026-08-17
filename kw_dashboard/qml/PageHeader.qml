import QtQuick 2.15

// Breadcrumb bar, identical in height, palette and type to Cluster.qml's
// hand-rolled one: `kw / kubernetes / <crumb>` at left, contextual chips at
// right. Cluster keeps its own copy inline (that file is frozen); this is
// the shared version every other page uses so all seven read as one product.
//
// Detail views (depth > 0) set `height: 84` and `crumbX: 104`: Main.qml
// draws a 80x60 "‹ Back" button at x 12..92 / y 12..72 with z:100, so a
// 34px bar would be half-covered by it. At 84px the button sits INSIDE the
// bar and the crumbs start clear of it.
//
// `chips` is an array of { text, color? } — display-only, exactly as in 5a.
Rectangle {
    id: header

    property string crumb: ""
    property string parentCrumb: ""
    property var chips: []
    property int crumbX: 14

    x: 0
    y: 0
    width: parent ? parent.width : 1280
    height: 34
    color: Theme.bgAlt
    clip: true

    Rectangle {
        x: 0
        y: header.height - 1
        width: header.width
        height: 1
        color: Theme.border
    }

    Row {
        x: header.crumbX
        height: header.height
        spacing: 8

        Text { anchors.verticalCenter: parent.verticalCenter; text: "kw"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "kubernetes"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        Text {
            visible: header.parentCrumb.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "/"
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
        }
        Text {
            visible: header.parentCrumb.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: header.parentCrumb
            color: Theme.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
            width: Math.min(implicitWidth, 320)
            elide: Text.ElideRight
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "/"; color: Theme.dim; font.family: Theme.fontFamily; font.pixelSize: Theme.tableText }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: header.crumb
            color: Theme.fgBright
            font.bold: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tableText
            width: Math.min(implicitWidth, 520)
            elide: Text.ElideRight
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        height: header.height
        spacing: 6

        Repeater {
            model: header.chips

            delegate: Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: chipText.implicitWidth + 20
                height: 26
                color: Theme.panelAlt
                border.color: Theme.border
                border.width: 1
                radius: 3

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData.text
                    color: modelData.color !== undefined ? modelData.color : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.tableText
                }
            }
        }
    }
}

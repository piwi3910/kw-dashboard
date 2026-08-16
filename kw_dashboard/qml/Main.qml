import QtQuick 2.15
import QtQuick.Window 2.15

// Window shell: routes to page files by naming convention so later tasks
// only need to drop a QML file in qml/pages/ — nothing here changes.
Window {
    id: root
    visible: true
    width: 1280
    height: 720
    color: Theme.bg

    readonly property var pages: ["cluster", "pulse", "explore", "alerts"]

    function pageFile(kind) {
        var name = kind.length ? kind.charAt(0).toUpperCase() + kind.slice(1) : "Cluster"
        return "pages/" + name + ".qml"
    }

    // Global touch observer: registers every press as activity (so rotation
    // pauses) without stealing the event from controls underneath — a
    // TapHandler only takes a passive grab, it never consumes the point.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onPressedChanged: if (pressed) bridge.touch()
    }

    Loader {
        id: pageLoader
        anchors.fill: parent
        source: Qt.resolvedUrl(root.pageFile(bridge.viewKind))
        asynchronous: false

        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Fallback while a page file doesn't exist yet (this task ships only
    // the shell) or fails to load — names the page so routing is visibly
    // correct even before later tasks fill it in.
    Text {
        anchors.centerIn: parent
        visible: pageLoader.status !== Loader.Ready
        text: bridge.viewKind
        font.family: Theme.fontFamily
        font.pixelSize: Theme.big
        color: Theme.fg
    }

    // Page-position dots for the four top-level pages.
    Row {
        id: dots
        visible: bridge.depth === 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        spacing: 18

        Repeater {
            model: root.pages
            delegate: Rectangle {
                width: 16
                height: 16
                radius: 8
                color: index === bridge.pageIndex ? Theme.accent : Theme.border

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -22   // pad the tap target up toward touchMin
                    onClicked: bridge.jumpToPage(index)
                }
            }
        }
    }

    // Back affordance whenever a detail view has been pushed.
    Rectangle {
        id: backButton
        visible: bridge.depth > 0
        width: Theme.touchMin + 20
        height: Theme.touchMin
        radius: 8
        color: Theme.panelAlt
        border.color: Theme.border
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12

        Text {
            anchors.centerIn: parent
            text: "‹ Back"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.small
            color: Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            onClicked: bridge.popView()
        }
    }
}

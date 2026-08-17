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

    // Wraps the Loader so a horizontal swipe can translate the whole page
    // during the drag and slide it back into place on release — plain
    // x/width/height (not anchors.fill) because anchors would fight the
    // DragHandler's attempts to move pageArea.x every frame.
    Item {
        id: pageArea
        x: 0
        width: 1280
        height: 720

        Behavior on x {
            enabled: !swipeHandler.active
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Loader {
            id: pageLoader
            width: pageArea.width
            height: pageArea.height
            source: Qt.resolvedUrl(root.pageFile(bridge.viewKind))
            asynchronous: false

            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // Horizontal-only swipe between the four top-level pages. xAxis
        // enabled / yAxis disabled means a drag that's mostly vertical
        // (e.g. dragging inside a ListView) never gets claimed here, so
        // list scrolling on Explore/Alerts/Pulse/detail views is untouched.
        // Only active at depth 0 — inside a detail view a horizontal drag
        // does nothing (chosen over "swipe = back" to keep the gesture
        // meaning fixed: horizontal always means "change top-level page").
        DragHandler {
            id: swipeHandler
            target: pageArea
            enabled: bridge.depth === 0
            xAxis.enabled: true
            yAxis.enabled: false

            onActiveChanged: {
                if (active) return
                if (pageArea.x <= -60)
                    bridge.jumpToPage((bridge.pageIndex + 1) % root.pages.length)
                else if (pageArea.x >= 60)
                    bridge.jumpToPage((bridge.pageIndex - 1 + root.pages.length) % root.pages.length)
                pageArea.x = 0
            }
        }
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

    // Page-position dots for the four top-level pages. z above everything
    // else in the scene (page roots included) so an opaque full-bleed page
    // background can never paint over them.
    Row {
        id: dots
        z: 100
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

    // Back affordance whenever a detail view has been pushed. Same z as the
    // dots so it always sits above page content too.
    Rectangle {
        id: backButton
        z: 100
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

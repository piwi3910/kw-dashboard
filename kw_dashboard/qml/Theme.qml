pragma Singleton
import QtQuick 2.15

// Palette and type scale for the panel. Accessibility-corrected colours —
// do not "harmonise" ok/crit, their luminance gap is deliberate so
// red/green colour-blind viewers can still tell healthy from critical.
QtObject {
    readonly property color bg: "#0d0d0d"
    readonly property color panel: "#131312"
    readonly property color panelAlt: "#1c1c1b"
    readonly property color border: "#262624"
    readonly property color fg: "#c3c2b7"
    readonly property color fgBright: "#ffffff"
    readonly property color dim: "#6e7a8a"
    readonly property color accent: "#3987e5"
    readonly property color ok: "#288c28"
    readonly property color warn: "#fab219"
    readonly property color crit: "#ff8c8c"

    readonly property int huge: 120
    readonly property int big: 64
    readonly property int body: 30
    readonly property int small: 26
    readonly property int mono: 20

    readonly property string fontFamily: "Inter"
    readonly property string monoFamily: "DejaVu Sans Mono"

    readonly property int touchMin: 60

    function stateColor(pct) {
        if (pct >= 88)
            return crit
        if (pct >= 70)
            return warn
        return ok
    }
}

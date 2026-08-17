pragma Singleton
import QtQuick 2.15

// Palette and type scale for the panel. Updated to the approved 5a
// "Grafana-style" palette (see .superpowers/sdd/2026-08-16-kw-dashboard/design5/5a.html).
//
// Accessibility note: ok (#56C08D) and crit (#E36A6A) are only ~1.39:1 apart
// in luminance — a real regression versus the old forced-apart pair IF hue
// were the only signal. It is not: every state in this design is paired
// with a text pill, a legend name, or a numeric label, so colour is never
// the sole carrier of meaning. Keep it that way — any new state indicator
// added later must carry a word/icon too, not just a colour.
QtObject {
    // ---- 5a palette (existing names kept, values updated) ----------------
    readonly property color bg: "#171A1F"
    readonly property color panel: "#1F2329"
    readonly property color panelAlt: "#23272D"
    readonly property color border: "#2C3138"
    readonly property color fg: "#C7CDD6"
    readonly property color fgBright: "#D8DDE5"
    readonly property color dim: "#8E97A3"
    readonly property color accent: "#5B9BF8"
    readonly property color ok: "#56C08D"
    readonly property color warn: "#E8B341"
    readonly property color crit: "#E36A6A"

    // ---- new names added for 5a (do not rename the above) ----------------
    readonly property color bgAlt: "#191D21"
    readonly property color fgMuted: "#C7CDD6"
    readonly property color dimmer: "#6C7480"

    // Chart series palette, in the order 5a cycles them.
    readonly property var seriesColors: ["#56C08D", "#5B9BF8", "#9B8CF0", "#46C4D6", "#E8B341", "#E36A6A"]

    // ---- type scale (existing values kept — other pages depend on them) --
    readonly property int huge: 120
    readonly property int big: 64
    readonly property int body: 30
    readonly property int small: 26
    readonly property int mono: 20

    // ---- new type scale added for the 5a panel-grid page ------------------
    // 5a ships ~11-13px labels/table text; that's below this project's 26px
    // glanceable floor for a 1m viewing distance. tableText sits at the
    // 20px dense-table floor (numerals are IBM Plex Mono so columns still
    // line up); glance/panelTitle sit at or above the 26px floor for
    // anything meant to be read at a glance.
    readonly property int tableText: 20
    readonly property int panelTitle: 22
    readonly property int glance: 26
    readonly property int statNumber: 36
    readonly property int gaugeNumber: 44

    readonly property string fontFamily: "IBM Plex Sans"
    readonly property string monoFamily: "IBM Plex Mono"

    readonly property int touchMin: 60

    function stateColor(pct) {
        if (pct >= 88)
            return crit
        if (pct >= 70)
            return warn
        return ok
    }
}

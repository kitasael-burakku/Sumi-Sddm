pragma Singleton

import QtQuick

QtObject {
    readonly property SystemPalette system: SystemPalette {}
    readonly property bool dark: system.window.hslLightness < 0.5
    readonly property color window: dark ? "#111722" : "#f5f7fb"
    readonly property color chrome: dark ? "#151d2a" : "#edf1f8"
    readonly property color surface: dark ? "#1a2332" : "#ffffff"
    readonly property color control: dark ? "#222e41" : "#edf2fa"
    readonly property color hover: dark ? "#2b3950" : "#e0e8f6"
    readonly property color selected: dark ? "#263c59" : "#dce8fa"
    readonly property color border: dark ? "#344359" : "#d1dae9"
    readonly property color ink: dark ? "#edf3ff" : "#19263a"
    readonly property color muted: dark ? "#afbdd2" : "#495a73"
    readonly property color disabled: dark ? "#8a9ab2" : "#5c6b82"
    readonly property color accent: dark ? "#a5c8ff" : "#23569a"
    readonly property color accentHover: dark ? "#bfd7ff" : "#204d8a"
    readonly property color accentPressed: dark ? "#88b3f5" : "#1a4177"
    readonly property color onAccent: dark ? "#122744" : "#ffffff"
    readonly property color frame: "#0e1420"
    readonly property color frameText: "#e1eafd"
    readonly property color unfilled: "transparent"
    readonly property color error: dark ? "#ff9d96" : "#a72d29"
    readonly property color pending: dark ? "#f5b773" : "#8a4b00"

    readonly property int small: 4
    readonly property int gap: 8
    readonly property int inset: 12
    readonly property int padding: 16
    readonly property int gutter: 24
    readonly property int sectionGap: 26
    readonly property int controlRadius: 7
    readonly property int cardRadius: 12
    readonly property int controlHeight: 34
    readonly property int navHeight: 38
    readonly property int stroke: 1
    readonly property int focusStroke: 2
    readonly property font uiFont: Application.font
    readonly property real captionScale: 0.9
    readonly property real headingScale: 1.15
    readonly property real titleScale: 1.8
    readonly property string mono: "monospace"

    property bool reduceMotion: false
    readonly property bool systemReducesMotion: {
        const preference = Application.styleHints?.accessibility?.motionPreference;
        return preference !== undefined && preference === Qt.ReducedMotion;
    }
    readonly property int duration: reduceMotion || systemReducesMotion ? 0 : 170
    readonly property int easing: Easing.OutCubic
}

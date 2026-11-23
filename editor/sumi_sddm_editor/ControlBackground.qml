import QtQuick

Rectangle {
    property bool selected: false
    property bool primary: false
    property bool quiet: false
    property bool pressed: false
    property bool hovered: false
    property bool focused: false

    implicitHeight: Tones.controlHeight
    radius: Tones.controlRadius
    color: primary && enabled
        ? (pressed ? Tones.accentPressed : hovered ? Tones.accentHover : Tones.accent)
        : enabled && pressed ? Tones.selected
        : enabled && hovered ? Tones.hover
        : selected ? Tones.selected
        : quiet ? Tones.unfilled : enabled ? Tones.control : Tones.surface
    border.width: focused ? Tones.focusStroke : Tones.stroke
    border.color: focused ? (primary ? Tones.ink : Tones.accent)
        : quiet || primary || selected ? Tones.unfilled : Tones.border

    Behavior on color { ColorAnimation { duration: Tones.duration; easing.type: Tones.easing } }
}

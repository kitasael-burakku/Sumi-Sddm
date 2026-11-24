import QtQuick

/**
 * The square surface behind every button, selector and segment.
 *
 *   secondary (default)   control fill, visible control border
 *   primary               frost fill, dark text (one dominant action per context)
 *   quiet (ghost)         transparent until hovered
 *   destructive           error text; error tint and border when hovered or armed
 *   selected              selected fill (navigation, options)
 */
Rectangle {
    id: root

    property bool selected: false
    property bool primary: false
    property bool quiet: false
    property bool destructive: false
    /** A destructive action waiting for its confirming second press. */
    property bool armed: false
    property bool pressed: false
    property bool hovered: false
    property bool focused: false

    implicitHeight: Tones.controlHeight
    radius: Tones.cornerRadius
    color: !enabled ? (quiet ? Tones.transparent : Tones.disabledSurface)
        : primary ? (pressed ? Tones.accentPressed : hovered ? Tones.accentHover : Tones.accent)
        : destructive ? (armed || pressed || hovered ? Tones.errorSurface : Tones.transparent)
        : pressed ? Tones.pressedSurface
        : hovered ? Tones.hoverSurface
        : selected ? Tones.selectedSurface
        : quiet ? Tones.transparent : Tones.controlSurface
    border.width: Tones.stroke
    border.color: !enabled ? (quiet ? Tones.transparent : Tones.borderSubtle)
        : primary ? Tones.accent
        : destructive ? (armed || hovered || pressed ? Tones.error : Tones.transparent)
        : quiet || selected ? Tones.transparent
        : hovered ? Tones.borderHover : Tones.controlBorder

    Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }

    FocusRing { shown: root.focused }
}

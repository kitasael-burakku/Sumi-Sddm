import QtQuick

// Keyboard focus: a 2 px frost outline just outside the control, with a 1 px dark gap. It never changes the
// control's size and is independent of hover and selection.
// `inset` keeps it inside for full-width rows, whose outside a scroll view would clip.
Rectangle {
    property bool shown: false
    /** Draw inside the control instead (for full-width rows whose outside would be clipped). */
    property bool inset: false

    anchors.fill: parent
    anchors.margins: inset ? 0 : -(Tones.focusStroke + Tones.focusGap)
    visible: shown
    color: Tones.transparent
    radius: Tones.cornerRadius
    border.width: Tones.focusStroke
    border.color: Tones.focusRing
    z: 10

    Rectangle {
        anchors.fill: parent
        anchors.margins: Tones.focusStroke
        color: Tones.transparent
        border.width: Tones.focusGap
        border.color: Tones.separation
    }
}

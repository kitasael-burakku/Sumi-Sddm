import QtQuick
import QtQuick.Controls

// Text input recipe: square, control fill, visible control border; `invalid` gives the error border.
TextField {
    id: root

    property bool invalid: false
    property bool monospace: false

    hoverEnabled: true
    selectByMouse: true
    leftPadding: Tones.space3
    rightPadding: Tones.space3
    topPadding: Tones.space1
    bottomPadding: Tones.space1
    verticalAlignment: TextInput.AlignVCenter
    font.family: monospace ? Tones.mono : Tones.sans
    font.pixelSize: monospace ? Tones.monoSize : Tones.bodySize
    color: enabled ? Tones.textPrimary : Tones.textDisabled
    placeholderTextColor: Tones.textMuted
    selectionColor: Tones.selectedSurface
    selectedTextColor: Tones.textPrimary

    background: Rectangle {
        implicitHeight: Tones.controlHeight
        implicitWidth: 120
        radius: Tones.cornerRadius
        color: !root.enabled ? Tones.disabledSurface
            : root.readOnly ? Tones.groupSurface
            : root.hovered && !root.activeFocus ? Tones.hoverSurface : Tones.controlSurface
        border.width: root.invalid || root.activeFocus ? Tones.focusStroke : Tones.stroke
        border.color: !root.enabled ? Tones.borderSubtle
            : root.invalid ? Tones.error
            : root.activeFocus ? Tones.focusRing
            : root.hovered ? Tones.borderHover : Tones.controlBorder
        Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }
    }
}

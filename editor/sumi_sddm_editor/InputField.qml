import QtQuick
import QtQuick.Controls

TextField {
    id: root

    hoverEnabled: true
    selectByMouse: true
    leftPadding: Tones.inset
    rightPadding: Tones.inset
    topPadding: Tones.small
    bottomPadding: Tones.small
    color: enabled ? Tones.ink : Tones.disabled

    background: Rectangle {
        implicitHeight: Tones.controlHeight
        radius: Tones.controlRadius
        color: root.hovered && root.enabled ? Tones.hover : Tones.control
        border.width: root.activeFocus ? Tones.focusStroke : Tones.stroke
        border.color: root.activeFocus ? Tones.accent : Tones.border
        Behavior on color { ColorAnimation { duration: Tones.duration; easing.type: Tones.easing } }
    }
}

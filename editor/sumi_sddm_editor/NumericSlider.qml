import QtQuick
import QtQuick.Controls

Slider {
    id: root

    hoverEnabled: true
    implicitHeight: Tones.controlHeight
    padding: Tones.small
    background: Rectangle {
        x: root.leftPadding
        y: (root.height - height) / 2
        width: root.availableWidth
        height: Tones.small
        radius: height / 2
        color: Tones.border
        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: root.enabled ? Tones.accent : Tones.disabled
        }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: (root.height - height) / 2
        width: 16
        height: width
        radius: width / 2
        color: !root.enabled ? Tones.disabled : root.hovered || root.pressed ? Tones.ink : Tones.accent
        border.width: root.visualFocus ? Tones.focusStroke : Tones.stroke
        border.color: root.visualFocus ? Tones.ink : Tones.window
        Behavior on color { ColorAnimation { duration: Tones.duration; easing.type: Tones.easing } }
    }
}

import QtQuick
import QtQuick.Controls

// Slider recipe: 4 px track (control border → frost), 14 px square frost thumb, 32 px tall hit area.
Slider {
    id: root

    hoverEnabled: true
    implicitHeight: Math.max(Tones.sliderHitHeight, Tones.controlHeight)
    padding: Tones.space1
    leftPadding: Tones.sliderThumb / 2
    rightPadding: Tones.sliderThumb / 2
    background: Rectangle {
        x: root.leftPadding
        y: (root.height - height) / 2
        width: root.availableWidth
        height: Tones.sliderTrack
        radius: Tones.cornerRadius
        color: root.enabled ? Tones.controlBorder : Tones.borderSubtle
        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: Tones.cornerRadius
            color: root.enabled ? Tones.accent : Tones.textDisabled
        }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * root.availableWidth - width / 2
        y: (root.height - height) / 2
        width: Tones.sliderThumb
        height: width
        radius: Tones.cornerRadius
        color: !root.enabled ? Tones.textDisabled
            : root.pressed ? Tones.accentPressed : root.hovered ? Tones.accentHover : Tones.accent
        border.width: Tones.stroke
        border.color: Tones.separation
        Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }
        FocusRing { shown: root.visualFocus }
    }
}

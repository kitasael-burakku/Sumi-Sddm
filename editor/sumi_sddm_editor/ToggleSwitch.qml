import QtQuick
import QtQuick.Controls

// Switch recipe: a rectangular track and a square thumb; off = thumb left on a control fill, on = thumb right on frost.
Switch {
    id: root

    hoverEnabled: true
    implicitHeight: Tones.controlHeight
    padding: Tones.space1
    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: Tones.cornerRadius
        color: !root.enabled ? Tones.disabledSurface
            : root.checked ? (root.hovered ? Tones.accentHover : Tones.accent)
            : root.hovered ? Tones.hoverSurface : Tones.controlSurface
        border.width: Tones.stroke
        border.color: !root.enabled ? Tones.borderSubtle
            : root.checked ? Tones.accent : root.hovered ? Tones.borderHover : Tones.controlBorder
        Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }

        Rectangle {
            width: 14
            height: width
            x: root.checked ? parent.width - width - Tones.space1 : Tones.space1
            anchors.verticalCenter: parent.verticalCenter
            radius: Tones.cornerRadius
            color: !root.enabled ? Tones.textDisabled : root.checked ? Tones.textOnAccent : Tones.textSecondary
            Behavior on x { NumberAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }
        }
        FocusRing { shown: root.visualFocus }
    }
}

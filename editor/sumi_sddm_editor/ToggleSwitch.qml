import QtQuick
import QtQuick.Controls

Switch {
    id: root

    hoverEnabled: true
    implicitHeight: Tones.controlHeight
    padding: Tones.small
    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: height / 2
        color: root.checked ? Tones.accent : root.hovered ? Tones.hover : Tones.control
        border.width: root.visualFocus ? Tones.focusStroke : Tones.stroke
        border.color: root.visualFocus ? Tones.ink : root.checked ? Tones.accent : Tones.muted
        Behavior on color { ColorAnimation { duration: Tones.duration; easing.type: Tones.easing } }

        Rectangle {
            width: 14
            height: width
            x: root.checked ? parent.width - width - Tones.small : Tones.small
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            color: root.checked ? Tones.onAccent : Tones.muted
            Behavior on x { NumberAnimation { duration: Tones.duration; easing.type: Tones.easing } }
        }
    }
}

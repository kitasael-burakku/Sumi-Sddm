import QtQuick
import QtQuick.Controls

// A thin square scroll bar: muted thumb, brighter when hovered or dragged.
ScrollBar {
    id: root

    hoverEnabled: true
    padding: Tones.stroke
    minimumSize: 0.08
    contentItem: Rectangle {
        implicitWidth: root.hovered || root.pressed ? 8 : 6
        implicitHeight: implicitWidth
        radius: Tones.cornerRadius
        color: root.pressed ? Tones.textSecondary : root.hovered ? Tones.borderHover : Tones.controlBorder
        opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tones.overlayDuration } }
    }
    background: null
}

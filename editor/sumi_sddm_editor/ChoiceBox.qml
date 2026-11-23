import QtQuick
import QtQuick.Controls

ComboBox {
    id: root

    hoverEnabled: true
    padding: Tones.gap
    leftPadding: Tones.inset
    rightPadding: Tones.inset + Tones.gap + (indicator ? indicator.width : 0)
    spacing: Tones.gap

    contentItem: Label {
        text: root.displayText
        font: root.font
        color: root.enabled ? Tones.ink : Tones.disabled
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: SettingsIcon {
        name: "chevron"
        x: root.width - root.padding - width
        y: (root.height - height) / 2
        color: Tones.muted
    }
    background: ControlBackground {
        hovered: root.hovered
        focused: root.visualFocus
        pressed: root.down
        implicitWidth: 128
    }
}

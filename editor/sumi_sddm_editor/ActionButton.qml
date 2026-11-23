import QtQuick
import QtQuick.Controls

Button {
    id: root

    property string glyph: ""
    property color tone: highlighted && enabled ? Tones.onAccent : enabled ? Tones.ink : Tones.disabled

    hoverEnabled: true
    padding: Tones.inset
    topPadding: Tones.small
    bottomPadding: Tones.small
    font.weight: Font.Medium
    Accessible.name: text
    contentItem: Row {
        spacing: Tones.gap
        SettingsIcon {
            visible: root.glyph !== ""
            name: root.glyph
            color: root.tone
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            visible: root.text !== ""
            text: root.text
            font: root.font
            color: root.tone
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    background: ControlBackground {
        hovered: root.hovered
        focused: root.visualFocus
        pressed: root.down
        primary: root.highlighted
        selected: root.checked
        quiet: root.flat
    }
}

import QtQuick
import QtQuick.Controls

/**
 * Button recipe: secondary by default, `highlighted` = primary, `flat` = ghost, `destructive` = error text that
 * gains an error tint on hover (`highlighted` + `destructive` = an armed destructive action).
 */
Button {
    id: root

    property string glyph: ""
    property bool destructive: false
    property color tone: !enabled ? Tones.textDisabled
        : destructive ? Tones.error
        : highlighted ? Tones.textOnAccent
        : flat ? (hovered || checked ? Tones.textPrimary : Tones.textSecondary)
        : Tones.textPrimary

    hoverEnabled: true
    leftPadding: text !== "" ? Tones.space4 : Tones.space2
    rightPadding: text !== "" ? Tones.space4 : Tones.space2
    topPadding: Tones.space1
    bottomPadding: Tones.space1
    implicitHeight: Tones.controlHeight
    implicitWidth: Math.max(text !== "" ? 0 : Tones.controlHeight, implicitContentWidth + leftPadding + rightPadding)
    font.pixelSize: Tones.bodySize
    font.weight: Font.DemiBold
    Accessible.name: text

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Tones.space2
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
    }
    background: ControlBackground {
        enabled: root.enabled
        hovered: root.hovered
        focused: root.visualFocus
        pressed: root.down
        primary: root.highlighted && !root.destructive
        destructive: root.destructive
        armed: root.highlighted && root.destructive
        selected: root.checked
        quiet: root.flat
    }
}

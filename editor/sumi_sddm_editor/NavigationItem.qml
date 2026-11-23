import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ItemDelegate {
    id: root

    required property string glyph
    property int customised: 0
    property bool pending: false

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: Tones.inset
    topPadding: Tones.small
    bottomPadding: Tones.small
    Accessible.name: text + (customised ? ", " + customised + " customised" : "")
        + (pending ? ", changes to apply" : "")
    Accessible.selected: highlighted

    contentItem: RowLayout {
        spacing: Tones.inset
        SettingsIcon { name: root.glyph; color: root.highlighted ? Tones.accent : Tones.muted }
        Label {
            Layout.fillWidth: true
            text: root.text
            elide: Text.ElideRight
            color: root.highlighted ? Tones.accent : Tones.ink
            font.weight: root.highlighted ? Font.DemiBold : Font.Normal
        }
        Label {
            visible: root.customised > 0
            text: root.customised
            color: Tones.accent
            font.pointSize: Tones.uiFont.pointSize * Tones.captionScale
        }
        Rectangle {
            objectName: root.glyph === "system" ? "applyDot" : ""
            visible: root.pending
            implicitWidth: 7
            implicitHeight: 7
            radius: width / 2
            color: Tones.pending
        }
    }
    background: ControlBackground {
        hovered: root.hovered
        focused: root.visualFocus
        pressed: root.down
        selected: root.highlighted
        quiet: true
        implicitHeight: Tones.navHeight
    }
}

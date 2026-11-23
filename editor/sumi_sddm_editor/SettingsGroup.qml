import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property alias title: heading.text
    default property alias rows: body.data

    spacing: Tones.gap
    Label {
        id: heading
        visible: text.length > 0
        font.weight: Font.DemiBold
        font.pointSize: Tones.uiFont.pointSize * Tones.headingScale
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Accessible.role: Accessible.Heading
    }
    Pane {
        padding: 0
        Layout.fillWidth: true
        background: Rectangle {
            color: Tones.surface
            radius: Tones.cardRadius
            border.color: Tones.border
            border.width: Tones.stroke
        }
        contentItem: ColumnLayout {
            id: body
            spacing: 0
        }
    }
}

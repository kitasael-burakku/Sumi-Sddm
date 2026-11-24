import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A named section: its heading, then one square group surface with a passive border. Rows separate themselves.
ColumnLayout {
    id: root

    property alias title: heading.text
    default property alias rows: body.data

    spacing: Tones.space3
    Label {
        id: heading
        visible: text.length > 0
        font.pixelSize: Tones.sectionHeadingSize
        font.weight: Font.DemiBold
        color: Tones.textPrimary
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        Accessible.role: Accessible.Heading
    }
    Pane {
        padding: 0
        Layout.fillWidth: true
        background: Rectangle {
            color: Tones.groupSurface
            radius: Tones.cornerRadius
            border.color: Tones.borderDefault
            border.width: Tones.stroke
        }
        contentItem: ColumnLayout {
            id: body
            spacing: 0
        }
    }
}

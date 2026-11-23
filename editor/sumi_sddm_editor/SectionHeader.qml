import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    property alias title: heading.text
    property alias description: detail.text

    spacing: Tones.small

    Label {
        id: heading
        objectName: "pageTitle"
        font.pointSize: Tones.uiFont.pointSize * Tones.titleScale
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
    }
    Label {
        id: detail
        visible: text.length > 0
        color: Tones.muted
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}

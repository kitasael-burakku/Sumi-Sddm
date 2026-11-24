import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Page heading (28/700, the strongest text in the editor) and its description.
ColumnLayout {
    property alias title: heading.text
    property alias description: detail.text

    spacing: Tones.space2

    Label {
        id: heading
        objectName: "pageTitle"
        font.pixelSize: Tones.pageHeadingSize
        font.weight: Font.Bold
        lineHeight: 1.05
        color: Tones.textPrimary
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
    }
    Label {
        id: detail
        visible: text.length > 0
        color: Tones.textSecondary
        font.pixelSize: Tones.bodySize
        lineHeight: 1.15
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}

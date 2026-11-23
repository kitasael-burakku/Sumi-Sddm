import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GridLayout {
    id: root

    property alias title: titleLabel.text
    property alias description: detail.text
    property alias descriptionColor: detail.color
    property bool modified: false
    property alias control: editor.sourceComponent
    property bool wideControl: false
    property bool divider: false
    property bool resettable: false
    property string defaultHint: ""
    signal reset()

    readonly property bool stacked: wideControl || width < editor.implicitWidth + 180

    columns: stacked ? 1 : 2
    rowSpacing: Tones.gap
    columnSpacing: Tones.inset

    ColumnLayout {
        spacing: Tones.small
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.margins: Tones.padding
        Layout.bottomMargin: root.stacked ? 0 : Tones.padding

        RowLayout {
            spacing: Tones.gap
            Label {
                id: titleLabel
                objectName: "label"
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            Rectangle {
                id: dot
                objectName: "customDot"
                visible: root.modified
                implicitWidth: 6
                implicitHeight: width
                radius: width / 2
                color: Tones.accent
                Accessible.role: Accessible.Indicator
                Accessible.name: "Customised"
            }
            ActionButton {
                objectName: "reset"
                glyph: "reset"
                flat: true
                visible: root.resettable && root.modified
                enabled: visible
                Accessible.name: "Reset " + root.title + " to its default"
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: root.defaultHint
                onClicked: root.reset()
            }
        }
        Label {
            id: detail
            objectName: "caption"
            visible: text.length > 0
            color: Tones.muted
            wrapMode: Text.Wrap
            font.pointSize: Tones.uiFont.pointSize * Tones.captionScale
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }
    Loader {
        id: editor
        Layout.fillWidth: root.stacked
        Layout.minimumWidth: root.stacked ? 0 : implicitWidth
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        Layout.rightMargin: Tones.padding
        Layout.leftMargin: root.stacked ? Tones.padding : 0
        Layout.topMargin: root.stacked ? 0 : Tones.gap
        Layout.bottomMargin: root.stacked ? Tones.padding : Tones.gap
    }
    Rectangle {
        visible: root.divider
        Layout.columnSpan: root.columns
        Layout.leftMargin: Tones.padding
        Layout.rightMargin: Tones.padding
        Layout.topMargin: -root.rowSpacing
        Layout.fillWidth: true
        implicitHeight: Tones.stroke
        color: Tones.border
    }
}

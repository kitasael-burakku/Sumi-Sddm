import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * One setting inside a group: label and helper text on the left, the control on the right, and between them, always
 * next to the control, the customised marker (a small frost square) and the local reset. When the control does not
 * fit beside the label it moves below it, full width, instead of clipping or shrinking text.
 */
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

    /** The label column keeps at least this much room before the control moves below it. */
    readonly property int labelMinimum: 168
    readonly property bool stacked: wideControl
        || width < editor.implicitWidth + marks.implicitWidth + labelMinimum + Tones.space4 * 2 + Tones.space3 * 2

    columns: stacked ? 2 : 3
    rowSpacing: 0
    columnSpacing: Tones.space3

    ColumnLayout {
        spacing: Tones.space1
        Layout.row: 0
        Layout.column: 0
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Tones.space4
        Layout.rightMargin: root.stacked && !marks.visible ? Tones.space4 : 0
        Layout.topMargin: Tones.space3
        Layout.bottomMargin: root.stacked ? Tones.space2 : Tones.space3

        Label {
            id: titleLabel
            objectName: "label"
            font.pixelSize: Tones.bodySize
            font.weight: Font.Medium
            color: Tones.textPrimary
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
        Label {
            id: detail
            objectName: "caption"
            visible: text.length > 0
            color: Tones.textSecondary
            wrapMode: Text.Wrap
            font.pixelSize: Tones.helperSize
            lineHeight: 1.15
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }

    RowLayout {
        id: marks
        visible: root.modified
        spacing: Tones.space1
        Layout.row: 0
        Layout.column: 1
        Layout.alignment: root.stacked ? Qt.AlignRight | Qt.AlignTop : Qt.AlignRight | Qt.AlignVCenter
        Layout.topMargin: root.stacked ? Tones.space2 : 0
        Layout.rightMargin: root.stacked ? Tones.space3 : 0

        Rectangle {
            id: dot
            objectName: "customDot"
            implicitWidth: Tones.markerSize
            implicitHeight: Tones.markerSize
            radius: Tones.cornerRadius
            color: Tones.modified
            Accessible.role: Accessible.Indicator
            Accessible.name: "Customised"
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: root.resettable ? 0 : Tones.space1
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
            ToolTip.delay: 400
            onClicked: root.reset()
        }
    }

    Loader {
        id: editor
        Layout.row: root.stacked ? 1 : 0
        Layout.column: root.stacked ? 0 : 2
        Layout.columnSpan: root.stacked ? 2 : 1
        Layout.fillWidth: root.stacked
        Layout.minimumWidth: root.stacked ? 0 : implicitWidth
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        Layout.rightMargin: Tones.space4
        Layout.leftMargin: root.stacked ? Tones.space4 : 0
        Layout.topMargin: root.stacked ? 0 : Tones.space2
        Layout.bottomMargin: root.stacked ? Tones.space3 : Tones.space2
    }

    Rectangle {
        visible: root.divider
        Layout.row: root.stacked ? 2 : 1
        Layout.column: 0
        Layout.columnSpan: root.columns
        Layout.leftMargin: Tones.space4
        Layout.rightMargin: Tones.space4
        Layout.fillWidth: true
        implicitHeight: Tones.stroke
        color: Tones.borderSubtle
    }
}

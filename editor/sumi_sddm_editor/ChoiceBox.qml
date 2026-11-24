pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Selector recipe: input geometry with a trailing chevron; the menu is a square overlay with rectangular rows.
ComboBox {
    id: root

    hoverEnabled: true
    implicitHeight: Tones.controlHeight
    leftPadding: Tones.space3
    rightPadding: Tones.space3 + Tones.space2 + Tones.iconSize
    topPadding: Tones.space1
    bottomPadding: Tones.space1
    font.pixelSize: Tones.bodySize

    contentItem: Label {
        text: root.displayText
        font: root.font
        color: root.enabled ? Tones.textPrimary : Tones.textDisabled
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: SettingsIcon {
        name: "chevron"
        x: root.width - Tones.space3 - width
        y: (root.height - height) / 2
        color: root.enabled ? Tones.textSecondary : Tones.textDisabled
    }
    background: ControlBackground {
        hovered: root.hovered
        focused: root.visualFocus
        pressed: root.down
        implicitWidth: 128
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: Tones.controlHeight
        leftPadding: Tones.space3
        rightPadding: Tones.space3
        highlighted: root.highlightedIndex === index
        hoverEnabled: true
        readonly property bool current: root.currentIndex === index
        text: root.textRole && modelData !== null && typeof modelData === "object" ? modelData[root.textRole] : modelData
        font.pixelSize: Tones.bodySize
        font.weight: current ? Font.DemiBold : Font.Normal
        contentItem: Label {
            text: option.text
            font: option.font
            color: option.current ? Tones.accent : Tones.textPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: option.down ? Tones.pressedSurface
                : option.highlighted || option.hovered ? Tones.hoverSurface
                : option.current ? Tones.selectedSurface : Tones.transparent
            Rectangle {
                visible: option.current
                width: Tones.indicatorWidth
                height: parent.height
                color: Tones.accent
            }
        }
    }
    popup: Popup {
        y: root.height + Tones.space1
        width: root.width
        implicitHeight: Math.min(contentItem.implicitHeight + 2 * Tones.stroke,
                                 root.Window.height - topMargin - bottomMargin)
        topMargin: Tones.space2
        bottomMargin: Tones.space2
        padding: Tones.stroke
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            highlightMoveDuration: 0
            ScrollBar.vertical: SquareScrollBar {}
        }
        background: Rectangle {
            color: Tones.overlaySurface
            border.width: Tones.stroke
            border.color: Tones.controlBorder
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tones.overlayDuration } }
    }
}

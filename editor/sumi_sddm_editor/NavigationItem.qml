import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Sidebar row: 16 px icon, label, and a plain frost count of customised settings (hidden at zero).
 * Hover = hover fill; active = selected fill, primary text and a 2 px frost left edge; focus = its own outline.
 */
ItemDelegate {
    id: root

    required property string glyph
    property int customised: 0
    property bool pending: false

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    leftPadding: Tones.space3
    rightPadding: Tones.space3
    topPadding: Tones.space1
    bottomPadding: Tones.space1
    implicitHeight: Tones.navHeight
    font.pixelSize: Tones.bodySize
    font.weight: Font.Medium
    Accessible.name: text + (customised ? ", " + customised + " customised" : "")
        + (pending ? ", changes to apply" : "")
    Accessible.selected: highlighted

    contentItem: RowLayout {
        spacing: Tones.space3
        SettingsIcon {
            name: root.glyph
            color: root.highlighted ? Tones.accent : root.hovered ? Tones.textPrimary : Tones.textSecondary
        }
        Label {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.text
            font: root.font
            elide: Text.ElideRight
            color: root.highlighted || root.hovered ? Tones.textPrimary : Tones.textSecondary
        }
        Label {
            visible: root.customised > 0
            text: root.customised
            color: Tones.accent
            font.family: Tones.mono
            font.pixelSize: Tones.metaSize
            font.weight: Font.Medium
        }
        Rectangle {
            objectName: root.glyph === "system" ? "applyDot" : ""
            visible: root.pending
            implicitWidth: Tones.markerSize + 1
            implicitHeight: implicitWidth
            radius: Tones.cornerRadius
            color: Tones.warning
        }
    }
    background: Rectangle {
        implicitHeight: Tones.navHeight
        color: root.down ? Tones.pressedSurface
            : root.highlighted ? Tones.selectedSurface
            : root.hovered ? Tones.hoverSurface : Tones.transparent
        Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }
        Rectangle {
            visible: root.highlighted
            width: Tones.indicatorWidth
            height: parent.height
            color: Tones.accent
        }
        FocusRing { shown: root.visualFocus; inset: true }
    }
}

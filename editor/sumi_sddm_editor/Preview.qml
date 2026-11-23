pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One panel and one Image for the saved-config render, even when the window changes layout.
SettingsScroll {
    id: root

    required property var backend
    property string screenSize: ""
    property bool canExpand: false
    property bool expanded: false
    signal toggleExpanded()

    readonly property var sizeList: {
        const sizes = ["1920x1080", "2560x1440", "1366x768", "1280x800", "3840x2160"];
        return [...new Set([root.screenSize, ...sizes, root.backend.previewSize].filter(Boolean))];
    }
    readonly property real aspect: {
        const size = /^(\d+)x(\d+)$/.exec(root.backend.previewSize);
        return size ? Number(size[2]) / Number(size[1]) : 9 / 16;
    }
    readonly property bool working: root.backend.previewStale && !root.backend.previewFailed

    function focusPanel() { scene.forceActiveFocus(Qt.TabFocusReason); }

    background: Rectangle {
        color: Tones.chrome
        Rectangle { width: Tones.stroke; height: parent.height; color: Tones.border }
    }

    Item {
        width: root.availableWidth
        implicitHeight: content.implicitHeight + Tones.gutter * 2

        ColumnLayout {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: Tones.gutter
            width: Math.min(1056, parent.width - Tones.gutter * 2)
            spacing: Tones.padding

            RowLayout {
                Layout.fillWidth: true
                SectionHeader {
                    title: "Preview"
                    description: "Rendered from your saved settings"
                    Layout.fillWidth: true
                }
                ActionButton {
                    objectName: "expandPreview"
                    visible: root.canExpand
                    glyph: root.expanded ? "collapse" : "expand"
                    flat: true
                    Accessible.name: root.expanded ? "Dock preview" : "Expand preview"
                    ToolTip.visible: hovered || visualFocus
                    ToolTip.text: Accessible.name
                    onClicked: root.toggleExpanded()
                }
            }

            Rectangle {
                objectName: "frame"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(144, Math.min(width * root.aspect, root.height - 225))
                color: Tones.frame
                border.width: Tones.stroke
                border.color: Tones.border
                radius: Tones.cardRadius

                Item {
                    anchors.fill: parent
                    anchors.margins: Tones.gap
                    Image {
                        id: shot
                        objectName: "previewImage"
                        anchors.fill: parent
                        source: root.backend.previewUrl
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        opacity: root.working ? 0.45 : 1
                        Behavior on opacity { NumberAnimation { duration: Tones.duration; easing.type: Tones.easing } }
                        Accessible.role: Accessible.Graphic
                        Accessible.name: "Login screen preview"
                    }
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.working && root.visible
                        visible: running
                    }
                    Label {
                        objectName: "previewPlaceholder"
                        anchors.centerIn: parent
                        width: parent.width - Tones.padding
                        visible: (shot.status !== Image.Ready || root.backend.previewFailed) && !root.working
                        text: root.backend.previewFailed ? "The preview could not be made" : "No preview yet"
                        color: Tones.frameText
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }
            Label {
                objectName: "stale"
                visible: root.working
                text: "Updating…"
                color: Tones.muted
                Accessible.role: Accessible.StaticText
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tones.inset
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Tones.small
                    Label { text: "Scene"; color: Tones.muted }
                    ChoiceBox {
                        id: scene
                        objectName: "scenario"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        model: root.backend.scenarios
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.backend.scenarios.findIndex(entry => entry.value === root.backend.scenario)
                        Accessible.name: "Preview scene"
                        onActivated: root.backend.scenario = currentValue
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: Tones.small
                    Label { text: "Resolution"; color: Tones.muted }
                    ChoiceBox {
                        objectName: "size"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        model: root.sizeList
                        currentIndex: root.sizeList.indexOf(root.backend.previewSize)
                        displayText: currentText + (currentText === root.screenSize ? "  (this screen)" : "")
                        Accessible.name: "Preview size"
                        onActivated: root.backend.previewSize = currentText
                    }
                }
            }

            ActionButton {
                objectName: "tryWindow"
                text: root.backend.tryArmed ? "Press again to open" : "Try in a window"
                glyph: "system"
                highlighted: root.backend.tryArmed
                Accessible.name: root.backend.tryArmed ? "Press again to open the test login window"
                    : "Try the login screen in a window"
                onClicked: root.backend.openTestWindow()
            }
            Label {
                text: "The test window takes keyboard input until you close it."
                color: Tones.muted
                font.pointSize: Tones.uiFont.pointSize * Tones.captionScale
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
}

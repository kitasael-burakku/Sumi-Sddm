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
    readonly property int pad: Tones.space5
    /** What sits under the frame (header, status, selectors, test window), so a short window still shows it all. */
    readonly property real chromeBelow: headerRow.implicitHeight + statusLine.implicitHeight + choices.implicitHeight
        + tryBlock.implicitHeight + tryBlock.Layout.topMargin + content.spacing * 4

    function focusPanel() { scene.forceActiveFocus(Qt.TabFocusReason); }

    background: Rectangle {
        color: Tones.previewBackground
        Rectangle { width: Tones.stroke; height: parent.height; color: Tones.borderSubtle }
    }

    Item {
        width: root.availableWidth
        implicitHeight: content.implicitHeight + root.pad * 2

        ColumnLayout {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.pad
            width: Math.min(1056, parent.width - root.pad * 2)
            spacing: Tones.space3

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Tones.space2
                ColumnLayout {
                    spacing: Tones.space1
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Label {
                        text: "Preview"
                        font.pixelSize: Tones.sectionHeadingSize
                        font.weight: Font.DemiBold
                        color: Tones.textPrimary
                        Accessible.role: Accessible.Heading
                    }
                    Label {
                        // lo que se ve es lo GUARDADO: nada sin guardar llega a la vista previa
                        text: "Rendered from your saved settings"
                        color: Tones.textSecondary
                        font.pixelSize: Tones.helperSize
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                ActionButton {
                    objectName: "expandPreview"
                    visible: root.canExpand
                    glyph: root.expanded ? "collapse" : "expand"
                    flat: true
                    Accessible.name: root.expanded ? "Dock preview" : "Expand preview"
                    ToolTip.visible: hovered || visualFocus
                    ToolTip.text: Accessible.name
                    ToolTip.delay: 400
                    Layout.alignment: Qt.AlignTop
                    onClicked: root.toggleExpanded()
                }
            }

            // El marco conserva la proporción de la resolución elegida (el greeter nunca se estira): el alto sale
            // del ancho, salvo que no quepa en la columna; entonces la imagen se encaja con bandas negras.
            Rectangle {
                id: frame
                objectName: "frame"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Math.max(144, Math.min((width - 2 * frameInset.anchors.margins) * root.aspect
                                                                 + 2 * frameInset.anchors.margins,
                                                                 root.height - root.pad * 2 - root.chromeBelow)))
                color: Tones.previewLetterbox
                border.width: Tones.stroke
                border.color: Tones.controlBorder
                radius: Tones.cornerRadius

                Item {
                    id: frameInset
                    anchors.fill: parent
                    anchors.margins: Tones.space1 + Tones.stroke
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
                        opacity: root.working ? 0.45 : root.backend.previewFailed ? 0.3 : 1
                        Behavior on opacity { NumberAnimation { duration: Tones.previewDuration; easing.type: Tones.easing } }
                        Accessible.role: Accessible.Graphic
                        Accessible.name: "Login screen preview"
                    }
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.working && root.visible
                        visible: running
                        palette.dark: Tones.accent
                    }
                    Label {
                        objectName: "previewPlaceholder"
                        anchors.centerIn: parent
                        width: parent.width - Tones.space4 * 2
                        visible: (shot.status !== Image.Ready || root.backend.previewFailed) && !root.working
                        text: root.backend.previewFailed
                            ? (shot.status === Image.Ready ? "The preview could not be made\nThe dimmed image is an older render"
                                                           : "The preview could not be made")
                            : "No preview yet"
                        color: root.backend.previewFailed ? Tones.error : Tones.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Estado de la imagen en texto, no sólo con la opacidad.
            RowLayout {
                id: statusLine
                spacing: Tones.space2
                Layout.fillWidth: true
                SettingsIcon {
                    name: root.backend.previewFailed ? "alert" : "check"
                    color: root.backend.previewFailed ? Tones.error : root.working ? Tones.info : Tones.textMuted
                    visible: !root.working
                }
                Label {
                    objectName: "stale"
                    visible: root.working
                    text: "Updating · the image shown is out of date"
                    color: Tones.info
                    font.pixelSize: Tones.helperSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Accessible.role: Accessible.StaticText
                }
                Label {
                    visible: !root.working
                    text: root.backend.previewFailed ? "Not up to date · the last render failed"
                        : shot.status === Image.Ready ? "Up to date with your saved settings"
                        : "Waiting for the first render"
                    color: root.backend.previewFailed ? Tones.error : Tones.textMuted
                    font.pixelSize: Tones.helperSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            GridLayout {
                id: choices
                Layout.fillWidth: true
                // una al lado de la otra si caben con sus valores; si no, una encima de otra
                columns: width >= 2 * 168 + Tones.space3 ? 2 : 1
                columnSpacing: Tones.space3
                rowSpacing: Tones.space3
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    spacing: Tones.space1
                    Label { text: "Scene"; color: Tones.textSecondary; font.pixelSize: Tones.helperSize }
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
                    Layout.preferredWidth: 1
                    spacing: Tones.space1
                    Label { text: "Resolution"; color: Tones.textSecondary; font.pixelSize: Tones.helperSize }
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

            ColumnLayout {
                id: tryBlock
                spacing: Tones.space2
                Layout.fillWidth: true
                Layout.topMargin: Tones.space1
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
                    color: root.backend.tryArmed ? Tones.warning : Tones.textSecondary
                    font.pixelSize: Tones.helperSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}

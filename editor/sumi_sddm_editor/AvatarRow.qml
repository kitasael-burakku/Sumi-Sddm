pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

// The avatar lives in AccountsService and uses the CLI's separate avatar commands.
Item {
    id: root

    required property var backend
    property bool divider: false

    implicitHeight: row.implicitHeight
    implicitWidth: row.implicitWidth

    readonly property var info: root.backend.avatar
    readonly property bool exists: !!(root.info && root.info.exists)
    property int serial: 0

    function choose(url) { root.backend.setAvatar(url); }

    objectName: "field-avatar"
    SettingsRow {
        id: row
        anchors.fill: parent
        divider: root.divider

        title: "Avatar"
        description: root.info ? root.backend.captionFor("avatar") : ""
        descriptionColor: root.info && root.info.error ? Tones.error : Tones.muted
        modified: root.exists

        control: RowLayout {
            spacing: Tones.gap
            Rectangle {
                objectName: "avatarFrame"
                implicitWidth: 42
                implicitHeight: width
                radius: width / 2
                color: Tones.control
                clip: true
                SettingsIcon { name: "users"; visible: !root.exists; anchors.centerIn: parent }
                Image {
                    objectName: "avatarImage"
                    anchors.fill: parent
                    visible: root.exists
                    source: root.exists ? "file://" + String(root.info.iconFile) + "?v=" + root.serial : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(96, 96)
                    cache: false
                    asynchronous: true
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Your picture"
                }
            }
            ActionButton {
                objectName: "chooseAvatar"
                text: "Choose picture…"
                Accessible.name: "Choose your picture"
                onClicked: pictures.open()
            }
            ActionButton {
                objectName: "removeAvatar"
                visible: root.exists
                text: "Remove"
                flat: true
                tone: Tones.error
                Accessible.name: "Remove your picture"
                onClicked: root.backend.clearAvatar()
            }
            Item { Layout.fillWidth: true }
        }
    }

    Connections {
        target: root.backend
        function onAvatarChanged() { root.serial++; }
    }

    FileDialog {
        id: pictures
        title: "Choose your picture"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: root.choose(selectedFile)
    }

    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (ev) => { if (ev.hasUrls && ev.urls.length > 0) root.choose(ev.urls[0]); }
    }
    Rectangle {
        anchors.fill: parent
        visible: drop.containsDrag
        color: Tones.unfilled
        border.width: Tones.focusStroke
        border.color: Tones.accent
        radius: Tones.controlRadius
    }
}

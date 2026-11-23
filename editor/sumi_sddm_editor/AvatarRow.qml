pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

/**
 * El avatar no es una clave del tema: es de AccountsService (`sumi-sddm avatar info|set|clear`, sin contraseña).
 * Va como primera fila del grupo Users, como en Settings. La CLI lo recorta a un cuadrado de 512 px; el greeter lo
 * enseña en un círculo. También se puede soltar una imagen sobre la fila.
 */
Item {
    id: root

    required property var backend

    readonly property var info: root.backend.avatar
    readonly property bool exists: !!(root.info && root.info.exists)
    readonly property string caption: { root.backend.avatar; return root.backend.captionFor("avatar"); }
    /** Otra URL en cada cambio: el archivo de AccountsService se llama igual antes y después. */
    property int serial: 0

    /** Lo que pasa al elegir (diálogo) o soltar (arrastrar) una imagen. */
    function choose(url) { root.backend.setAvatar(url); }

    objectName: "field-avatar"
    implicitHeight: row.implicitHeight + 12

    Connections {
        target: root.backend
        function onAvatarChanged() { root.serial++; }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 12

        Rectangle {
            objectName: "avatarFrame"
            implicitWidth: 48
            implicitHeight: 48
            radius: 24
            color: palette.mid
            clip: true
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
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: "Avatar"
                font.weight: Font.DemiBold
            }
            Label {
                objectName: "caption"
                visible: text.length > 0
                text: root.caption
                color: root.info && root.info.error ? "#d9534f" : palette.placeholderText
                wrapMode: Text.Wrap
                font.pointSize: Qt.application.font.pointSize * 0.9
                Layout.fillWidth: true
            }
        }
        Button {
            objectName: "chooseAvatar"
            text: "Choose picture…"
            Accessible.name: "Choose your picture"
            onClicked: pictures.open()
        }
        Button {
            objectName: "removeAvatar"
            visible: root.exists
            text: "Remove"
            Accessible.name: "Remove your picture"
            onClicked: root.backend.clearAvatar()
        }
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
        color: "transparent"
        border.width: 2
        border.color: palette.highlight
        radius: 4
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * La pantalla de inicio de verdad: `sumi-sddm system …` → helper → polkit (pkexec pide la contraseña de un
 * administrador cada vez). El editor nunca corre como root y nunca toca el sistema por su cuenta.
 *
 *   estado        `system status`: instalado, activo (y qué archivo lo decide), si lo aplicado = lo guardado
 *   Apply         `system apply`: lleva lo guardado al tema instalado; sólo cuando no coincide. Espera a que no
 *                 quede nada por escribir (lo hace el backend)
 *   Use / Restore `system activate|deactivate`: dos pulsaciones; surten efecto la PRÓXIMA vez que aparezca la
 *                 pantalla de inicio (SDDM no se reinicia)
 *   último arranque `system log`: si el greeter de Sumi arrancó bien y, si no, qué problemas tuvo
 *   recuperación  la orden para una TTY y la guía instalada
 */
SettingsScroll {
    id: root

    required property var backend

    readonly property var sys: root.backend.system
    readonly property bool installed: !!(root.sys && root.sys.installed === true)
    readonly property bool active: root.installed && root.sys.active === true
    readonly property bool inSync: root.installed && root.sys.inSync === true
    readonly property string busy: root.backend.systemBusy
    readonly property var log: root.backend.systemLog
    readonly property var greeter: root.log && root.log.greeters && root.log.greeters.length > 0
        ? root.log.greeters[root.log.greeters.length - 1] : null

    Component.onCompleted: { root.backend.refreshSystem(); root.backend.refreshLog(); }

    Item {
        width: root.availableWidth
        implicitHeight: content.implicitHeight + gutter * 2
        readonly property int gutter: width >= 440 ? Tones.gutter : Tones.padding

        ColumnLayout {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.gutter
            width: Math.min(760, parent.width - parent.gutter * 2)
            spacing: Tones.sectionGap

            SectionHeader {
                title: "Login screen"
                description: "Apply your settings, choose the active theme and check the last greeter startup."
                Layout.fillWidth: true
            }

            SettingsGroup {
                title: "Installation"
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.padding
                    spacing: Tones.gap
                    GridLayout {
                        objectName: "statusGrid"
                        visible: root.installed
                        columns: 2
                        Layout.fillWidth: true
                        columnSpacing: Tones.padding
                        rowSpacing: Tones.gap

                        Label { text: "Theme"; color: palette.placeholderText }
                        Label {
                            objectName: "installedText"
                            text: "Sumi SDDM " + String(root.sys ? root.sys.version || "" : "") + " is installed"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                        Label { text: "In use"; color: palette.placeholderText }
                        Label {
                            objectName: "activeText"
                            text: root.active ? "Sumi is your login screen"
                                : "Your login screen uses “" + String(root.sys ? root.sys.activeTheme || "SDDM's default" : "") + "”"
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            ToolTip.visible: decidedHover.hovered && !!(root.sys && root.sys.decidedBy)
                            ToolTip.text: "Decided by " + String(root.sys ? root.sys.decidedBy || "" : "")
                            HoverHandler { id: decidedHover }
                        }
                        Label { text: "Your settings"; color: palette.placeholderText }
                        Label {
                            objectName: "syncText"
                            text: root.inSync ? "Applied · the login screen shows what you see here"
                                              : "Not applied yet · the login screen still shows the previous settings"
                            color: root.inSync ? palette.windowText : Tones.pending
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        objectName: "notInstalled"
                        visible: !!root.sys && !root.installed          // sin estado todavía (undefined), nada
                        text: root.sys && root.sys.error && !root.sys.missing
                            ? "The system state could not be read: " + root.sys.error
                            : "The Sumi SDDM theme is not installed system-wide, so nothing here can reach the login screen yet. "
                              + "Install the sumi-sddm package; your settings stay saved meanwhile."
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        objectName: "busyRow"
                        visible: root.busy.length > 0
                        Layout.fillWidth: true
                        spacing: Tones.gap
                        BusyIndicator { running: parent.visible; implicitWidth: 24; implicitHeight: 24 }
                        Label {
                            text: "Waiting for an administrator password, then changing the login screen…"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Apply and activate"
                Layout.fillWidth: true
                visible: root.installed

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.padding
                    spacing: Tones.gap

                    ActionButton {
                        objectName: "apply"
                        // con el texto, no sólo con el gris de «desactivado»: algunas paletas apenas lo distinguen
                        text: root.inSync ? "Already applied" : "Apply to login screen"
                        enabled: !root.inSync && root.busy.length === 0
                        highlighted: !root.inSync
                        Accessible.name: "Apply your settings to the login screen"
                        onClicked: root.backend.systemApply()
                    }
                    Label {
                        text: "Copies your saved settings and wallpaper to the installed theme. Asks for an administrator "
                            + "password. The theme is tested with them first; if it fails, nothing changes."
                        wrapMode: Text.Wrap
                        color: palette.placeholderText
                        font.pointSize: Tones.uiFont.pointSize * Tones.captionScale
                        Layout.fillWidth: true
                    }

                    Item { Layout.preferredHeight: Tones.small }

                    ActionButton {
                        objectName: "activate"
                        visible: !root.active
                        text: root.backend.activateArmed ? "Press again to use Sumi" : "Use as login screen"
                        enabled: root.busy.length === 0
                        highlighted: root.backend.activateArmed
                        Accessible.name: root.backend.activateArmed ? "Press again to make Sumi your login screen"
                                                                    : "Use Sumi as your login screen"
                        onClicked: root.backend.activateSystem()
                    }
                    ActionButton {
                        objectName: "deactivate"
                        visible: root.active
                        text: root.backend.deactivateArmed ? "Press again to restore" : "Restore previous theme"
                        enabled: root.busy.length === 0
                        highlighted: root.backend.deactivateArmed
                        Accessible.name: root.backend.deactivateArmed ? "Press again to restore the previous login screen"
                                                                      : "Restore the previous login screen theme"
                        onClicked: root.backend.deactivateSystem()
                    }
                    Label {
                        objectName: "switchHelp"
                        text: (root.active
                               ? "Goes back to " + (root.sys && root.sys.previousTheme ? "“" + root.sys.previousTheme + "”"
                                                                                       : "the theme used before Sumi")
                               : "Makes Sumi your login screen")
                            + " the next time the login screen appears (after logging out or restarting). Nothing restarts "
                            + "now. Asks for an administrator password."
                        wrapMode: Text.Wrap
                        color: root.backend.activateArmed || root.backend.deactivateArmed ? palette.windowText
                                                                                        : palette.placeholderText
                        font.pointSize: Tones.uiFont.pointSize * Tones.captionScale
                        Layout.fillWidth: true
                    }
                }
            }

            SettingsGroup {
                title: "Startup log"
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.padding
                    spacing: Tones.gap

                    RowLayout {
                        Label {
                            objectName: "logText"
                            text: !root.log ? "Reading this boot's log…"
                                : root.log.error ? "This boot's log could not be read: " + root.log.error
                                : root.greeter === null ? "No login screen has been shown since this computer started"
                                : !root.greeter.sumi ? "Last login screen: another theme (" + root.greeter.theme + ")"
                                : root.greeter.ok ? "Last login screen: Sumi started correctly"
                                : "Last login screen: Sumi had problems"
                            color: root.greeter && root.greeter.sumi && !root.greeter.ok ? Tones.error : palette.windowText
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        ActionButton {
                            flat: true
                            objectName: "refreshLog"
                            text: "Refresh"
                            Accessible.name: "Refresh the login screen status"
                            onClicked: { root.backend.refreshSystem(); root.backend.refreshLog(); }
                        }
                    }
                    Repeater {
                        objectName: "problems"
                        model: root.greeter && root.greeter.problems ? root.greeter.problems : []
                        delegate: Label {
                            required property var modelData
                            text: "· " + String(modelData)
                            wrapMode: Text.Wrap
                            font.family: Tones.mono
                            font.pointSize: Tones.uiFont.pointSize * 0.85
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            SettingsGroup {
                title: "Recovery"
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.padding
                    spacing: Tones.gap

                    Label { text: "If the login screen ever fails"; font.weight: Font.DemiBold }
                    Label {
                        text: "Switch to a text console (Ctrl+Alt+F3), log in and run this; it restores the previous theme:"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    InputField {
                        objectName: "recoveryCommand"
                        text: root.backend.recoveryCommand
                        readOnly: true
                        selectByMouse: true
                        font.family: Tones.mono
                        Accessible.name: "Recovery command"
                        Layout.fillWidth: true
                    }
                    ActionButton {
                        objectName: "recoveryDoc"
                        visible: root.backend.recoveryDoc.length > 0
                        text: "Open the recovery guide"
                        Accessible.name: text
                        onClicked: Qt.openUrlExternally(root.backend.recoveryDoc)
                    }
                }
            }

        }
    }
}

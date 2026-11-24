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
    readonly property bool greeterFailed: !!(root.greeter && root.greeter.sumi && !root.greeter.ok)

    Component.onCompleted: { root.backend.refreshSystem(); root.backend.refreshLog(); }

    // Una fila de estado: nombre a la izquierda (secundario), valor a la derecha; debajo del nombre si no cabe.
    component StatusRow: GridLayout {
        id: statusRow
        property alias label: name.text
        default property alias value: valueSlot.data
        property bool divider: true
        columns: width >= 420 ? 2 : 1
        columnSpacing: Tones.space4
        rowSpacing: Tones.space1
        Layout.fillWidth: true
        Label {
            id: name
            color: Tones.textSecondary
            font.pixelSize: Tones.helperSize
            Layout.preferredWidth: statusRow.columns === 2 ? 112 : -1
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Tones.space3
            Layout.bottomMargin: statusRow.columns === 2 ? Tones.space3 : 0
            Layout.leftMargin: Tones.space4
        }
        RowLayout {
            id: valueSlot
            spacing: Tones.space2
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.topMargin: statusRow.columns === 2 ? Tones.space3 : 0
            Layout.bottomMargin: Tones.space3
            Layout.leftMargin: statusRow.columns === 2 ? 0 : Tones.space4
            Layout.rightMargin: Tones.space4
        }
        Rectangle {
            visible: statusRow.divider
            Layout.columnSpan: statusRow.columns
            Layout.fillWidth: true
            Layout.leftMargin: Tones.space4
            Layout.rightMargin: Tones.space4
            implicitHeight: Tones.stroke
            color: Tones.borderSubtle
        }
    }

    Item {
        width: root.availableWidth
        implicitHeight: content.implicitHeight + gutter * 2
        readonly property int gutter: width >= Tones.contentMinWidth + Tones.contentPadding * 2
            ? Tones.contentPadding : Tones.contentPaddingCompact

        ColumnLayout {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.gutter
            width: Math.min(Tones.contentMaxWidth, parent.width - parent.gutter * 2)
            spacing: Tones.space8

            SectionHeader {
                title: "Login screen"
                description: "Apply your settings, choose the active theme and check the last greeter startup."
                Layout.fillWidth: true
            }

            // ---- estado del sistema: sólo lo que `system status` sabe ------------------------------------------
            SettingsGroup {
                title: "Installation"
                Layout.fillWidth: true

                ColumnLayout {
                    objectName: "statusGrid"
                    visible: root.installed
                    spacing: 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    StatusRow {
                        label: "Theme"
                        Label {
                            objectName: "installedText"
                            text: "Sumi SDDM " + String(root.sys ? root.sys.version || "" : "") + " is installed"
                            color: Tones.textPrimary
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                    StatusRow {
                        label: "In use"
                        Label {
                            objectName: "activeText"
                            text: root.active ? "Sumi is your login screen"
                                : "Your login screen uses “" + String(root.sys ? root.sys.activeTheme || "SDDM's default" : "") + "”"
                            color: Tones.textPrimary
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            ToolTip.visible: decidedHover.hovered && !!(root.sys && root.sys.decidedBy)
                            ToolTip.text: "Decided by " + String(root.sys ? root.sys.decidedBy || "" : "")
                            HoverHandler { id: decidedHover }
                        }
                    }
                    StatusRow {
                        label: "Your settings"
                        divider: false
                        SettingsIcon {
                            name: root.inSync ? "check" : "alert"
                            color: root.inSync ? Tones.success : Tones.warning
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 1
                        }
                        Label {
                            objectName: "syncText"
                            text: root.inSync ? "Applied · the login screen shows what you see here"
                                              : "Not applied yet · the login screen still shows the previous settings"
                            color: root.inSync ? Tones.success : Tones.warning
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Label {
                    objectName: "notInstalled"
                    visible: !!root.sys && !root.installed          // sin estado todavía (undefined), nada
                    text: root.sys && root.sys.error && !root.sys.missing
                        ? "The system state could not be read: " + root.sys.error
                        : "The Sumi SDDM theme is not installed system-wide, so nothing here can reach the login screen yet. "
                          + "Install the sumi-sddm package; your settings stay saved meanwhile."
                    color: root.sys && root.sys.error && !root.sys.missing ? Tones.error : Tones.textPrimary
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.margins: Tones.space4
                }
            }

            // ---- acciones con privilegios: cada una dice qué cambia y dónde ----------------------------------------
            SettingsGroup {
                title: "Apply and activate"
                Layout.fillWidth: true
                visible: root.installed

                RowLayout {
                    objectName: "busyRow"
                    visible: root.busy.length > 0
                    spacing: Tones.space2
                    Layout.fillWidth: true
                    Layout.leftMargin: Tones.space4
                    Layout.rightMargin: Tones.space4
                    Layout.topMargin: Tones.space3
                    BusyIndicator {
                        running: parent.visible
                        implicitWidth: Tones.iconSize + Tones.space2
                        implicitHeight: implicitWidth
                        palette.dark: Tones.info
                    }
                    Label {
                        text: "Waiting for an administrator password, then changing the login screen…"
                        color: Tones.info
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }

                SettingsRow {
                    title: "Apply your settings"
                    description: "Copies your saved settings and wallpaper to the installed theme. Asks for an "
                        + "administrator password. The theme is tested with them first; if it fails, nothing changes."
                    divider: true
                    Layout.fillWidth: true
                    control: ActionButton {
                        objectName: "apply"
                        // con el texto, no sólo con el gris de «desactivado»: algunas paletas apenas lo distinguen
                        text: root.inSync ? "Already applied" : "Apply to login screen"
                        glyph: root.inSync ? "check" : ""
                        enabled: !root.inSync && root.busy.length === 0
                        highlighted: !root.inSync
                        Accessible.name: "Apply your settings to the login screen"
                        onClicked: root.backend.systemApply()
                    }
                }

                GridLayout {
                    id: switchRow
                    readonly property bool stacked: width < switchButtons.implicitWidth + 168 + Tones.space4 * 2 + Tones.space3
                    columns: stacked ? 1 : 2
                    columnSpacing: Tones.space3
                    rowSpacing: Tones.space2
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: Tones.space1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.leftMargin: Tones.space4
                        Layout.rightMargin: switchRow.stacked ? Tones.space4 : 0
                        Layout.topMargin: Tones.space3
                        Layout.bottomMargin: switchRow.stacked ? 0 : Tones.space3
                        Label {
                            text: root.active ? "Restore the previous theme" : "Use Sumi as the login screen"
                            font.weight: Font.Medium
                            color: Tones.textPrimary
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
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
                            color: root.backend.activateArmed || root.backend.deactivateArmed ? Tones.warning
                                                                                            : Tones.textSecondary
                            font.pixelSize: Tones.helperSize
                            lineHeight: 1.15
                            Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        id: switchButtons
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.leftMargin: switchRow.stacked ? Tones.space4 : 0
                        Layout.rightMargin: Tones.space4
                        Layout.bottomMargin: switchRow.stacked ? Tones.space3 : 0
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
                            destructive: true
                            highlighted: root.backend.deactivateArmed
                            Accessible.name: root.backend.deactivateArmed ? "Press again to restore the previous login screen"
                                                                          : "Restore the previous login screen theme"
                            onClicked: root.backend.deactivateSystem()
                        }
                    }
                }
            }

            // ---- último arranque -----------------------------------------------------------------------------------
            SettingsGroup {
                title: "Startup log"
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.space4
                    Layout.topMargin: Tones.space3
                    Layout.bottomMargin: Tones.space3
                    spacing: Tones.space2

                    RowLayout {
                        spacing: Tones.space2
                        SettingsIcon {
                            visible: !!root.greeter && root.greeter.sumi
                            name: root.greeterFailed ? "alert" : "check"
                            color: root.greeterFailed ? Tones.error : Tones.success
                        }
                        Label {
                            objectName: "logText"
                            text: !root.log ? "Reading this boot's log…"
                                : root.log.error ? "This boot's log could not be read: " + root.log.error
                                : root.greeter === null ? "No login screen has been shown since this computer started"
                                : !root.greeter.sumi ? "Last login screen: another theme (" + root.greeter.theme + ")"
                                : root.greeter.ok ? "Last login screen: Sumi started correctly"
                                : "Last login screen: Sumi had problems"
                            color: root.greeterFailed || (root.log && root.log.error) ? Tones.error : Tones.textPrimary
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        ActionButton {
                            objectName: "refreshLog"
                            text: "Refresh"
                            glyph: "reset"
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
                            color: Tones.textSecondary
                            font.family: Tones.mono
                            font.pixelSize: Tones.monoSize
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ---- recuperación ---------------------------------------------------------------------------------------
            SettingsGroup {
                title: "Recovery"
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.margins: Tones.space4
                    spacing: Tones.space2

                    Label {
                        text: "If the login screen ever fails"
                        font.weight: Font.Medium
                        color: Tones.textPrimary
                    }
                    Label {
                        text: "Switch to a text console (Ctrl+Alt+F3), log in and run this; it restores the previous theme:"
                        color: Tones.textSecondary
                        font.pixelSize: Tones.helperSize
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    InputField {
                        objectName: "recoveryCommand"
                        text: root.backend.recoveryCommand
                        readOnly: true
                        selectByMouse: true
                        monospace: true
                        Accessible.name: "Recovery command"
                        Layout.fillWidth: true
                    }
                    ActionButton {
                        objectName: "recoveryDoc"
                        visible: root.backend.recoveryDoc.length > 0
                        text: "Open the recovery guide"
                        Accessible.name: text
                        Layout.topMargin: Tones.space1
                        onClicked: Qt.openUrlExternally(root.backend.recoveryDoc)
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * La ventana del editor.
 *
 * Barra lateral con los grupos del esquema y búsqueda (por etiqueta o clave, en todos los grupos) y, aparte, la
 * página «Login screen» (SystemPanel: estado, Apply / Use / Restore con pkexec, último arranque, recuperación).
 * En medio, un Field por clave (y el avatar, primera fila de Users); a la derecha, la vista previa, que se puede
 * ocultar (sin ella no se genera ninguna). Pie: el aviso o el error del backend, «Apply to login screen» si lo
 * guardado no está aplicado, cuántas claves están personalizadas, «Restore previous» y «Reset all» (dos
 * pulsaciones). Al volver el foco se relee (`recheck`): si algo cambió desde la terminal o desde Settings, se
 * avisa. Al cerrar con escrituras pendientes, se escriben antes de salir; con una operación de sistema en curso
 * (esperando la contraseña o aplicando), la ventana espera a que termine.
 */
ApplicationWindow {
    id: win

    required property var backend

    property string selectedGroup: ""
    /** "settings" (grupos del esquema) o "system" (la pantalla de inicio de verdad). */
    property string page: "settings"
    readonly property var sys: win.backend.system
    readonly property bool needsApply: !!(win.sys && win.sys.installed === true && win.sys.inSync === false)
    readonly property string group: win.selectedGroup.length > 0 ? win.selectedGroup
        : (win.backend.groups.length > 0 ? win.backend.groups[0].id : "")
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var shownKeys: {
        const keys = win.backend.keys;
        return win.backend.order.filter(k => {
            const e = keys[k] || {};
            if (win.query.length === 0) return e.group === win.group;
            return k.toLowerCase().indexOf(win.query) >= 0
                || String(e.label || "").toLowerCase().indexOf(win.query) >= 0;
        });
    }
    readonly property string groupLabel: {
        const g = win.backend.groups.find(x => x.id === win.group);
        return g ? g.label : "";
    }
    property bool closeWhenIdle: false
    property bool showPreview: true
    readonly property bool showAvatar: win.query.length > 0 ? "avatar picture photo".indexOf(win.query) >= 0
                                                            : win.group === "users"

    width: 1280
    height: 760
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    title: "Login Screen (Sumi)"

    onActiveChanged: if (win.active) win.backend.recheck()
    Component.onCompleted: {
        // La vista previa, por defecto, al tamaño real de esta pantalla (el greeter dibuja en píxeles físicos).
        const w = Math.round(Screen.width * Screen.devicePixelRatio), h = Math.round(Screen.height * Screen.devicePixelRatio);
        if (w >= 100 && h >= 100) {
            preview.screenSize = w + "x" + h;
            win.backend.previewSize = preview.screenSize;
        }
    }
    Binding { target: win.backend; property: "previewEnabled"; value: win.showPreview }
    onClosing: (close) => {
        if (win.backend.systemBusy.length > 0) {
            // pkexec espera una contraseña o el helper está trabajando: no se deja a medias
            close.accepted = false;
            win.closeWhenIdle = true;
            win.backend.inform("The window will close when the login screen change finishes");
        } else if (win.backend.busy) {
            close.accepted = false;
            win.closeWhenIdle = true;
            win.backend.flushNow();
        }
    }
    Connections {
        target: win.backend
        function onBusyChanged() { win.closeIfIdle(); }
        function onSystemBusyChanged() { win.closeIfIdle(); }
    }
    function closeIfIdle() {
        if (win.closeWhenIdle && !win.backend.busy && win.backend.systemBusy.length === 0) win.close();
    }

    Shortcut { sequences: [StandardKey.Find]; onActivated: search.forceActiveFocus() }
    Shortcut { sequences: [StandardKey.Quit, StandardKey.Close]; onActivated: win.close() }

    // ---- estados que no son «ready» ------------------------------------------------------------------------------
    ColumnLayout {
        objectName: "statusPage"
        visible: !win.backend.ready
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 520)
        spacing: 12

        BusyIndicator {
            visible: win.backend.status === "" || win.backend.status === "checking"
            running: visible
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            objectName: "statusTitle"
            text: win.backend.status === "missing" ? "The sumi-sddm command was not found"
                : win.backend.status === "incompatible" ? "This sumi-sddm is a different version"
                : win.backend.status === "broken" ? "sumi-sddm did not answer as expected"
                : "Loading…"
            font.pointSize: Qt.application.font.pointSize * 1.3
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        Label {
            objectName: "statusDetail"
            text: win.backend.status === "missing"
                ? "Install the sumi-sddm package, which provides the command, and try again."
                : win.backend.statusDetail
            visible: text.length > 0 && win.backend.status !== "checking"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: palette.placeholderText
            Layout.fillWidth: true
        }
        Button {
            objectName: "retry"
            visible: ["missing", "incompatible", "broken"].indexOf(win.backend.status) >= 0
            text: "Try again"
            Layout.alignment: Qt.AlignHCenter
            onClicked: win.backend.load()
        }
    }

    // ---- formulario ---------------------------------------------------------------------------------------------
    RowLayout {
        objectName: "form"
        visible: win.backend.ready
        anchors.fill: parent
        spacing: 0

        Pane {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            padding: 8
            background: Rectangle { color: palette.alternateBase }

            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                TextField {
                    id: search
                    objectName: "search"
                    placeholderText: "Search settings"
                    Accessible.name: "Search settings"
                    Layout.fillWidth: true
                    Keys.onEscapePressed: text = ""
                    onTextChanged: if (text.length > 0) win.page = "settings"
                }
                ListView {
                    id: groupList
                    objectName: "groups"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: win.backend.groups
                    keyNavigationEnabled: true
                    delegate: ItemDelegate {
                        id: gd
                        required property var modelData
                        required property int index
                        readonly property int custom: win.backend.order.filter(k =>
                            (win.backend.keys[k] || {}).group === gd.modelData.id
                            && (win.backend.values[k] || {}).set === true).length
                        objectName: "group-" + gd.modelData.id
                        width: ListView.view.width
                        text: gd.modelData.label + (gd.custom > 0 ? "  ·  " + gd.custom : "")
                        highlighted: win.page === "settings" && win.query.length === 0 && win.group === gd.modelData.id
                        Accessible.name: gd.modelData.label + (gd.custom > 0 ? ", " + gd.custom + " customised" : "")
                        onClicked: {
                            search.text = "";
                            win.page = "settings";
                            win.selectedGroup = gd.modelData.id;
                            groupList.currentIndex = gd.index;
                        }
                    }
                }
                MenuSeparator { Layout.fillWidth: true }
                ItemDelegate {
                    id: sysItem
                    objectName: "page-system"
                    text: "Login screen"
                    highlighted: win.page === "system"
                    Layout.fillWidth: true
                    Accessible.name: "Login screen" + (win.needsApply ? ", your settings are not applied yet" : "")
                    ToolTip.visible: hovered && win.needsApply
                    ToolTip.text: "Your settings are not applied to the login screen yet"
                    onClicked: { search.text = ""; win.page = "system"; }
                    // un punto, no texto: en la barra lateral no cabe «not applied»
                    Rectangle {
                        objectName: "applyDot"
                        visible: win.needsApply
                        width: 8
                        height: 8
                        radius: 4
                        color: "#e08a1e"
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Loader {
            objectName: "systemPage"
            active: win.page === "system"
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            // se crea al abrir la página: así relee el estado y el registro cada vez
            sourceComponent: SystemPanel { backend: win.backend }
        }

        ScrollView {
            id: scroll
            objectName: "scroll"
            visible: win.page === "settings"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 0

                Label {
                    objectName: "pageTitle"
                    readonly property int results: win.shownKeys.length + (win.showAvatar ? 1 : 0)
                    text: win.query.length > 0 ? (results === 1 ? "1 result" : results + " results") : win.groupLabel
                    font.pointSize: Qt.application.font.pointSize * 1.4
                    font.weight: Font.DemiBold
                    Layout.margins: 20
                    Layout.bottomMargin: 8
                }
                AvatarRow {
                    visible: win.showAvatar
                    backend: win.backend
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 16
                }
                Repeater {
                    objectName: "fields"
                    model: win.shownKeys
                    delegate: Field {
                        required property string modelData
                        backend: win.backend
                        key: modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 16
                    }
                }
                Label {
                    visible: win.query.length > 0 && win.shownKeys.length === 0 && !win.showAvatar
                    text: "Nothing matches “" + search.text.trim() + "”"
                    color: palette.placeholderText
                    Layout.margins: 20
                }
                Item { Layout.preferredHeight: 16 }
            }
        }

        Preview {
            id: preview
            objectName: "preview"
            backend: win.backend
            visible: win.showPreview
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(320, Math.min(520, win.width * 0.36))
        }
    }

    footer: ToolBar {
        visible: win.backend.ready
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 8
            Label {
                objectName: "message"
                readonly property bool isError: win.backend.error.length > 0
                text: isError ? win.backend.error : win.backend.notice
                color: isError ? "#d9534f" : palette.windowText
                elide: Text.ElideRight
                Layout.fillWidth: true
                Accessible.role: Accessible.AlertMessage
            }
            ToolButton {
                objectName: "dismiss"
                visible: win.backend.error.length > 0 || win.backend.notice.length > 0
                text: "×"
                Accessible.name: "Dismiss message"
                onClicked: win.backend.dismiss()
            }
            Button {
                objectName: "quickApply"
                visible: win.needsApply && win.page !== "system"
                enabled: win.backend.systemBusy.length === 0
                text: win.backend.systemBusy === "apply" ? "Applying…" : "Apply to login screen"
                highlighted: true
                Accessible.name: "Apply your settings to the login screen"
                onClicked: win.backend.systemApply()
            }
            BusyIndicator {
                visible: win.backend.busy
                running: visible
                implicitWidth: 24
                implicitHeight: 24
            }
            Label {
                objectName: "customCount"
                text: win.backend.customCount === 0 ? "All defaults"
                    : win.backend.customCount === 1 ? "1 customised" : win.backend.customCount + " customised"
                color: palette.placeholderText
            }
            Button {
                objectName: "togglePreview"
                text: win.showPreview ? "Hide preview" : "Show preview"
                onClicked: win.showPreview = !win.showPreview
            }
            Button {
                objectName: "restore"
                text: "Restore previous"
                ToolTip.visible: hovered
                ToolTip.text: "Bring back the settings saved before the last reset"
                onClicked: win.backend.restorePrevious()
            }
            Button {
                objectName: "resetAll"
                text: win.backend.resetArmed ? "Press again to reset" : "Reset all"
                enabled: win.backend.customCount > 0
                highlighted: win.backend.resetArmed
                Accessible.name: win.backend.resetArmed ? "Press again to reset every setting" : "Reset all settings"
                onClicked: win.backend.resetAll()
            }
        }
    }
}

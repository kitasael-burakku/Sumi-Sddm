pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * La ventana del editor (fase 2: formulario; la vista previa y el sistema llegan en las fases 3 y 4).
 *
 * Barra lateral con los grupos del esquema y búsqueda (por etiqueta o clave, en todos los grupos); a la derecha,
 * un Field por clave. Pie: el aviso o el error del backend, cuántas claves están personalizadas, «Restore
 * previous» y «Reset all» (dos pulsaciones). Al volver el foco se relee (`recheck`): si algo cambió desde la
 * terminal o desde Settings, se avisa. Al cerrar con escrituras pendientes, se escriben antes de salir.
 */
ApplicationWindow {
    id: win

    required property var backend

    property string selectedGroup: ""
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

    width: 960
    height: 680
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    title: "Login Screen (Sumi)"

    onActiveChanged: if (win.active) win.backend.recheck()
    onClosing: (close) => {
        if (win.backend.busy) {
            close.accepted = false;
            win.closeWhenIdle = true;
            win.backend.flushNow();
        }
    }
    Connections {
        target: win.backend
        function onBusyChanged() { if (win.closeWhenIdle && !win.backend.busy) win.close(); }
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
                        highlighted: win.query.length === 0 && win.group === gd.modelData.id
                        Accessible.name: gd.modelData.label + (gd.custom > 0 ? ", " + gd.custom + " customised" : "")
                        onClicked: { search.text = ""; win.selectedGroup = gd.modelData.id; groupList.currentIndex = gd.index; }
                    }
                }
            }
        }

        ScrollView {
            id: scroll
            objectName: "scroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 0

                Label {
                    objectName: "pageTitle"
                    text: win.query.length > 0
                        ? (win.shownKeys.length === 1 ? "1 result" : win.shownKeys.length + " results")
                        : win.groupLabel
                    font.pointSize: Qt.application.font.pointSize * 1.4
                    font.weight: Font.DemiBold
                    Layout.margins: 20
                    Layout.bottomMargin: 8
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
                    visible: win.query.length > 0 && win.shownKeys.length === 0
                    text: "Nothing matches “" + search.text.trim() + "”"
                    color: palette.placeholderText
                    Layout.margins: 20
                }
                Item { Layout.preferredHeight: 16 }
            }
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Vista previa: el PNG de `sumi-sddm preview` con lo GUARDADO (lo que verá el greeter), 600 ms después del último
 * cambio y una a la vez (lo decide el backend). Mientras se genera otra, la anterior se queda atenuada.
 *
 * Escena (las de Settings) y tamaño (por defecto, el de la pantalla en píxeles reales). «Try in a window» abre el
 * greeter real con `try --yes`: toma el teclado hasta cerrar esa ventana, así que pide dos pulsaciones.
 */
Pane {
    id: root

    required property var backend
    /** Tamaños ofrecidos además del de la pantalla («AnchoxAlto»). */
    property var sizes: ["1920x1080", "2560x1440", "1366x768", "1280x800", "3840x2160"]
    property string screenSize: ""

    readonly property var sizeList: {
        const l = root.screenSize.length > 0 ? [root.screenSize] : [];
        for (const s of root.sizes) if (l.indexOf(s) < 0) l.push(s);
        if (l.indexOf(root.backend.previewSize) < 0) l.push(root.backend.previewSize);
        return l;
    }
    readonly property real aspect: {
        const m = /^(\d+)x(\d+)$/.exec(root.backend.previewSize);
        return m ? Number(m[2]) / Number(m[1]) : 9 / 16;
    }
    readonly property bool working: root.backend.previewStale && !root.backend.previewFailed

    padding: 16

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Preview"
                font.weight: Font.DemiBold
                font.pointSize: Qt.application.font.pointSize * 1.2
                Layout.fillWidth: true
            }
            ComboBox {
                objectName: "scenario"
                model: root.backend.scenarios
                textRole: "label"
                valueRole: "value"
                currentIndex: root.backend.scenarios.findIndex(s => s.value === root.backend.scenario)
                Accessible.name: "Preview scene"
                onActivated: root.backend.scenario = currentValue
            }
        }

        Rectangle {
            objectName: "frame"
            Layout.fillWidth: true
            Layout.preferredHeight: width * root.aspect
            color: "#101114"
            radius: 4
            clip: true

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
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Accessible.role: Accessible.Graphic
                Accessible.name: "Login screen preview"
            }
            BusyIndicator {
                anchors.centerIn: parent
                running: root.working
                visible: running
            }
            Label {
                objectName: "previewPlaceholder"
                anchors.centerIn: parent
                visible: shot.status !== Image.Ready && !root.working
                text: root.backend.previewFailed ? "The preview could not be made" : "No preview yet"
                color: "#c8c8cc"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Size" }
            ComboBox {
                objectName: "size"
                model: root.sizeList
                currentIndex: root.sizeList.indexOf(root.backend.previewSize)
                displayText: currentText + (currentText === root.screenSize ? "  (this screen)" : "")
                Accessible.name: "Preview size"
                Layout.fillWidth: true
                onActivated: root.backend.previewSize = currentText
            }
        }

        Label {
            objectName: "stale"
            visible: root.working
            text: "Updating…"
            color: palette.placeholderText
        }

        Item { Layout.preferredHeight: 4 }

        Button {
            objectName: "tryWindow"
            text: root.backend.tryArmed ? "Press again to open" : "Try in a window"
            highlighted: root.backend.tryArmed
            Accessible.name: root.backend.tryArmed ? "Press again to open the test window" : "Try the login screen in a window"
            onClicked: root.backend.openTestWindow()
        }
        Label {
            objectName: "tryHelp"
            text: "Opens the real login screen in a window with your saved settings. It takes the keyboard until you "
                + "close that window; logging in and power buttons do nothing there."
            wrapMode: Text.Wrap
            color: root.backend.tryArmed ? palette.windowText : palette.placeholderText
            font.pointSize: Qt.application.font.pointSize * 0.9
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

/**
 * Una clave del esquema (`sumi-sddm config schema`) → un control según su tipo:
 *
 *   bool → Switch · enum → botones si hay ≤ 4 valores, si no ComboBox · integer/number → Slider + campo
 *   (`allowZero`: casilla «Off») · color → muestra + ColorDialog (con alfa) + campo hex · string → campo de texto
 *   · fontFamily → lista con búsqueda de `config fonts` (las familias sólo de tu $HOME se marcan: el greeter, que
 *   corre como el usuario sddm, no las ve); sin la lista, campo de texto
 *   · path (el fondo) → «Choose image…» (FileDialog → `wallpaper set`), soltar una imagen sobre la fila, y «Remove»
 *   (`wallpaper clear`)
 *
 * Etiqueta, `help` (o el aviso de `config show` para esa clave), punto de «personalizado» y «Reset» (→ unset).
 * La CLI valida en serio; aquí sólo se evita enviar lo que a todas luces no vale (rango, hex, `pattern`) para dar
 * el aviso en inglés junto al campo. La interacción no rompe los enlaces de Switch, ComboBox o Slider; los campos de
 * texto sí se vuelven a enlazar después de cada edición: si lo escrito no se envió (o no cambió nada), el valor
 * guardado no cambia y, sin eso, el campo seguiría enseñando lo tecleado.
 */
Item {
    id: root

    required property var backend
    required property string key

    objectName: "field-" + root.key

    readonly property var entry: root.backend.keys[root.key] || ({})
    readonly property string type: String(root.entry.type || "")
    readonly property string label: String(root.entry.label || root.key)
    readonly property var current: root.backend.values[root.key] || ({})
    readonly property var value: root.current.value
    readonly property bool isSet: root.current.set === true
    readonly property string caption: { root.backend.warnings; root.backend.keys; return root.backend.captionFor(root.key); }
    readonly property bool warned: root.backend.warnings.some(w => w.key === root.key)
    /** Lo que no se envió por no valer (en inglés, junto al campo). Se borra al siguiente cambio válido. */
    property string problem: ""
    /** Lo que la CLI rechazó de esta clave en la última escritura (`fields` de su respuesta). */
    readonly property string rejected: String(root.backend.fieldErrors[root.key] || "")

    function send(v) { root.problem = ""; root.backend.set(root.key, v); }

    implicitHeight: Math.max(row.implicitHeight, 40) + 12
    implicitWidth: row.implicitWidth

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 160
            spacing: 2
            RowLayout {
                spacing: 6
                Label {
                    objectName: "label"
                    text: root.label
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Rectangle {
                    objectName: "customDot"
                    visible: root.isSet
                    implicitWidth: 7
                    implicitHeight: 7
                    radius: 3.5
                    color: palette.highlight
                    Accessible.role: Accessible.Indicator
                    Accessible.name: "Customised"
                }
            }
            Label {
                objectName: "caption"
                visible: text.length > 0
                text: root.problem.length > 0 ? root.problem : root.rejected.length > 0 ? root.rejected : root.caption
                color: root.problem.length > 0 || root.rejected.length > 0 || root.warned ? Tones.error
                                                                                        : palette.placeholderText
                wrapMode: Text.Wrap
                font.pointSize: Qt.application.font.pointSize * 0.9
                Layout.fillWidth: true
            }
        }

        Loader {
            id: loader
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            sourceComponent: root.type === "bool" ? boolC
                : root.type === "enum" ? ((root.entry.values || []).length <= 4 ? segmentsC : comboC)
                : root.type === "integer" || root.type === "number" ? numberC
                : root.type === "color" ? colorC
                : root.type === "path" ? pathC
                : root.type === "string" && root.key === "fontFamily" && root.backend.fonts.length > 0 ? fontC
                : root.type === "string" ? textC : null
        }

        ToolButton {
            objectName: "reset"
            text: "Reset"
            opacity: root.isSet ? 1 : 0
            enabled: root.isSet
            Accessible.name: "Reset " + root.label + " to its default"
            ToolTip.visible: hovered
            ToolTip.text: "Default: " + (String(root.entry["default"]) || "empty")
            onClicked: { root.problem = ""; root.backend.unset(root.key); }
        }
    }

    DropArea {
        id: drop
        anchors.fill: parent
        enabled: root.type === "path"
        keys: ["text/uri-list"]
        onDropped: (ev) => { if (ev.hasUrls && ev.urls.length > 0) root.backend.setWallpaper(ev.urls[0]); }
    }
    Rectangle {
        anchors.fill: parent
        visible: drop.containsDrag
        color: "transparent"
        border.width: 2
        border.color: palette.highlight
        radius: 4
    }

    // ---- controles -------------------------------------------------------------------------------------------------
    Component {
        id: boolC
        Switch {
            objectName: "switch"
            checked: root.value === true
            Accessible.name: root.label
            onToggled: root.send(checked)
        }
    }

    Component {
        id: segmentsC
        Row {
            objectName: "segments"
            spacing: 0
            Repeater {
                model: root.entry.values || []
                delegate: Button {
                    required property var modelData
                    objectName: "segment-" + modelData
                    text: root.backend.enumLabel(modelData)
                    checkable: false
                    checked: root.value === modelData
                    Accessible.name: root.label + ": " + text
                    Accessible.checkable: true
                    Accessible.checked: checked
                    onClicked: if (root.value !== modelData) root.send(modelData)
                }
            }
        }
    }

    Component {
        id: comboC
        ComboBox {
            readonly property var vals: root.entry.values || []
            objectName: "combo"
            implicitWidth: 180
            model: vals.map(v => root.backend.enumLabel(v))
            currentIndex: vals.indexOf(root.value)
            Accessible.name: root.label
            onActivated: (i) => root.send(vals[i])
        }
    }

    Component {
        id: numberC
        RowLayout {
            id: num
            readonly property var e: root.entry
            readonly property bool integer: root.type === "integer"
            readonly property real lo: Number(num.e.min)
            readonly property real hi: Number(num.e.max)
            readonly property real stepv: Number(num.e.step || (num.integer ? 1 : 0.05))
            readonly property bool off: num.e.allowZero === true && Number(root.value) === 0
            readonly property string unit: num.e.unit ? " " + num.e.unit : ""
            function fmt(n) { return num.integer ? String(Math.round(n)) : String(Math.round(n * 1000) / 1000); }
            function snap(n) {
                n = num.lo + Math.round((n - num.lo) / num.stepv) * num.stepv;
                n = Math.max(num.lo, Math.min(num.hi, Math.round(n * 1000) / 1000));
                return num.integer ? Math.round(n) : n;
            }
            spacing: 8

            CheckBox {
                objectName: "off"
                visible: num.e.allowZero === true
                text: "Off"
                checked: num.off
                Accessible.name: root.label + " off"
                onToggled: {
                    const d = Number(root.entry["default"]);
                    root.send(checked ? 0 : (d > 0 ? d : num.lo));
                }
            }
            Slider {
                objectName: "slider"
                enabled: !num.off
                from: num.lo
                to: num.hi
                stepSize: num.stepv
                snapMode: Slider.SnapAlways
                value: num.off ? num.lo : Number(root.value)
                implicitWidth: 200
                Accessible.name: root.label
                onMoved: {
                    const n = num.snap(value);
                    if (n !== Number(root.value)) root.send(n);
                }
            }
            TextField {
                objectName: "number"
                enabled: !num.off
                text: num.off ? "" : num.fmt(Number(root.value))
                placeholderText: num.off ? "Off" : ""
                horizontalAlignment: Text.AlignRight
                implicitWidth: 72
                rightPadding: unitLabel.visible ? unitLabel.implicitWidth + 10 : leftPadding
                inputMethodHints: num.integer ? Qt.ImhFormattedNumbersOnly : Qt.ImhPreferNumbers
                Accessible.name: root.label + " value" + num.unit
                Label {
                    id: unitLabel
                    visible: num.unit.length > 0
                    text: num.unit.trim()
                    color: palette.placeholderText
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                }
                onEditingFinished: {
                    const t = text.trim().replace(",", ".");
                    const n = Number(t);
                    if (t.length > 0 && !isNaN(n) && n !== Number(root.value)) {
                        if (n < num.lo || n > num.hi)
                            root.problem = "Use a value between " + num.fmt(num.lo) + " and " + num.fmt(num.hi);
                        else
                            root.send(num.integer ? Math.round(n) : Math.round(n * 1000) / 1000);
                    }
                    text = Qt.binding(() => num.off ? "" : num.fmt(Number(root.value)));
                }
            }
        }
    }

    Component {
        id: colorC
        RowLayout {
            id: col
            spacing: 8
            function hexOf(c) {
                const h = (n) => ("0" + Math.round(n * 255).toString(16)).slice(-2);
                return "#" + (c.a < 1 ? h(c.a) : "") + h(c.r) + h(c.g) + h(c.b);
            }
            Button {
                objectName: "swatch"
                implicitWidth: 36
                implicitHeight: 28
                Accessible.name: "Choose " + root.label + " colour"
                contentItem: Rectangle {
                    radius: 3
                    color: String(root.value || "#000000")
                    border.width: 1
                    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.6)
                }
                onClicked: { dialog.selectedColor = String(root.value || "#000000"); dialog.open(); }
            }
            TextField {
                objectName: "hex"
                text: String(root.value || "")
                placeholderText: String(root.entry["default"] || "#000000")
                implicitWidth: 110
                font.family: "monospace"
                Accessible.name: root.label + " colour"
                onEditingFinished: {
                    const raw = text.trim();
                    const t = raw.replace(/^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/, "#$1").toLowerCase();
                    if (raw.length > 0 && t !== String(root.value || "").toLowerCase()) {
                        if (/^#([0-9a-f]{6}|[0-9a-f]{8})$/.test(t)) root.send(t);
                        else root.problem = "“" + raw + "” is not a colour · use #rrggbb or #aarrggbb";
                    }
                    text = Qt.binding(() => String(root.value || ""));
                }
            }
            ColorDialog {
                id: dialog
                title: root.label
                options: ColorDialog.ShowAlphaChannel
                onAccepted: root.send(col.hexOf(selectedColor))
            }
        }
    }

    Component {
        id: textC
        TextField {
            objectName: "text"
            text: String(root.value || "")
            placeholderText: root.key === "fontFamily" ? "Bundled Inter" : String(root.entry["default"] || "Default")
            maximumLength: root.entry.maxLength || 32767
            implicitWidth: 220
            Accessible.name: root.label
            onEditingFinished: {
                const t = text.trim();
                if (t !== String(root.value || "")) {
                    if (t.length === 0) { root.problem = ""; root.backend.unset(root.key); }
                    else if (root.entry.pattern && !(new RegExp(root.entry.pattern)).test(t))
                        root.problem = "Some characters are not allowed here";
                    else root.send(t);
                }
                text = Qt.binding(() => String(root.value || ""));
            }
        }
    }

    Component {
        id: fontC
        Button {
            id: fontButton
            readonly property string family: String(root.value || "")
            readonly property var found: root.backend.fonts.find(f => f.family === fontButton.family)
            objectName: "fontButton"
            implicitWidth: 220
            text: fontButton.family.length > 0 ? fontButton.family : "Bundled Inter"
            font.family: fontButton.family.length > 0 ? fontButton.family : Qt.application.font.family
            Accessible.name: root.label + ": " + text
            onClicked: { fontSearch.text = ""; fontPopup.open(); fontSearch.forceActiveFocus(); }

            Popup {
                id: fontPopup
                objectName: "fontPopup"
                y: fontButton.height + 4
                x: fontButton.width - width
                width: 320
                height: 380
                padding: 8
                focus: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    TextField {
                        id: fontSearch
                        objectName: "fontSearch"
                        placeholderText: "Search " + root.backend.fonts.length + " fonts"
                        Accessible.name: "Search fonts"
                        Layout.fillWidth: true
                        Keys.onDownPressed: { fontList.forceActiveFocus(); fontList.currentIndex = 0; }
                        Keys.onReturnPressed: if (fontList.count > 0) fontList.pick(fontList.model[0])
                    }
                    FontMetrics { id: uiMetrics; font: Qt.application.font }
                    ListView {
                        id: fontList
                        objectName: "fontList"
                        readonly property string q: fontSearch.text.trim().toLowerCase()
                        function pick(entry) {
                            fontPopup.close();
                            if (entry.family === "") {
                                if (root.isSet) root.backend.unset(root.key);
                            } else if (entry.family !== fontButton.family) {
                                root.send(entry.family);
                            }
                        }
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        keyNavigationEnabled: true
                        // la primera fila es el valor por defecto (Inter, incluida en el tema)
                        model: [{ family: "", system: true }].concat(root.backend.fonts).filter(f =>
                            fontList.q.length === 0 || (f.family === "" ? "bundled inter default" : f.family.toLowerCase())
                                .indexOf(fontList.q) >= 0)
                        ScrollBar.vertical: ScrollBar {}
                        delegate: ItemDelegate {
                            id: fd
                            required property var modelData
                            objectName: "font-" + (fd.modelData.family || "bundled")
                            width: ListView.view.width
                            highlighted: fd.modelData.family === fontButton.family
                            Accessible.name: (fd.modelData.family || "Bundled Inter")
                                + (fd.modelData.system ? "" : ", only in your home folder")
                            contentItem: ColumnLayout {
                                spacing: 0
                                Label {
                                    // cada familia en su letra, pero en la altura de una fila de la interfaz:
                                    // las de métricas enormes se encogen hasta caber
                                    text: fd.modelData.family || "Bundled Inter (default)"
                                    font.family: fd.modelData.family || Qt.application.font.family
                                    font.pointSize: Qt.application.font.pointSize
                                    fontSizeMode: Text.Fit
                                    minimumPointSize: 6
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    clip: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.ceil(uiMetrics.height * 1.25)
                                }
                                Label {
                                    visible: !fd.modelData.system
                                    text: "Only in your home folder · the login screen can't use it"
                                    color: Tones.error
                                    font.pointSize: Qt.application.font.pointSize * 0.8
                                }
                            }
                            onClicked: fontList.pick(fd.modelData)
                            Keys.onReturnPressed: fontList.pick(fd.modelData)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: pathC
        RowLayout {
            id: pathRow
            /** Lo que pasa al elegir (diálogo) o soltar (arrastrar) una imagen. */
            function choose(url) { root.backend.setWallpaper(url); }
            objectName: "wallpaperRow"
            spacing: 8
            Label {
                objectName: "pathValue"
                text: String(root.value || "").length > 0 ? String(root.value).replace(/^backgrounds\//, "")
                                                          : "Built-in background"
                color: String(root.value || "").length > 0 ? palette.text : palette.placeholderText
                elide: Text.ElideMiddle
                Layout.maximumWidth: 180
            }
            Button {
                objectName: "choose"
                text: "Choose image…"
                Accessible.name: "Choose a wallpaper image"
                onClicked: files.open()
            }
            Button {
                objectName: "remove"
                visible: String(root.value || "").length > 0
                text: "Remove"
                Accessible.name: "Remove the wallpaper"
                onClicked: root.backend.clearWallpaper()
            }
            FileDialog {
                id: files
                title: "Choose a wallpaper"
                nameFilters: ["Images (" + (root.entry.extensions || ["jpg", "jpeg", "png", "webp"])
                              .map(x => "*." + x).join(" ") + ")"]
                onAccepted: pathRow.choose(selectedFile)
            }
        }
    }
}

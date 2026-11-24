pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

/**
 * Una clave del esquema (`sumi-sddm config schema`) → un control según su tipo:
 *
 *   bool → Switch · enum → control segmentado si hay ≤ 4 valores, si no ComboBox · integer/number → Slider + campo
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
    property bool divider: false

    implicitHeight: row.implicitHeight
    implicitWidth: row.implicitWidth
    required property string key

    objectName: "field-" + root.key

    readonly property var entry: root.backend.keys[root.key] || ({})
    readonly property string type: String(root.entry.type || "")
    readonly property string label: String(root.entry.label || root.key)
    readonly property var current: root.backend.values[root.key] || ({})
    readonly property var value: root.current.value
    readonly property bool isSet: root.current.set === true
    readonly property var warning: root.backend.warnings.find(w => w.key === root.key)
    readonly property bool warned: !!root.warning
    readonly property string caption: root.warning || root.entry.help ? root.backend.captionFor(root.key) : ""
    /** Lo que no se envió por no valer (en inglés, junto al campo). Se borra al siguiente cambio válido. */
    property string problem: ""
    /** Lo que la CLI rechazó de esta clave en la última escritura (`fields` de su respuesta). */
    readonly property string rejected: String(root.backend.fieldErrors[root.key] || "")
    readonly property size windowSize: Qt.size(Window.width, Window.height)
    /** El valor escrito no se envió o la CLI lo rechazó: borde de error en el campo, explicación debajo de la etiqueta. */
    readonly property bool invalid: root.problem.length > 0 || root.rejected.length > 0

    function send(v) { root.problem = ""; root.backend.set(root.key, v); }

    // El control segmentado sólo si cabe entero en la fila (con texto grande o ventana estrecha, el desplegable):
    // se mide con el texto, no con el control ya creado, para no entrar en un bucle de maquetación.
    FontMetrics { id: segmentMetrics; font.family: Tones.sans; font.pixelSize: Tones.bodySize; font.weight: Font.DemiBold }
    readonly property real segmentsWidth: (root.entry.values || []).reduce((sum, v) =>
        sum + Math.ceil(segmentMetrics.advanceWidth(root.backend.enumLabel(v))) + 2 * Tones.space3, 2 * Tones.stroke)
    readonly property bool segmentsFit: root.width <= 0 || root.segmentsWidth <= root.width - 2 * Tones.space4

    SettingsRow {
        id: row
        anchors.fill: parent
        divider: root.divider

        title: root.label
        description: root.problem || root.rejected || root.caption
        descriptionColor: root.problem || root.rejected || root.warned ? Tones.error : Tones.textSecondary
        modified: root.isSet
        resettable: root.type !== "path"
        defaultHint: "Default: " + (String(root.entry["default"]) || "empty")
        wideControl: root.type === "path"
        onReset: { root.problem = ""; root.backend.unset(root.key); }

        control: root.type === "bool" ? boolC
            : root.type === "enum" ? ((root.entry.values || []).length <= 4 && root.segmentsFit ? segmentsC : comboC)
            : root.type === "integer" || root.type === "number" ? numberC
            : root.type === "color" ? colorC
            : root.type === "path" ? pathC
            : root.type === "string" && root.key === "fontFamily" && root.backend.fonts.length > 0 ? fontC
            : root.type === "string" ? textC : null
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
        color: Tones.transparent
        border.width: Tones.focusStroke
        border.color: Tones.accent
        radius: Tones.cornerRadius
    }

    // ---- controles -------------------------------------------------------------------------------------------------
    Component {
        id: boolC
        ToggleSwitch {
            objectName: "switch"
            checked: root.value === true
            Accessible.name: root.label
            onToggled: root.send(checked)
        }
    }

    Component {
        id: segmentsC
        // Un solo rectángulo: segmentos contiguos, borde exterior de 1 px y separadores; el activo, relleno escarcha.
        Pane {
            id: segments
            objectName: "segments"
            readonly property var values: root.entry.values || []
            readonly property int widest: {
                let w = 0;
                for (let i = 0; i < segmentRepeater.count; ++i) {
                    const it = segmentRepeater.itemAt(i);
                    if (it) w = Math.max(w, it.implicitWidth);
                }
                return w;
            }
            padding: Tones.stroke
            background: Rectangle {
                radius: Tones.cornerRadius
                color: Tones.controlSurface
                border.width: Tones.stroke
                border.color: Tones.controlBorder
            }
            contentItem: RowLayout {
                spacing: 0
                Repeater {
                    id: segmentRepeater
                    model: segments.values
                    delegate: AbstractButton {
                        id: segment
                        required property var modelData
                        required property int index
                        readonly property bool active: root.value === modelData
                        objectName: "segment-" + modelData
                        text: root.backend.enumLabel(modelData)
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        checkable: false
                        checked: active
                        leftPadding: Tones.space3
                        rightPadding: Tones.space3
                        implicitHeight: Tones.controlHeight - 2 * Tones.stroke
                        implicitWidth: implicitContentWidth + leftPadding + rightPadding
                        Layout.fillWidth: true
                        Layout.preferredWidth: segments.widest
                        Layout.minimumWidth: implicitWidth
                        font.pixelSize: Tones.bodySize
                        font.weight: active ? Font.DemiBold : Font.Normal
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: root.label + ": " + text
                        Accessible.checkable: true
                        Accessible.checked: active
                        contentItem: Label {
                            text: segment.text
                            font: segment.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: segment.active ? Tones.textOnAccent
                                : segment.hovered ? Tones.textPrimary : Tones.textSecondary
                        }
                        background: Rectangle {
                            color: segment.active ? (segment.down ? Tones.accentPressed : Tones.accent)
                                : segment.down ? Tones.pressedSurface
                                : segment.hovered ? Tones.hoverSurface : Tones.transparent
                            Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }
                            Rectangle {
                                visible: segment.index > 0
                                width: Tones.stroke
                                height: parent.height
                                x: -Tones.stroke
                                color: Tones.controlBorder
                            }
                            FocusRing { shown: segment.visualFocus; inset: true }
                        }
                        onClicked: if (root.value !== modelData) root.send(modelData)
                    }
                }
            }
        }
    }

    Component {
        id: comboC
        ChoiceBox {
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
            spacing: Tones.space2

            CheckMark {
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
            NumericSlider {
                objectName: "slider"
                enabled: !num.off
                from: num.lo
                to: num.hi
                stepSize: num.stepv
                snapMode: Slider.SnapAlways
                value: num.off ? num.lo : Number(root.value)
                implicitWidth: 128
                Layout.fillWidth: true
                Layout.minimumWidth: 72
                Accessible.name: root.label
                onMoved: {
                    const n = num.snap(value);
                    if (n !== Number(root.value)) root.send(n);
                }
            }
            TextMetrics {
                id: widest
                font.family: Tones.mono
                font.pixelSize: Tones.monoSize
                text: [num.fmt(num.lo), num.fmt(num.hi), num.fmt(num.lo + num.stepv)]
                    .reduce((a, b) => b.length > a.length ? b : a, "000")
            }
            InputField {
                objectName: "number"
                enabled: !num.off
                monospace: true
                invalid: root.invalid
                text: num.off ? "" : num.fmt(Number(root.value))
                placeholderText: num.off ? "Off" : ""
                horizontalAlignment: Text.AlignRight
                implicitWidth: Math.max(72, Math.ceil(widest.advanceWidth) + leftPadding + rightPadding + 2)
                rightPadding: unitLabel.visible ? unitLabel.implicitWidth + Tones.space2 + Tones.space1 : Tones.space3
                inputMethodHints: num.integer ? Qt.ImhFormattedNumbersOnly : Qt.ImhPreferNumbers
                Accessible.name: root.label + " value" + num.unit
                Label {
                    id: unitLabel
                    visible: num.unit.length > 0
                    text: num.unit.trim()
                    color: Tones.textMuted
                    font.pixelSize: Tones.metaSize
                    anchors.right: parent.right
                    anchors.rightMargin: Tones.space2
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
            spacing: Tones.space2
            function hexOf(c) {
                const h = (n) => ("0" + Math.round(n * 255).toString(16)).slice(-2);
                return "#" + (c.a < 1 ? h(c.a) : "") + h(c.r) + h(c.g) + h(c.b);
            }
            ActionButton {
                id: swatch
                objectName: "swatch"
                readonly property color shown: String(root.value || "#000000")
                implicitWidth: Tones.controlHeight
                implicitHeight: Tones.controlHeight
                Accessible.name: "Choose " + root.label + " colour"
                padding: (Tones.controlHeight - Math.max(Tones.swatchSize, Tones.controlHeight - 12)) / 2
                // con alfa (#aarrggbb), un damero bajo la muestra deja ver la transparencia
                contentItem: Item {
                    Grid {
                        anchors.fill: parent
                        visible: swatch.shown.a < 1
                        columns: 4
                        Repeater {
                            model: 16
                            Rectangle {
                                required property int index
                                width: parent.width / 4
                                height: parent.height / 4
                                color: (Math.floor(index / 4) + index) % 2 ? Tones.checkerDark : Tones.checkerLight
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Tones.cornerRadius
                        color: swatch.shown
                        border.width: Tones.stroke
                        border.color: Tones.borderHover
                    }
                }
                onClicked: { dialog.selectedColor = String(root.value || "#000000"); dialog.open(); }
            }
            InputField {
                objectName: "hex"
                text: String(root.value || "")
                placeholderText: String(root.entry["default"] || "#000000")
                implicitWidth: 112
                monospace: true
                invalid: root.invalid
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
        InputField {
            objectName: "text"
            text: String(root.value || "")
            placeholderText: root.key === "fontFamily" ? "Bundled Inter" : String(root.entry["default"] || "Default")
            maximumLength: root.entry.maxLength || 32767
            implicitWidth: 220
            invalid: root.invalid
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
        ActionButton {
            id: fontButton
            readonly property string family: String(root.value || "")
            objectName: "fontButton"
            implicitWidth: 220
            text: fontButton.family.length > 0 ? fontButton.family : "Bundled Inter"
            font.family: fontButton.family.length > 0 ? fontButton.family : Tones.sans
            leftPadding: Tones.space3
            rightPadding: Tones.space3 + Tones.space2 + Tones.iconSize
            contentItem: Label {
                text: fontButton.text
                font.family: fontButton.font.family
                font.pixelSize: Tones.bodySize
                color: Tones.textPrimary
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            SettingsIcon {
                name: "chevron"
                anchors.right: parent.right
                anchors.rightMargin: Tones.space3
                anchors.verticalCenter: parent.verticalCenter
            }
            Accessible.name: root.label + ": " + text
            onClicked: { fontSearch.text = ""; fontPopup.open(); fontSearch.forceActiveFocus(); }

            Popup {
                id: fontPopup
                objectName: "fontPopup"
                y: fontButton.height + Tones.space1
                x: fontButton.width - width
                width: Math.min(320, Math.max(1, root.windowSize.width - Tones.space6))
                height: Math.min(380, Math.max(1, root.windowSize.height - Tones.space6))
                margins: Tones.space2
                padding: Tones.space2
                focus: true
                background: Rectangle {
                    color: Tones.overlaySurface
                    border.width: Tones.stroke
                    border.color: Tones.controlBorder
                }
                enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tones.overlayDuration } }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Tones.space2
                    InputField {
                        id: fontSearch
                        objectName: "fontSearch"
                        placeholderText: "Search " + root.backend.fonts.length + " fonts"
                        Accessible.name: "Search fonts"
                        Layout.fillWidth: true
                        Keys.onDownPressed: { fontList.forceActiveFocus(); fontList.currentIndex = 0; }
                        Keys.onReturnPressed: if (fontList.count > 0) fontList.pick(fontList.model[0])
                    }
                    FontMetrics { id: uiMetrics; font.family: Tones.sans; font.pixelSize: Tones.bodySize }
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
                        ScrollBar.vertical: SquareScrollBar {}
                        delegate: ItemDelegate {
                            id: fd
                            required property var modelData
                            objectName: "font-" + (fd.modelData.family || "bundled")
                            width: ListView.view.width
                            hoverEnabled: true
                            leftPadding: Tones.space3
                            rightPadding: Tones.space3
                            highlighted: fd.modelData.family === fontButton.family
                            background: Rectangle {
                                color: fd.down ? Tones.pressedSurface
                                    : fd.hovered || fd.activeFocus ? Tones.hoverSurface
                                    : fd.highlighted ? Tones.selectedSurface : Tones.transparent
                                Rectangle {
                                    visible: fd.highlighted
                                    width: Tones.indicatorWidth
                                    height: parent.height
                                    color: Tones.accent
                                }
                                FocusRing { shown: fd.visualFocus; inset: true }
                            }
                            Accessible.name: (fd.modelData.family || "Bundled Inter")
                                + (fd.modelData.system ? "" : ", only in your home folder")
                            contentItem: ColumnLayout {
                                spacing: 0
                                Label {
                                    // cada familia en su letra, pero en la altura de una fila de la interfaz:
                                    // las de métricas enormes se encogen hasta caber
                                    text: fd.modelData.family || "Bundled Inter (default)"
                                    font.family: fd.modelData.family || Tones.sans
                                    font.pixelSize: Tones.bodySize
                                    color: fd.highlighted ? Tones.accent : Tones.textPrimary
                                    fontSizeMode: Text.Fit
                                    minimumPixelSize: 8
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    clip: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.ceil(uiMetrics.height * 1.25)
                                }
                                Label {
                                    visible: !fd.modelData.system
                                    text: "Only in your home folder · the login screen can't use it"
                                    color: Tones.warning
                                    font.pixelSize: Tones.metaSize
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
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
        GridLayout {
            id: pathRow

            objectName: "wallpaperRow"
            columns: width >= 390 ? 2 : 1
            rowSpacing: Tones.space2
            columnSpacing: Tones.space3
            function choose(url) { root.backend.setWallpaper(url); }

            Label {
                objectName: "pathValue"
                // sólo el nombre del archivo; la ruta entera, en la información emergente
                text: root.value ? String(root.value).replace(/^.*\//, "") : "Built-in background"
                color: root.value ? Tones.textPrimary : Tones.textSecondary
                font.family: root.value ? Tones.mono : Tones.sans
                font.pixelSize: root.value ? Tones.monoSize : Tones.bodySize
                elide: Text.ElideMiddle
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                ToolTip.visible: pathHover.hovered && (truncated || text !== String(root.value || text))
                ToolTip.text: String(root.value || text)
                HoverHandler { id: pathHover }
            }
            RowLayout {
                spacing: Tones.space2
                ActionButton {
                    objectName: "choose"
                    text: "Choose image…"
                    glyph: "background"
                    Accessible.name: "Choose a wallpaper image"
                    onClicked: files.open()
                }
                ActionButton {
                    objectName: "remove"
                    visible: !!root.value
                    flat: true
                    destructive: true
                    text: "Remove"
                    Accessible.name: "Remove the wallpaper"
                    onClicked: root.backend.clearWallpaper()
                }
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

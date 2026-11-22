import QtQuick

/*
 * Botón de texto en píldora. `kind`: "normal" | "primary" | "danger".
 * Opcionalmente con icono a la izquierda y/o chevron a la derecha (selector).
 */
Item {
    id: root

    required property Style style
    property string text: ""
    property string icon: ""
    property bool chevron: false
    property string kind: "normal"
    property real minWidth: style.px(96)
    property real maxWidth: style.px(260)
    property real fontSize: style.px(13.5)

    signal clicked

    implicitHeight: style.px(32)
    implicitWidth: Math.min(maxWidth, Math.max(minWidth, row.implicitWidth + style.px(28)))
    activeFocusOnTab: true  // Qt ya salta lo invisible o deshabilitado
    opacity: enabled ? 1 : 0.4

    function activate() {
        if (root.enabled)
            root.clicked();
    }

    readonly property color baseFill: kind === "primary" ? style.accent
                                     : kind === "danger" ? Qt.rgba(style.error.r, style.error.g, style.error.b, 0.22)
                                     : style.field
    readonly property color labelColor: kind === "primary" ? "#0b0b0d" : kind === "danger" ? style.error : style.text

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: mouse.pressed ? Qt.darker(root.baseFill, 1.15)
             : mouse.containsMouse || root.activeFocus ? Qt.lighter(root.baseFill, root.kind === "primary" ? 1.08 : 1.3)
             : root.baseFill
        Behavior on color {
            ColorAnimation {
                duration: root.style.dur(120)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.style.px(3)
        radius: height / 2
        color: "transparent"
        border.width: Math.max(1, root.style.px(2))
        border.color: root.style.focusRing
        visible: root.activeFocus
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.style.px(7)
        width: Math.min(implicitWidth, root.width - root.style.px(24))

        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: root.style.px(15)
            color: root.labelColor
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: label
            text: root.text
            color: root.labelColor
            font.family: root.style.fontFamily
            font.pixelSize: root.fontSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            // Ancho fijo calculado (nunca un elide condicional): ver la trampa de Text en Sumi.
            width: Math.min(implicitWidth, root.maxWidth - root.style.px(28)
                            - (root.icon !== "" ? root.style.px(22) : 0) - (root.chevron ? root.style.px(20) : 0))
            anchors.verticalCenter: parent.verticalCenter
        }
        Icon {
            visible: root.chevron
            name: "chevron-down"
            size: root.style.px(13)
            color: root.style.textDim
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activate();
            event.accepted = true;
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: root.activate()
}

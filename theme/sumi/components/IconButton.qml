import QtQuick

/*
 * Botón circular con icono. `label` es su nombre accesible (no se pinta).
 * Se activa con clic, Intro, Enter o Espacio.
 */
Item {
    id: root

    required property Style style
    property string icon: ""
    property string label: ""
    property real size: style.px(34)
    property color tint: style.text
    property color fill: style.field
    property bool busy: false

    signal clicked

    implicitWidth: size
    implicitHeight: size
    activeFocusOnTab: true  // Qt ya salta lo invisible o deshabilitado
    opacity: enabled ? 1 : 0.4

    function activate() {
        if (root.enabled && !root.busy)
            root.clicked();
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: mouse.pressed ? Qt.darker(root.style.fieldHover, 1.1)
             : mouse.containsMouse || root.activeFocus ? root.style.fieldHover : root.fill
        Behavior on color {
            ColorAnimation {
                duration: root.style.dur(120)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.style.px(3)
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, root.style.px(2))
        border.color: root.style.focusRing
        visible: root.activeFocus
    }

    Icon {
        anchors.centerIn: parent
        visible: !root.busy
        name: root.icon
        size: root.size * 0.52
        color: root.tint
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.busy
        style: root.style
        size: root.size * 0.5
        color: root.tint
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
    Accessible.name: root.label
    Accessible.onPressAction: root.activate()
}

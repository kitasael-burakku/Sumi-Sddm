import QtQuick

/*
 * Campo de texto en píldora: icono a la izquierda, texto, y elementos opcionales a la derecha
 * (hijos por defecto: indicador de mayúsculas, botón de enviar…).
 *
 * Con `secret: true` es un campo de contraseña: eco con puntos, sin selección con el ratón, sin
 * copiar (TextInput no copia en modo contraseña), pistas de dato sensible para el método de
 * entrada, y `wipe()` asigna `text = ""`, que además vacía el historial de deshacer (`clear()`
 * lo dejaría disponible: comprobado en Qt 6.12, ver tests/qml/tst_greeter.qml).
 */
FocusScope {
    id: root

    required property Style style
    property string placeholder: ""
    property string icon: ""
    property bool secret: false
    property bool readOnly: false
    property alias input: field
    property alias text: field.text
    default property alias trailing: trail.data

    signal accepted
    signal escaped

    function wipe() {
        field.text = "";
    }

    implicitWidth: style.px(300)
    implicitHeight: style.px(42)
    activeFocusOnTab: false

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: height / 2
        color: hover.hovered && !field.activeFocus ? root.style.fieldHover : root.style.field
        border.width: field.activeFocus ? Math.max(1, root.style.px(1.5)) : 0
        border.color: root.style.focusRing
        Behavior on color {
            ColorAnimation {
                duration: root.style.dur(120)
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.IBeamCursor
    }

    Icon {
        id: lead
        visible: root.icon !== ""
        name: root.icon
        size: root.style.px(17)
        color: root.style.textDim
        anchors.left: parent.left
        anchors.leftMargin: root.style.px(14)
        anchors.verticalCenter: parent.verticalCenter
    }

    TextInput {
        id: field
        focus: true
        activeFocusOnTab: true
        anchors.left: lead.visible ? lead.right : parent.left
        anchors.leftMargin: lead.visible ? root.style.px(10) : root.style.px(16)
        anchors.right: trail.left
        anchors.rightMargin: root.style.px(8)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        readOnly: root.readOnly
        color: root.style.text
        selectionColor: root.style.accent
        selectedTextColor: "black"
        font.family: root.style.fontFamily
        font.pixelSize: root.style.px(15)
        font.letterSpacing: root.secret && text.length > 0 ? root.style.px(1.5) : 0
        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        passwordMaskDelay: 0
        selectByMouse: !root.secret
        maximumLength: 512
        inputMethodHints: root.secret
            ? (Qt.ImhSensitiveData | Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase)
            : (Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase)
        onAccepted: root.accepted()
        Keys.onEscapePressed: event => {
            root.escaped();
            event.accepted = true;
        }

        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholder
        Accessible.passwordEdit: root.secret

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: field.text.length === 0 && field.preeditText.length === 0
            text: root.placeholder
            color: root.style.textFaint
            font: field.font
            elide: Text.ElideRight
        }
    }

    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: root.style.px(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.style.px(6)
    }
}

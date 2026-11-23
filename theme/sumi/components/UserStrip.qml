pragma ComponentBehavior: Bound
import QtQuick

/*
 * Selector de usuarios (parte inferior). Avatares circulares con su nombre; el seleccionado va a
 * tamaño completo con anillo, el resto atenuado. Un mosaico «Other…» opcional pasa a la entrada
 * manual (índice −1).
 *
 * Teclado (cuando tiene el foco): ←/→ cambian de usuario, Intro/Espacio vuelven al campo de la
 * notch, y cualquier carácter imprimible se reenvía (`typed`) para escribir la contraseña sin
 * tener que volver antes al campo.
 */
FocusScope {
    id: root

    required property Style style
    property var model: null
    property int count: 0
    property int currentIndex: 0
    property bool manualEntry: false
    property bool showOther: false
    property bool locked: false

    signal selected(int index, bool fromKeyboard)
    signal activated
    signal typed(string text)

    activeFocusOnTab: true
    implicitHeight: row.implicitHeight
    implicitWidth: row.implicitWidth

    readonly property real tileWidth: style.px(Math.max(108, style.avatarSize + 44))

    function step(delta) {
        if (root.locked)
            return;
        // Orden: 0 … count-1, y −1 («Other») al final.
        const order = [];
        for (let i = 0; i < root.count; i++)
            order.push(i);
        if (root.showOther)
            order.push(-1);
        if (order.length === 0)
            return;
        const cur = root.manualEntry ? -1 : root.currentIndex;
        let pos = order.indexOf(cur);
        pos = pos < 0 ? 0 : (pos + delta + order.length) % order.length;
        root.selected(order[pos], true);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) {
            step(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            step(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activated();
            event.accepted = true;
        } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                   && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.typed(event.text);
            event.accepted = true;
        }
    }

    component Tile: Item {
        id: tile
        property string label: ""
        property string iconPath: ""
        property bool current: false
        property bool other: false
        signal picked

        width: root.tileWidth
        height: col.implicitHeight
        opacity: current ? 1 : (hover.containsMouse ? Math.min(1, root.style.userInactiveOpacity + 0.25) : root.style.userInactiveOpacity)
        Behavior on opacity {
            NumberAnimation {
                duration: root.style.dur(200)
            }
        }

        Column {
            id: col
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.style.px(10)

            Item {
                width: root.style.px(root.style.avatarSize) + root.style.px(12)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(1, root.style.px(2))
                    border.color: root.activeFocus ? root.style.focusRing : Qt.rgba(1, 1, 1, 0.85)
                    visible: tile.current
                }

                Avatar {
                    anchors.centerIn: parent
                    style: root.style
                    size: root.style.px(root.style.avatarSize)
                    visible: !tile.other
                    source: tile.iconPath
                    label: tile.label
                    scale: tile.current ? 1 : 0.88
                    Behavior on scale {
                        NumberAnimation {
                            duration: root.style.dur(220)
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: tile.other
                    width: root.style.px(root.style.avatarSize)
                    height: width
                    radius: width / 2
                    color: root.style.field
                    scale: tile.current ? 1 : 0.88
                    Icon {
                        anchors.centerIn: parent
                        name: "user"
                        size: parent.width * 0.46
                        color: root.style.textDim
                    }
                }
            }

            Text {
                visible: root.style.userNames
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, root.tileWidth)
                horizontalAlignment: Text.AlignHCenter
                text: tile.label
                elide: Text.ElideRight
                color: root.style.text
                font.family: root.style.fontFamily
                font.pixelSize: root.style.fs(14)
                font.weight: tile.current ? Font.DemiBold : Font.Medium
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.35)
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.locked
            onClicked: tile.picked()
        }

        Accessible.role: Accessible.RadioButton
        Accessible.name: tile.label
        Accessible.checked: tile.current
        Accessible.onPressAction: tile.picked()
    }

    Flickable {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(row.implicitWidth, root.width)
        height: row.implicitHeight
        contentWidth: row.implicitWidth
        contentHeight: row.implicitHeight
        interactive: row.implicitWidth > root.width
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row
            spacing: root.style.px(8)

            Repeater {
                model: root.model
                delegate: Tile {
                    required property int index
                    required property var model
                    objectName: "userTile" + index
                    label: (model.realName ?? "") !== "" ? model.realName : (model.name ?? "")
                    iconPath: model.icon ?? ""
                    current: !root.manualEntry && root.currentIndex === index
                    onPicked: root.selected(index, false)
                }
            }

            Tile {
                objectName: "userTileOther"
                visible: root.showOther
                other: true
                label: "Other…"
                current: root.manualEntry
                onPicked: root.selected(-1, false)
            }
        }
    }
}

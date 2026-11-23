import QtQuick

/* Doble de `keyboard` (KeyboardModel). */
QtObject {
    property bool capsLock: false
    property bool numLock: false
    property var layouts: []
    property int currentLayout: 0
    property bool enabled: false
}

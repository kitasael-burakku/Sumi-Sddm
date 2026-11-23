pragma Singleton

import QtQuick

/**
 * Los pocos colores propios del editor, según el tema del sistema. Todo lo demás sale de la paleta (Fusion la
 * toma del sistema: claro u oscuro). Cada tono tiene un contraste de al menos 4,5:1 con el fondo de la ventana
 * de Fusion en su modo (comprobado en tests/py/test_editor_ui.py).
 */
QtObject {
    readonly property SystemPalette palette: SystemPalette {}
    readonly property bool dark: palette.window.hslLightness < 0.5
    /** El fondo de ventana con el que se comparan estos tonos. */
    readonly property color window: palette.window

    /** Errores y avisos que impiden algo. */
    readonly property color error: dark ? "#ff8f87" : "#b3261e"
    /** «Todavía no aplicado» y su punto en la barra lateral. */
    readonly property color pending: dark ? "#f0a64b" : "#8a4b00"
}

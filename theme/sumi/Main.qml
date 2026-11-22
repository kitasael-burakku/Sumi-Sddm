import QtQuick
import "components"

/*
 * Punto de entrada para SDDM (MainScript). Sólo traduce el contexto del greeter a las propiedades
 * de Greeter.qml; toda la lógica vive allí y se prueba con objetos simulados.
 *
 * Propiedades de contexto de sddm-greeter-qt6 0.21 (verificadas en el binario): sddm, userModel,
 * sessionModel, screenModel, keyboard, config, primaryScreen. Se comprueban con `typeof` para que
 * el tema cargue también fuera de SDDM (qml, herramientas) sin errores de referencia.
 */
Item {
    id: root

    // SDDM ajusta la raíz al tamaño de cada pantalla; esto sólo vale fuera de SDDM.
    width: 1280
    height: 800

    Greeter {
        anchors.fill: parent
        focus: true
        users: typeof userModel !== "undefined" ? userModel : null
        sessions: typeof sessionModel !== "undefined" ? sessionModel : null
        backend: typeof sddm !== "undefined" ? sddm : null
        keyboardState: typeof keyboard !== "undefined" ? keyboard : null
        cfg: typeof config !== "undefined" ? config : null
        primary: typeof primaryScreen !== "undefined" ? !!primaryScreen : true
    }
}

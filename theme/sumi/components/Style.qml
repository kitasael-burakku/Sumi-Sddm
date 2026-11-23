import QtQuick
import "config.js" as Config

/*
 * Configuración tipada del tema.
 *
 * `source` es el `config` de SDDM (un QQmlPropertyMap con cadenas) o, en las pruebas, un objeto JS.
 * Tipos, defaults y rangos salen de schema.js (generado desde schema/config-schema.json) y la lectura
 * tolerante de config.js: nada aquí repite un valor por defecto, y un theme.conf.user roto nunca deja
 * la pantalla de inicio de sesión inutilizable.
 */
QtObject {
    id: s

    property var source: null
    property real screenWidth: 1920
    property real screenHeight: 1080
    /** true con el renderizador software de Qt Quick: sin MultiEffect (blur, máscaras, sombras). */
    property bool softwareRenderer: false
    /** Familia cargada por el FontLoader del tema ("" si no cargó). */
    property string bundledFont: ""

    /** Claves con un valor distinto del defecto (para el registro de arranque: sólo el número). */
    function customCount() {
        return Config.customCount(source);
    }
    /** Valor validado de una clave del esquema. */
    function value(key) {
        return Config.read(source, key);
    }
    /** Ruta aceptada → url (relativa al directorio del tema), o "" sin imagen. */
    function imageUrl(path) {
        if (path === "")
            return "";
        if (path.startsWith("file:///"))
            return path;
        if (path.startsWith("/"))
            return "file://" + path;
        return Qt.resolvedUrl("../" + path);
    }

    // ── Escala ──────────────────────────────────────────────────────────────────────────
    readonly property real uiScale: value("uiScale")
    readonly property real fontScale: value("fontScale")
    /**
     * Factor de píxeles: 1.0 en 1920×1080 lógicos (también en 1080×1920: se compara el lado largo con
     * 1920 y el corto con 1080, así una pantalla vertical no encoge la interfaz). Acotado a 0.6–3.
     */
    readonly property real unit: Math.max(0.6, Math.min(3.0, Math.min(Math.max(screenWidth, screenHeight) / 1920,
                                                                      Math.min(screenWidth, screenHeight) / 1080))) * uiScale
    function px(v) {
        return Math.round(v * unit);
    }
    /** Tamaño de texto (notch, botones, nombres): escala de pantalla × fontScale. */
    function fs(v) {
        return Math.round(v * unit * fontScale);
    }

    // ── Fondo ───────────────────────────────────────────────────────────────────────────
    readonly property url background: imageUrl(value("background"))
    readonly property string backgroundFill: value("backgroundFill")
    readonly property real blurRadius: value("blurRadius")
    readonly property real dimOpacity: value("dimOpacity")
    readonly property color backgroundColor: value("backgroundColor")

    // ── Colores ─────────────────────────────────────────────────────────────────────────
    readonly property color accent: value("accentColor")
    readonly property color text: value("textColor")
    readonly property color textDim: Qt.rgba(text.r, text.g, text.b, 0.62)
    readonly property color textFaint: Qt.rgba(text.r, text.g, text.b, 0.38)
    readonly property color error: value("errorColor")
    readonly property color notch: value("notchColor")
    readonly property color field: value("fieldColor")
    readonly property color fieldHover: Qt.lighter(field, 1.35)
    readonly property color focusRing: Qt.rgba(accent.r, accent.g, accent.b, 0.9)

    // ── Tipografía ──────────────────────────────────────────────────────────────────────
    readonly property string fontFamily: {
        const f = value("fontFamily");
        return f !== "" ? f : (bundledFont !== "" ? bundledFont : "Inter");
    }

    // ── Notch ───────────────────────────────────────────────────────────────────────────
    readonly property int notchCompactWidth: value("notchCompactWidth")
    readonly property int notchCompactHeight: value("notchCompactHeight")
    readonly property int notchExpandedWidth: value("notchExpandedWidth")
    readonly property int notchRadius: value("notchRadius")
    readonly property int notchShoulder: value("notchShoulder")
    readonly property bool notchStartExpanded: value("notchStartExpanded")
    /** 0 = nunca; si no, 5–600 s. */
    readonly property int notchIdleCollapse: value("notchIdleCollapse")

    // ── Reloj ───────────────────────────────────────────────────────────────────────────
    readonly property string clockPosition: value("clockPosition")
    readonly property bool clock24h: value("clockFormat") === "24h"
    readonly property bool clockSeconds: value("clockSeconds")
    readonly property real clockScale: value("clockScale")
    readonly property int clockWeight: {
        const w = value("clockWeight");
        return w === "thin" ? Font.Thin : w === "regular" ? Font.Normal : w === "medium" ? Font.Medium : Font.Light;
    }
    readonly property int clockOffsetX: value("clockOffsetX")
    readonly property int clockOffsetY: value("clockOffsetY")
    readonly property string dateFormat: value("dateFormat")

    // ── Usuarios ────────────────────────────────────────────────────────────────────────
    readonly property string userStrip: value("userStrip")
    readonly property int avatarSize: value("avatarSize")
    readonly property bool userNames: value("userNames")
    readonly property real userInactiveOpacity: value("userInactiveOpacity")
    readonly property int userStripMargin: value("userStripMargin")
    readonly property string manualUser: value("manualUser")

    // ── Energía ─────────────────────────────────────────────────────────────────────────
    readonly property bool showShutdown: value("showShutdown")
    readonly property bool showRestart: value("showRestart")
    readonly property bool showSuspend: value("showSuspend")

    // ── Movimiento ──────────────────────────────────────────────────────────────────────
    readonly property bool animate: value("animations")
    readonly property real animationSpeed: value("animationSpeed")
    /** Duración efectiva: 0 con las animaciones apagadas. */
    function dur(ms) {
        return animate ? Math.round(ms / animationSpeed) : 0;
    }
    /** Curva suave tipo «ease-out» larga, para cambios de tamaño de la notch. */
    readonly property var curve: [0.32, 0.72, 0.0, 1.0, 1.0, 1.0]

    // ── Comportamiento ──────────────────────────────────────────────────────────────────
    readonly property string multiMonitor: value("multiMonitor")
    readonly property int authTimeout: value("authTimeout")
}

import QtQuick

/*
 * Configuración tipada del tema.
 *
 * `source` es el `config` de SDDM (un QQmlPropertyMap con cadenas) o, en las pruebas, un objeto JS.
 * Cada clave tiene aquí su valor por defecto (los mismos que theme.conf) y se valida: un valor
 * que no se entiende vuelve al defecto y un número fuera de rango se acota. Nada lanza: un
 * theme.conf.user roto nunca debe dejar la pantalla de inicio de sesión inutilizable.
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

    // ── Lectura defensiva ───────────────────────────────────────────────────────────────
    function raw(key) {
        if (!source)
            return undefined;
        let v;
        try {
            v = source[key];
        } catch (e) {
            return undefined;
        }
        if (v === undefined || v === null)
            return undefined;
        // QSettings convierte «a, b» en lista: se vuelve a unir.
        if (typeof v === "object" && v.length !== undefined)
            v = Array.prototype.join.call(v, ", ");
        return String(v).trim();
    }
    function str(key, def) {
        const v = raw(key);
        return v === undefined || v === "" ? def : v;
    }
    function num(key, def, lo, hi) {
        const v = raw(key);
        if (v === undefined || v === "")
            return def;
        const n = Number(v);
        if (!isFinite(n))
            return def;
        return Math.min(hi, Math.max(lo, n));
    }
    function integer(key, def, lo, hi) {
        return Math.round(num(key, def, lo, hi));
    }
    function flag(key, def) {
        const v = raw(key);
        if (v === undefined)
            return def;
        const l = v.toLowerCase();
        if (l === "true" || l === "1" || l === "yes" || l === "on")
            return true;
        if (l === "false" || l === "0" || l === "no" || l === "off")
            return false;
        return def;
    }
    function choice(key, def, allowed) {
        const v = raw(key);
        if (v === undefined)
            return def;
        const l = v.toLowerCase();
        return allowed.indexOf(l) >= 0 ? l : def;
    }
    function color(key, def) {
        const v = raw(key);
        return v !== undefined && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) ? v : def;
    }
    /** Ruta de imagen → url, o "" si no es aceptable (vacía, con «..», esquema remoto). */
    function imageUrl(key) {
        const v = raw(key);
        if (v === undefined || v === "")
            return "";
        if (v.indexOf("..") >= 0 || v.indexOf("\n") >= 0)
            return "";
        if (v.startsWith("file:///"))
            return v;
        if (v.indexOf(":") >= 0)
            return "";                       // http:, qrc:, image: … no se aceptan
        if (v.startsWith("/"))
            return "file://" + v;
        return Qt.resolvedUrl("../" + v);    // relativo al directorio del tema
    }

    // ── Escala ──────────────────────────────────────────────────────────────────────────
    readonly property real uiScale: num("uiScale", 1.0, 0.5, 2.0)
    /**
     * Factor de píxeles: 1.0 en 1920×1080 lógicos (también en 1080×1920: se compara el lado largo con
     * 1920 y el corto con 1080, así una pantalla vertical no encoge la interfaz). Acotado a 0.6–3.
     */
    readonly property real unit: Math.max(0.6, Math.min(3.0, Math.min(Math.max(screenWidth, screenHeight) / 1920,
                                                                      Math.min(screenWidth, screenHeight) / 1080))) * uiScale
    function px(v) {
        return Math.round(v * unit);
    }

    // ── Fondo ───────────────────────────────────────────────────────────────────────────
    readonly property url background: imageUrl("background")
    readonly property string backgroundFill: choice("backgroundFill", "crop", ["crop", "fit", "stretch"])
    readonly property real blurRadius: num("blurRadius", 0, 0, 100)
    readonly property real dimOpacity: num("dimOpacity", 0.2, 0, 0.85)
    readonly property color backgroundColor: color("backgroundColor", "#0c0d10")

    // ── Colores ─────────────────────────────────────────────────────────────────────────
    readonly property color accent: color("accentColor", "#a9bdff")
    readonly property color text: color("textColor", "#f3f3f5")
    readonly property color textDim: Qt.rgba(text.r, text.g, text.b, 0.62)
    readonly property color textFaint: Qt.rgba(text.r, text.g, text.b, 0.38)
    readonly property color error: color("errorColor", "#ff8f87")
    readonly property color notch: color("notchColor", "#000000")
    readonly property color field: color("fieldColor", "#1c1c1f")
    readonly property color fieldHover: Qt.lighter(field, 1.35)
    readonly property color focusRing: Qt.rgba(accent.r, accent.g, accent.b, 0.9)

    // ── Tipografía ──────────────────────────────────────────────────────────────────────
    readonly property string fontFamily: str("fontFamily", bundledFont !== "" ? bundledFont : "Inter")

    // ── Notch ───────────────────────────────────────────────────────────────────────────
    readonly property int notchCompactWidth: integer("notchCompactWidth", 200, 120, 480)
    readonly property int notchCompactHeight: integer("notchCompactHeight", 34, 24, 64)
    readonly property int notchExpandedWidth: integer("notchExpandedWidth", 440, 340, 720)
    readonly property int notchRadius: integer("notchRadius", 22, 4, 48)
    readonly property int notchShoulder: integer("notchShoulder", 12, 0, 24)
    readonly property bool notchStartExpanded: flag("notchStartExpanded", false)
    /** 0 = nunca; si no, 5–600 s. */
    readonly property int notchIdleCollapse: {
        const n = integer("notchIdleCollapse", 60, 0, 600);
        return n === 0 ? 0 : Math.max(5, n);
    }

    // ── Reloj ───────────────────────────────────────────────────────────────────────────
    readonly property string clockPosition: choice("clockPosition", "center", ["center", "top-left", "top-right", "bottom-left", "bottom-right"])
    readonly property bool clock24h: choice("clockFormat", "24h", ["24h", "12h"]) === "24h"
    readonly property bool clockSeconds: flag("clockSeconds", false)
    readonly property real clockScale: num("clockScale", 1.0, 0.5, 2.0)
    readonly property string dateFormat: str("dateFormat", "dddd, d MMMM")

    // ── Usuarios ────────────────────────────────────────────────────────────────────────
    readonly property string userStrip: choice("userStrip", "always", ["always", "auto", "never"])
    readonly property int avatarSize: integer("avatarSize", 64, 40, 120)
    readonly property string manualUser: choice("manualUser", "auto", ["auto", "always", "never"])

    // ── Energía ─────────────────────────────────────────────────────────────────────────
    readonly property bool showShutdown: flag("showShutdown", true)
    readonly property bool showRestart: flag("showRestart", true)
    readonly property bool showSuspend: flag("showSuspend", false)

    // ── Movimiento ──────────────────────────────────────────────────────────────────────
    readonly property bool animate: flag("animations", true)
    readonly property real animationSpeed: num("animationSpeed", 1.0, 0.25, 3.0)
    /** Duración efectiva: 0 con las animaciones apagadas. */
    function dur(ms) {
        return animate ? Math.round(ms / animationSpeed) : 0;
    }
    /** Curva suave tipo «ease-out» larga, para cambios de tamaño de la notch. */
    readonly property var curve: [0.32, 0.72, 0.0, 1.0, 1.0, 1.0]

    // ── Varios ──────────────────────────────────────────────────────────────────────────
    readonly property string multiMonitor: choice("multiMonitor", "all", ["all", "primary"])
    readonly property int authTimeout: integer("authTimeout", 30, 5, 120)
}

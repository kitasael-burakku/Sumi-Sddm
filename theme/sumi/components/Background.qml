pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

/*
 * Fondo en capas:
 *   1. color base
 *   2. «tinta»: aguadas radiales generadas en QML (el fondo por defecto; no necesita archivos)
 *   3. wallpaper opcional (`background`), con desenfoque opcional; si falta o falla, no se ve
 *      y queda la tinta
 *   4. oscurecimiento (`dimOpacity`) y una sombra suave desde el borde superior, que funde la
 *      notch con el borde de la pantalla
 */
Item {
    id: root

    required property Style style

    /** true cuando el wallpaper configurado cargó; false si no hay o falló. */
    readonly property bool wallpaperReady: wall.status === Image.Ready
    readonly property bool wallpaperFailed: style.background.toString() !== "" && wall.status === Image.Error
    /** Sólo depende de la configuración (no del estado de carga): `sourceSize` la usa y cambiarla recarga la imagen. */
    readonly property bool wantBlur: style.blurRadius > 0 && !style.softwareRenderer
    readonly property bool blurActive: wallpaperReady && wantBlur
    readonly property real decodeDivisor: wantBlur ? 1 + style.blurRadius / 40 : 1

    Rectangle {
        anchors.fill: parent
        color: root.style.backgroundColor
    }

    // ── 2. Tinta ────────────────────────────────────────────────────────────────────────
    Shape {
        id: ink
        anchors.fill: parent
        visible: !root.wallpaperReady

        component Wash: ShapePath {
            id: wash
            property real cx: 0
            property real cy: 0
            property real rad: 100
            property color tint: "white"
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: RadialGradient {
                centerX: wash.cx
                centerY: wash.cy
                centerRadius: wash.rad
                focalX: wash.cx
                focalY: wash.cy
                GradientStop {
                    position: 0.0
                    color: wash.tint
                }
                GradientStop {
                    position: 0.55
                    color: Qt.rgba(wash.tint.r, wash.tint.g, wash.tint.b, wash.tint.a * 0.35)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
            startX: 0
            startY: 0
            PathLine {
                x: ink.width
                y: 0
            }
            PathLine {
                x: ink.width
                y: ink.height
            }
            PathLine {
                x: 0
                y: ink.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }

        Wash {
            cx: ink.width * 0.18
            cy: ink.height * 0.08
            rad: Math.max(ink.width, ink.height) * 0.62
            tint: Qt.rgba(0.20, 0.25, 0.40, 0.55)
        }
        Wash {
            cx: ink.width * 0.86
            cy: ink.height * 0.92
            rad: Math.max(ink.width, ink.height) * 0.58
            tint: Qt.rgba(0.27, 0.19, 0.27, 0.50)
        }
        Wash {
            cx: ink.width * 0.55
            cy: ink.height * 0.62
            rad: Math.max(ink.width, ink.height) * 0.34
            tint: Qt.rgba(0.16, 0.20, 0.24, 0.35)
        }
    }

    // ── 3. Wallpaper ────────────────────────────────────────────────────────────────────
    Image {
        id: wall
        anchors.fill: parent
        source: root.style.background
        asynchronous: true
        cache: false
        smooth: true
        visible: root.wallpaperReady && !root.blurActive
        fillMode: root.style.backgroundFill === "fit" ? Image.PreserveAspectFit
                : root.style.backgroundFill === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
        // Decodificar al tamaño de pantalla (más pequeño con desenfoque fuerte): memoria acotada
        // en 4K y desenfoque más amplio de lo que permite MultiEffect por sí solo.
        sourceSize.width: Math.max(1, Math.round(root.width / root.decodeDivisor))
        sourceSize.height: Math.max(1, Math.round(root.height / root.decodeDivisor))
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("sumi-sddm: background image could not be loaded; using the built-in background");
        }
    }

    MultiEffect {
        anchors.fill: wall
        source: wall
        visible: root.blurActive
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: Math.min(1, 0.25 + root.style.blurRadius / 100)
    }

    // ── 4. Oscurecimiento y sombra superior ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.style.dimOpacity
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height * 0.22
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(0, 0, 0, 0.42)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }
}

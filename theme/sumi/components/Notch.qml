import QtQuick
import QtQuick.Effects

/*
 * Contenedor de la notch: la silueta pegada al borde superior, una sombra discreta y el cuerpo
 * (recortado) donde el Greeter coloca sus páginas. El tamaño del cuerpo se anima.
 *
 * La sombra sale de una COPIA oculta de la silueta: si MultiEffect no se puede dibujar (GPU rara,
 * renderizador software) sólo se pierde la sombra; la notch real y su contenido siguen visibles.
 */
Item {
    id: root

    required property Style style
    /** Tamaño objetivo del cuerpo (sin los hombros). */
    property real bodyWidth: style.px(style.notchCompactWidth)
    property real bodyHeight: style.px(style.notchCompactHeight)
    default property alias content: body.data
    readonly property alias body: body

    readonly property real shoulder: style.px(style.notchShoulder)

    width: bodyWidth + 2 * shoulder
    height: bodyHeight

    Behavior on bodyWidth {
        NumberAnimation {
            duration: root.style.dur(460)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.style.curve
        }
    }
    Behavior on bodyHeight {
        NumberAnimation {
            duration: root.style.dur(460)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.style.curve
        }
    }

    NotchShape {
        id: shadowSource
        anchors.fill: parent
        visible: false
        radius: root.style.px(root.style.notchRadius)
        shoulder: root.shoulder
        color: "black"
    }

    MultiEffect {
        anchors.fill: shadowSource
        source: shadowSource
        visible: !root.style.softwareRenderer
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "black"
        shadowOpacity: 0.55
        shadowBlur: 0.9
        shadowVerticalOffset: root.style.px(6)
    }

    NotchShape {
        anchors.fill: parent
        radius: root.style.px(root.style.notchRadius)
        shoulder: root.shoulder
        color: root.style.notch
    }

    Item {
        id: body
        x: root.shoulder
        width: root.bodyWidth
        height: root.bodyHeight
        clip: true
    }
}

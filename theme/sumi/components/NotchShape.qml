import QtQuick
import QtQuick.Shapes

/*
 * La silueta de la notch: borde superior recto pegado al de la pantalla, «hombros» cóncavos que la
 * funden con ese borde y esquinas inferiores redondeadas.
 *
 *   0 ─╮                          ╭─ width
 *      │         cuerpo           │         ← `shoulder` a cada lado
 *      ╰──────────────────────────╯
 *
 * `width` incluye los dos hombros; el cuerpo útil mide width − 2·shoulder.
 */
Shape {
    id: shape

    property real radius: 22
    property real shoulder: 12
    property color color: "black"

    readonly property real sh: Math.max(0, Math.min(shoulder, width / 4, height / 2))
    readonly property real r: Math.max(0, Math.min(radius, height - sh, (width - 2 * sh) / 2))

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: shape.color
        strokeColor: "transparent"
        strokeWidth: 0
        startX: 0
        startY: 0

        PathQuad {
            x: shape.sh
            y: shape.sh
            controlX: shape.sh
            controlY: 0
        }
        PathLine {
            x: shape.sh
            y: shape.height - shape.r
        }
        PathArc {
            x: shape.sh + shape.r
            y: shape.height
            radiusX: shape.r
            radiusY: shape.r
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: shape.width - shape.sh - shape.r
            y: shape.height
        }
        PathArc {
            x: shape.width - shape.sh
            y: shape.height - shape.r
            radiusX: shape.r
            radiusY: shape.r
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: shape.width - shape.sh
            y: shape.sh
        }
        PathQuad {
            x: shape.width
            y: 0
            controlX: shape.width - shape.sh
            controlY: 0
        }
        PathLine {
            x: 0
            y: 0
        }
    }
}

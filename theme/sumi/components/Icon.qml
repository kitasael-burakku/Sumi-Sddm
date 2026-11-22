import QtQuick
import QtQuick.Shapes

/*
 * Iconos de trazo propios (rejilla de 24 unidades, trazo redondeado). Se dibujan con Shapes:
 * vectoriales, del color que se pida y sin MultiEffect, así que también funcionan con el
 * renderizador software.
 */
Item {
    id: root

    property string name: ""
    property color color: "white"
    property real size: 20
    property real stroke: 1.8

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
            "power": "M12 3.5v7.5 M6.6 6.4a7.6 7.6 0 1 0 10.8 0",
            "restart": "M19.6 12a7.6 7.6 0 1 1-2.2-5.4 M19.6 4.2v4.4h-4.4",
            "moon": "M19.5 14.6A7.8 7.8 0 1 1 9.4 4.5a6.2 6.2 0 0 0 10.1 10.1z",
            "chevron-down": "M6.5 9.5l5.5 5.5 5.5-5.5",
            "arrow-right": "M5 12h13.5 M13 6.5l5.5 5.5-5.5 5.5",
            "lock": "M7.2 10.8h9.6a1.2 1.2 0 0 1 1.2 1.2v6.6a1.2 1.2 0 0 1-1.2 1.2H7.2A1.2 1.2 0 0 1 6 18.6V12a1.2 1.2 0 0 1 1.2-1.2z M8.6 10.8V8a3.4 3.4 0 0 1 6.8 0v2.8",
            "caps": "M12 4.5l7 7h-3.8v4.5H8.8v-4.5H5z M8.8 19.5h6.4",
            "check": "M5.5 12.5l4.2 4.2L18.5 7.8",
            "user": "M12 12a3.8 3.8 0 1 0 0-7.6 3.8 3.8 0 0 0 0 7.6z M4.8 19.6a7.2 7.2 0 0 1 14.4 0",
            "alert": "M12 3.8a8.2 8.2 0 1 0 0 16.4 8.2 8.2 0 0 0 0-16.4z M12 8v4.6 M12 15.9v.1",
            "back": "M14.5 6.5L9 12l5.5 5.5",
            "monitor": "M4.5 5.5h15a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1z M9 20h6 M12 16.5V20"
        })

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: root.paths[root.name] || ""
            }
        }
    }
}

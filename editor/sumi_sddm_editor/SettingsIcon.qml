import QtQuick
import QtQuick.Shapes

Item {
    id: root

    required property string name
    property color color: Tones.muted
    property real size: 16

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        background: "M3 5h18v14H3z M3 16l5-5 4 4 3-3 6 6 M15 8h.1",
        colors: "M12 3a9 9 0 1 0 0 18h1a2.3 2.3 0 0 0 1.5-4 1.3 1.3 0 0 1 1-2.3h2A3.5 3.5 0 0 0 21 11c0-4.4-4-8-9-8z M7 11h.1 M9 7h.1 M14 7h.1 M17 10h.1",
        typography: "M5 19l6-14 6 14 M7.5 14h7 M17 19h4",
        notch: "M3 6h18v12H3z M7 6v3a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V6",
        clock: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z M12 7v5l3 2",
        users: "M15 8a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0z M18 20H5v-1a6.5 6.5 0 0 1 13 0z",
        power: "M12 3v8 M6 6a8.5 8.5 0 1 0 12 0",
        motion: "M3 8h11 M6 12h11 M3 16h11 M16 6l6 6-6 6",
        behaviour: "M5 5v14 M12 5v14 M19 5v14 M3 9h4 M10 15h4 M17 10h4",
        system: "M3 5h18v12H3z M8 21h8 M12 17v4",
        search: "M16 10a6 6 0 1 1-12 0 6 6 0 0 1 12 0z M14.5 14.5L20 20",
        reset: "M5 10a7.5 7.5 0 1 1 1 8 M5 5v5h5",
        expand: "M14 4h6v6 M20 4l-6 6 M10 20H4v-6 M4 20l6-6",
        collapse: "M20 5l-6 6 M14 5v6h6 M4 19l6-6 M4 13h6v6",
        close: "M6 6l12 12 M18 6L6 18",
        chevron: "M7 9l5 5 5-5"
    })

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.7
            fillColor: Tones.unfilled
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[root.name] || root.paths.behaviour }
        }
    }
}

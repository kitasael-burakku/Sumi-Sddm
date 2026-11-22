import QtQuick
import QtQuick.Shapes

/* Arco giratorio para «autenticando». Con las animaciones apagadas queda quieto. */
Item {
    id: root

    required property Style style
    property real size: 18
    property color color: "white"

    implicitWidth: size
    implicitHeight: size

    Shape {
        id: arc
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: Math.max(1.5, root.size * 0.11)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.size / 2 - root.size * 0.08
                radiusY: root.size / 2 - root.size * 0.08
                startAngle: -90
                sweepAngle: 270
            }
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: root.visible && root.style.animate
        }
    }

    Accessible.role: Accessible.Indicator
    Accessible.name: "Working"
}

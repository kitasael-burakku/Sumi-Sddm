import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// Square checkbox recipe: 18 × 18, visible control border, frost fill with a dark check when checked.
CheckBox {
    id: root

    hoverEnabled: true
    spacing: Tones.space2
    padding: Tones.space1
    implicitHeight: Tones.controlHeight
    font.pixelSize: Tones.bodySize

    indicator: Rectangle {
        implicitWidth: Tones.checkSize
        implicitHeight: Tones.checkSize
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: Tones.cornerRadius
        color: !root.enabled ? Tones.disabledSurface
            : root.checked ? (root.down ? Tones.accentPressed : root.hovered ? Tones.accentHover : Tones.accent)
            : root.hovered ? Tones.hoverSurface : Tones.controlSurface
        border.width: Tones.stroke
        border.color: !root.enabled ? Tones.borderSubtle
            : root.checked ? Tones.accent : root.hovered ? Tones.borderHover : Tones.controlBorder
        Behavior on color { ColorAnimation { duration: Tones.hoverDuration; easing.type: Tones.easing } }

        Shape {
            anchors.fill: parent
            visible: root.checked
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: root.enabled ? Tones.textOnAccent : Tones.textDisabled
                strokeWidth: 2
                fillColor: Tones.transparent
                capStyle: ShapePath.SquareCap
                joinStyle: ShapePath.MiterJoin
                startX: 4; startY: 9.5
                PathLine { x: 7.5; y: 13 }
                PathLine { x: 14; y: 5.5 }
            }
        }
        FocusRing { shown: root.visualFocus }
    }
    contentItem: Label {
        leftPadding: root.indicator.width + root.spacing
        text: root.text
        font: root.font
        color: root.enabled ? Tones.textPrimary : Tones.textDisabled
        verticalAlignment: Text.AlignVCenter
    }
}

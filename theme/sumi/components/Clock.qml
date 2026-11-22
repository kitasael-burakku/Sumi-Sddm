import QtQuick

/*
 * Hora y fecha. Independiente de la notch: el Greeter sólo decide dónde va.
 * `align` (Text.AlignLeft/HCenter/Right) se ajusta a la esquina elegida.
 */
Column {
    id: root

    required property Style style
    property int align: Text.AlignHCenter
    /** Hora mostrada; las pruebas pueden fijarla y parar el temporizador. */
    property date now: new Date()
    property bool running: true

    spacing: style.px(2) * style.clockScale

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property string timeText: {
        if (style.clock24h)
            return Qt.formatTime(now, style.clockSeconds ? "HH:mm:ss" : "HH:mm");
        return Qt.formatTime(now, style.clockSeconds ? "h:mm:ss" : "h:mm");
    }
    readonly property string meridiem: style.clock24h ? "" : Qt.formatTime(now, "AP")
    readonly property string dateText: now.toLocaleDateString(Qt.locale(), style.dateFormat)

    Item {
        width: root.width
        height: timeLabel.implicitHeight
        implicitWidth: timeLabel.implicitWidth + (ap.visible ? ap.implicitWidth + ap.anchors.leftMargin : 0)

        Text {
            id: timeLabel
            x: root.align === Text.AlignLeft ? 0
               : root.align === Text.AlignRight ? parent.width - parent.implicitWidth
               : (parent.width - parent.implicitWidth) / 2
            text: root.timeText
            color: root.style.text
            font.family: root.style.fontFamily
            font.pixelSize: root.style.px(104) * root.style.clockScale
            font.weight: Font.Light
            font.letterSpacing: -root.style.px(2) * root.style.clockScale
            font.features: { "tnum": 1 }
            renderType: Text.QtRendering
            Accessible.role: Accessible.StaticText
            Accessible.name: root.timeText + (root.meridiem ? " " + root.meridiem : "")
        }
        Text {
            id: ap
            visible: text !== ""
            anchors.left: timeLabel.right
            anchors.leftMargin: root.style.px(8) * root.style.clockScale
            anchors.baseline: timeLabel.baseline
            text: root.meridiem
            color: root.style.textDim
            font.family: root.style.fontFamily
            font.pixelSize: root.style.px(26) * root.style.clockScale
            font.weight: Font.Medium
        }
    }

    Text {
        width: root.width
        horizontalAlignment: root.align
        text: root.dateText
        color: root.style.textDim
        font.family: root.style.fontFamily
        font.pixelSize: root.style.px(21) * root.style.clockScale
        font.weight: Font.Medium
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
}

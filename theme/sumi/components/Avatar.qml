import QtQuick
import QtQuick.Effects

/*
 * Avatar circular. Muestra iniciales si no hay imagen, si la imagen es la genérica de SDDM
 * (`…/faces/.face.icon`) o si falla al cargar. Con el renderizador software (sin MultiEffect)
 * la imagen se recorta en un cuadrado redondeado en vez de un círculo.
 */
Item {
    id: root

    required property Style style
    property string source: ""
    /** Nombre visible, para las iniciales y el color de reserva. */
    property string label: ""
    property real size: 64

    implicitWidth: size
    implicitHeight: size

    readonly property bool genericFace: source === "" || /\/faces\/\.face\.icon$/.test(source)
    readonly property bool showingImage: !genericFace && img.status === Image.Ready

    readonly property string initials: {
        const parts = label.trim().split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 0)
            return "?";
        const first = parts[0].charAt(0);
        const second = parts.length > 1 ? parts[parts.length - 1].charAt(0) : "";
        return String(first + second).toUpperCase();
    }
    /** Tono estable por nombre, apagado para no competir con el acento. */
    readonly property color fallbackColor: {
        let h = 0;
        for (let i = 0; i < label.length; i++)
            h = (h * 31 + label.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.22, 0.34, 1);
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: !root.showingImage
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.lighter(root.fallbackColor, 1.25)
            }
            GradientStop {
                position: 1
                color: root.fallbackColor
            }
        }
        Text {
            anchors.centerIn: parent
            text: root.initials
            color: "white"
            opacity: 0.92
            font.family: root.style.fontFamily
            font.pixelSize: root.size * 0.36
            font.weight: Font.DemiBold
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.genericFace ? "" : (root.source.startsWith("/") ? "file://" + root.source : root.source)
        sourceSize.width: Math.ceil(root.size * 2)
        sourceSize.height: Math.ceil(root.size * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
        layer.enabled: root.showingImage && !root.style.softwareRenderer
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
        layer.smooth: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.showingImage && !root.style.softwareRenderer
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // Reserva sin efectos: cuadrado redondeado.
    Rectangle {
        anchors.fill: parent
        visible: root.showingImage && root.style.softwareRenderer
        radius: width * 0.22
        clip: true
        color: "transparent"
        Image {
            anchors.fill: parent
            source: root.style.softwareRenderer ? img.source : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: img.sourceSize
        }
    }
}

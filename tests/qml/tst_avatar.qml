pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../../theme/sumi/components"

/*
 * El avatar con imagen es un CÍRCULO con los dos renderizadores: MultiEffect con RHI y un Canvas con el software
 * (antes, `clip` de un Rectangle dejaba un cuadrado que tapaba el anillo). Fixture: 300×200, verde con un disco
 * claro en el centro; «cover» recorta los lados. Detrás, un fondo rojo: en la esquina debe verse rojo.
 */
TestCase {
    id: tc
    name: "Avatar"
    when: windowShown
    visible: true
    width: 200
    height: 200

    Component {
        id: avatarC
        Item {
            id: box
            width: 120
            height: 120
            property alias avatar: av
            // fondo rojo: donde el avatar no pinta (fuera del círculo) se ve rojo
            Rectangle {
                anchors.fill: parent
                color: "#ff0000"
            }
            Style {
                id: st
                source: ({})
                softwareRenderer: box.GraphicsInfo.api === GraphicsInfo.Software
            }
            Avatar {
                id: av
                anchors.fill: parent
                style: st
                label: "Test User"
                source: Qt.resolvedUrl("../fixtures/avatar-wide.png").toString().replace("file://", "")
            }
        }
    }

    function test_round_image_on_this_renderer() {
        const box = createTemporaryObject(avatarC, tc);
        tryVerify(() => box.avatar.showingImage, 5000, "la imagen carga");
        wait(400);    // el Canvas (software) carga su propia copia
        const img = grabImage(box);
        const center = img.pixel(60, 60), corner = img.pixel(4, 4), side = img.pixel(4, 60);
        verify(center.a > 0.95 && center.r > 0.9, "centro: el disco claro (" + center + ")");
        verify(side.g > 0.5 && side.r < 0.35, "borde izquierdo a media altura: verde de la imagen (" + side + ")");
        verify(corner.r > 0.9 && corner.g < 0.15, "esquina: se ve el fondo rojo, recortado en círculo (" + corner + ")");
    }

    function test_initials_without_image() {
        const box = createTemporaryObject(avatarC, tc);
        box.avatar.source = "";
        verify(!box.avatar.showingImage);
        compare(box.avatar.initials, "TU");
    }
}

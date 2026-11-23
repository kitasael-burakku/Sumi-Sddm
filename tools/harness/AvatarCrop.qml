import QtQuick

/*
 * Recorte cuadrado de un avatar (sumi-sddm avatar set): la imagen, centrada y recortada a SIZE×SIZE, guardada en
 * PNG. Offscreen, sin ventana visible. Argumentos: --src=RUTA --out=RUTA.png --size=N
 * Escribe «avatar: saved» o «avatar: error …» y sale.
 */
Window {
    id: win

    readonly property var opts: {
        const o = { src: "", out: "", size: 512 };
        for (const a of Qt.application.arguments) {
            const m = /^--([a-z]+)=(.*)$/.exec(a);
            if (m)
                o[m[1]] = m[1] === "size" ? Number(m[2]) : m[2];
        }
        return o;
    }

    width: opts.size
    height: opts.size
    visible: true
    color: "transparent"

    Image {
        id: img
        anchors.fill: parent
        source: win.opts.src === "" ? "" : "file://" + win.opts.src
        sourceSize.width: win.opts.size * 2
        sourceSize.height: win.opts.size * 2
        fillMode: Image.PreserveAspectCrop
        smooth: true
        mipmap: true
        onStatusChanged: {
            if (status === Image.Error) {
                console.log("avatar: error no se pudo leer la imagen");
                Qt.exit(1);
            } else if (status === Image.Ready) {
                saveTimer.start();
            }
        }
    }
    Timer {
        id: saveTimer
        interval: 50
        onTriggered: {
            if (!img.grabToImage(r => {
                if (r.saveToFile(win.opts.out)) {
                    console.log("avatar: saved");
                    Qt.exit(0);
                } else {
                    console.log("avatar: error no se pudo guardar");
                    Qt.exit(1);
                }
            })) {
                console.log("avatar: error no se pudo capturar");
                Qt.exit(1);
            }
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: { console.log("avatar: error tiempo agotado"); Qt.exit(1); }
    }
}

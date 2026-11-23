pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "components"
import "surfaces" as Surfaces
import "services" as Svc
import "theme"
import "sddm-checks.js" as Checks

/*
 * Banco de Settings → Login screen (Sumi SDDM). Se copia junto a una COPIA del árbol de Sumi Shell y se ejecuta con
 * `qs -p` en un HOME privado y offscreen (bench/review.py). Escribe REVIEW {json} al terminar.
 */
ShellRoot {
    Window {
        id: win
        visible: true; width: 1100; height: 760
        readonly property string scenario: Quickshell.env("SDDM_REVIEW_SCENARIO")
        readonly property string out: Quickshell.env("SDDM_REVIEW_OUT")
        readonly property real factor: 0.8
        readonly property string home: Quickshell.env("HOME")
        property var steps: []
        property var checks: []
        property int next: 0
        property double stepStart: 0
        property bool finished: false
        property int writingShots: 0
        property alias page: page
        property alias pointer: pointer
        property var external: null          // resultado de la última orden externa (run)
        TestEvent { id: pointer }

        function assertThat(ok, label) {
            if (!ok) throw new Error(label);
            checks.push(label);
        }
        function key(code, modifiers) {
            const e = { key: code, modifiers: modifiers || 0, text: "", accepted: false, isAutoRepeat: false };
            page.keyPressed(e);
            return e.accepted;
        }
        function descendants(item, predicate, found) {
            if (predicate(item)) found.push(item);
            for (const child of item.children || []) descendants(child, predicate, found);
            return found;
        }
        function field(k) { return descendants(page, it => it.key === k && it.activate !== undefined && it.visible, [])[0]; }
        function click(item) {
            if (!item) throw new Error("Control ausente");
            pointer.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        }
        function finish(error) {
            if (finished) return;
            finished = true;
            console.log("REVIEW", JSON.stringify({ scenario: scenario, count: checks.length, checks: checks,
                                                   error: error || "" }));
            Qt.quit();
        }
        function shot(file) {
            writingShots++;
            if (!scene.grabToImage(result => {
                if (!result.saveToFile(out + "/" + file)) { win.finish("No se guardó " + file); return; }
                win.writingShots--;
            })) finish("La ventana no pudo capturarse");
        }
        /** Una orden externa (como haría alguien en la terminal); su resultado queda en `external`. */
        function run(argv) {
            win.external = null;
            ext.command = argv;
            ext.running = true;
        }

        Rectangle {
            id: scene; anchors.fill: parent; color: "#222932"
            Glass {
                width: Math.min(1180 * win.factor, scene.width - 32)
                height: Math.min(860 * win.factor, scene.height - 32)
                anchors.centerIn: parent
                s: win.factor; surface: "settings"; radius: Metrics.openCorner * s
                Surfaces.Settings { id: page; floating: true; s: win.factor; open: true; closeness: 1 }
            }
        }

        Process {
            id: ext
            stdout: StdioCollector { id: extOut }
            onExited: (code) => {
                let doc = null;
                try { doc = JSON.parse(extOut.text.trim()); } catch (e) { doc = null; }
                win.external = { code: code, doc: doc, text: extOut.text };
            }
        }

        // --reload-from: la primera generación es el árbol de ANTES; se instalan las rutas de la entrega y se recarga
        // en caliente (como hará la entrega en la sesión); los pasos corren en la generación nueva.
        Process {
            id: installOverlay
            command: ["cp", "-a", Quickshell.env("SDDM_REVIEW_OVERLAY") + "/.", Quickshell.shellDir]
            onExited: (code) => {
                if (code !== 0) win.finish("No se instalaron las rutas de la entrega");
                else Quickshell.reload(false);
            }
        }
        Timer {
            interval: 900; running: true
            onTriggered: {
                try {
                    // la generación de ANTES no tiene la integración, o es la de la Fase 4 (sin `system`)
                    if (typeof page.sddmRows !== "function" || Svc.SddmTheme.system === undefined) {
                        if (!Quickshell.env("SDDM_REVIEW_OVERLAY")) { win.finish("Árbol sin la integración"); return; }
                        console.log("RELOAD_BASE");
                        Quickshell.watchFiles = false;
                        installOverlay.running = true;
                        return;
                    }
                    win.steps = Checks.cases(win, Svc.SddmTheme, Svc.Settings);
                    win.stepStart = Date.now();
                    runner.start();
                } catch (e) { win.finish(String(e) + "\n" + e.stack); }
            }
        }
        Timer {
            id: runner; interval: 60; repeat: true
            onTriggered: {
                try {
                    if (win.writingShots) return;
                    if (win.next === win.steps.length) { win.finish(""); return; }
                    const st = win.steps[win.next];
                    if (st.fn() !== false) { win.next++; win.stepStart = Date.now(); return; }
                    if (Date.now() - win.stepStart > (st.timeout || 20000)) {
                        const t = Svc.SddmTheme;
                        win.finish("Tiempo agotado: " + st.label + " · " + JSON.stringify({ status: t.status, error: t.error,
                            notice: t.notice, busy: t.busy, previewFailed: t.previewFailed, previewUrl: t.previewUrl,
                            previewStale: t.previewStale, stamp: t.stamp, previewStamp: t.previewStamp }));
                    }
                } catch (e) { win.finish(String(e) + "\n" + e.stack); }
            }
        }
    }
}

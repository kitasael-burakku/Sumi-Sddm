pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Pantalla de inicio de sesión (Sumi SDDM, 2026-11-22): Settings → Desktop tools → Login screen.
 *
 * La configuración es de Sumi SDDM, no de la shell (un dueño por dato): vive en ~/.config/sumi-sddm y NO entra en
 * settings.json, presets ni Export/Import. Aquí sólo se pide y se enseña; todo lo hace la orden `sumi-sddm` del
 * PATH (contrato JSON api 1, docs/CLI-JSON.md de Sumi SDDM), con verbos fijos y `argv` (nunca un shell). La CLI
 * vuelve a validar todo con su lectura estricta. Nada de esto toca el sistema: llevarlo a la pantalla de inicio de
 * sesión real es trabajo de un helper aparte con pkexec, que aún no existe.
 *
 *   claim()      con la página a la vista se carga (versión → esquema → valores) y vive la vista previa; cerrada,
 *                no corre nada
 *   set(k, v)    cambio al momento en la vista; se escribe agrupado (300 ms quieto) con `--expect <stamp>`, así
 *                que un cambio hecho desde la terminal entre medias no se pisa: se recarga y se avisa
 *   preview      600 ms después del último cambio, una a la vez
 *
 * Se lanza como `/usr/bin/env sumi-sddm …`: si la orden no existe, env sale con 127 y `exited` llega igual (un
 * binario inexistente en `Process` no lo emite). Un proceso a la vez, en cola.
 */
Singleton {
    id: root

    readonly property var launcher: ["/usr/bin/env", "sumi-sddm"]
    readonly property int api: 1

    // ---- estado ---------------------------------------------------------------------------------------------------
    /** "" sin comprobar · checking · ready · missing (no hay `sumi-sddm`) · incompatible (otro api) · broken */
    property string status: ""
    property string version: ""
    property string statusDetail: ""
    property var groups: []                  // [{id, label}]
    property var keys: ({})                  // clave → entrada del esquema
    property var order: []                   // claves en el orden del esquema
    property var values: ({})                // clave → {value, default, set}
    property string stamp: ""
    property var warnings: []                // [{key, message}]
    property var fonts: []                   // [{family, system}]
    property string error: ""                // el último error para la persona («» si nada)
    property string notice: ""               // aviso informativo (p. ej. «cambiado en otro sitio»)
    readonly property bool ready: root.status === "ready"
    readonly property bool busy: root._running !== null || root._queue.length > 0 || writeTimer.running
    readonly property int customCount: root.order.filter(k => root.values[k] && root.values[k].set).length

    // ---- quién mira ---------------------------------------------------------------------------------------------
    property var claims: ({})
    readonly property bool watching: Object.keys(root.claims).length > 0
    function claim(who, on) {
        if (!!on === !!root.claims[who]) return;
        const c = Object.assign({}, root.claims);
        if (on) c[who] = true; else delete c[who];
        root.claims = c;
    }
    onWatchingChanged: {
        if (root.watching) root.load();
        else { root.tryArmed = false; root.resetArmed = false; }
    }

    // ---- cola de procesos ----------------------------------------------------------------------------------------
    property var _queue: []
    property var _running: null
    function _enqueue(job) {
        // una carga o una vista previa ya en cola no se repite
        if ((job.kind === "show" || job.kind === "preview") && root._queue.some(j => j.kind === job.kind)) return;
        root._queue = root._queue.concat([job]);
        root._pump();
    }
    function _pump() {
        if (root._running !== null || root._queue.length === 0) return;
        const job = root._queue[0];
        root._queue = root._queue.slice(1);
        root._running = job;
        proc.out = "";
        // La huella se toma al LANZAR, no al encolar: una escritura propia anterior ya la habrá actualizado.
        const expect = job.expect === true && root.stamp.length === 32 ? ["--expect", root.stamp] : [];
        proc.command = root.launcher.concat(job.args).concat(expect).concat(["--json"]);
        proc.running = true;
    }
    Process {
        id: proc
        property string out: ""
        property bool gotOut: false
        property bool exited: false
        property int code: 0
        onStarted: { proc.gotOut = false; proc.exited = false; }
        stdout: StdioCollector { onStreamFinished: { proc.out = this.text; proc.gotOut = true; root._done(); } }
        onExited: (code) => { proc.code = code; proc.exited = true; root._done(); }
    }
    function _done() {
        if (!proc.gotOut || !proc.exited) return;
        proc.gotOut = false; proc.exited = false;
        const job = root._running;
        root._running = null;
        let doc = null;
        try { doc = JSON.parse(String(proc.out).trim()); } catch (e) { doc = null; }
        if (job) {
            try { job.done(doc, proc.code); } catch (e) { root.error = "Unexpected reply from sumi-sddm"; }
        }
        root._pump();
    }

    // ---- carga ---------------------------------------------------------------------------------------------------
    function load() {
        root.status = "checking";
        root._enqueue({ kind: "version", args: ["version"], done: (doc, code) => {
            if (code === 127 && !doc) { root.status = "missing"; root.statusDetail = ""; return; }
            if (!doc || doc.ok !== true) {
                root.status = "broken";
                root.statusDetail = doc && doc.error ? doc.error : "sumi-sddm did not answer as expected";
                return;
            }
            if (doc.api !== root.api) {
                root.status = "incompatible";
                root.statusDetail = "sumi-sddm speaks version " + doc.api + " of its interface; this shell expects " + root.api;
                return;
            }
            root.version = String(doc.version || "");
            root._enqueue({ kind: "schema", args: ["config", "schema"], done: root._schemaDone });
        } });
    }
    function _schemaDone(doc) {
        if (!doc || doc.ok !== true || !Array.isArray(doc.keys)) {
            root.status = "broken";
            root.statusDetail = doc && doc.error ? doc.error : "Could not read the settings list";
            return;
        }
        const k = {}, ord = [];
        for (const e of doc.keys) { k[e.key] = e; ord.push(e.key); }
        root.keys = k;
        root.order = ord;
        root.groups = (doc.groups || []).map(g => ({ id: String(g.id), label: String(g.label || g.id) }));
        root.reload();
        if (root.fonts.length === 0)
            root._enqueue({ kind: "fonts", args: ["config", "fonts"], done: (d) => {
                if (d && d.ok === true) root.fonts = d.families || [];
            } });
    }
    /** Relee los valores. Lo que aún espera a escribirse se conserva encima (la vista no salta atrás). */
    function reload() {
        root._enqueue({ kind: "show", args: ["config", "show"], done: (doc) => {
            if (!doc || doc.ok !== true) {
                root.status = "broken";
                root.statusDetail = doc && doc.error ? doc.error : "Could not read the settings";
                return;
            }
            const v = doc.values || {};
            for (const key in root._pending)
                if (v[key]) v[key] = Object.assign({}, v[key], { value: root._pending[key].value, set: true });
            root.values = v;
            root.stamp = String(doc.stamp || "");
            root.warnings = doc.warnings || [];
            root.status = "ready";
            root.schedulePreview();
        } });
    }

    // ---- escribir --------------------------------------------------------------------------------------------------
    property var _pending: ({})              // clave → {value, raw}; raw "" = quitar
    function valueOf(key) { const v = root.values[key]; return v ? v.value : undefined; }
    function isSet(key) { const v = root.values[key]; return !!(v && v.set); }

    /** Cambio de una clave. `value` en el tipo del esquema; null = volver al valor por defecto. */
    function set(key, value) {
        const e = root.keys[key];
        if (!e || !root.ready) return;
        const unset = value === null || value === undefined;
        const shown = unset ? e["default"] : value;
        const raw = unset ? "" : root._raw(e, value);
        const p = Object.assign({}, root._pending);
        p[key] = { value: shown, raw: raw };
        root._pending = p;
        const v = Object.assign({}, root.values);
        v[key] = Object.assign({}, v[key] || {}, { value: shown, set: !unset });
        root.values = v;
        root.error = "";
        root.notice = "";
        writeTimer.restart();
    }
    function unset(key) { root.set(key, null); }
    function _raw(e, value) {
        if (e.type === "bool") return value ? "true" : "false";
        if (e.type === "integer") return String(Math.round(value));
        if (e.type === "number") return String(Math.round(value * 1000) / 1000);
        return String(value);
    }
    Timer { id: writeTimer; interval: 300; onTriggered: root._flush() }
    function _flush() {
        const keys = Object.keys(root._pending);
        if (keys.length === 0) return;
        if (root._running !== null && root._running.kind === "set") { writeTimer.restart(); return; }
        const sent = root._pending;
        root._pending = ({});
        root._write(["config", "set"].concat(keys.map(k => k + "=" + sent[k].raw)), sent);
    }
    function _write(args, sent) {
        root._enqueue({ kind: "set", args: args, expect: true, done: (doc) => root._written(doc, sent) });
    }
    /** Escrituras aceptadas desde que arrancó (diagnóstico y bancos: los cambios seguidos van agrupados). */
    property int writeCount: 0
    function _written(doc, sent) {
        if (doc && doc.ok === true) {
            root.writeCount++;
            root.stamp = String(doc.stamp || root.stamp);
            root.reload();
            return;
        }
        // Lo enviado no se guardó: lo pendiente posterior tampoco vale si la base cambió.
        if (doc && doc.code === "conflict") {
            root._pending = ({});
            writeTimer.stop();
            root.notice = "Changed outside Settings · reloaded";
        } else {
            root.error = doc && doc.error ? String(doc.error) : "sumi-sddm could not save the change";
        }
        root.reload();
    }

    function setWallpaper(path) {
        const p = String(path || "").trim();
        if (!root.ready || p.length === 0) return;
        root.error = ""; root.notice = "";
        root._write(["wallpaper", "set", p.replace(/^~(?=\/)/, Quickshell.env("HOME") || "~")], {});
    }
    function clearWallpaper() {
        if (!root.ready) return;
        root._write(["wallpaper", "clear"], {});
    }

    /** Reset y Restore piden dos pulsaciones (como Delete en Presets). */
    property bool resetArmed: false
    function resetAll() {
        if (!root.ready || root.customCount === 0) return;
        if (!root.resetArmed) { root.resetArmed = true; disarm.restart(); return; }
        root.resetArmed = false;
        root._pending = ({}); writeTimer.stop();
        root._write(["config", "reset"], {});
    }
    function restorePrevious() {
        if (!root.ready) return;
        root._write(["config", "restore"], {});
    }

    /** La ventana de prueba del greeter real toma el teclado: dos pulsaciones. */
    property bool tryArmed: false
    function openTestWindow() {
        if (!root.ready) return;
        if (!root.tryArmed) { root.tryArmed = true; disarm.restart(); return; }
        root.tryArmed = false;
        Quickshell.execDetached(root.launcher.concat(["try", "--yes"]));
    }
    Timer { id: disarm; interval: 4000; onTriggered: { root.resetArmed = false; root.tryArmed = false; } }

    // ---- vista previa ----------------------------------------------------------------------------------------------
    readonly property var scenarios: [
        { label: "Compact", value: "compact" }, { label: "Password", value: "expanded" },
        { label: "Sessions", value: "sessions" }, { label: "Error", value: "failed" }
    ]
    property string scenario: "expanded"
    onScenarioChanged: root.schedulePreview()
    property string previewUrl: ""
    property string previewStamp: ""
    property bool previewFailed: false
    property int _previewSerial: 0
    readonly property bool previewStale: root.previewStamp !== root.stamp || root._previewScenario !== root.scenario
    property string _previewScenario: ""
    function schedulePreview() { if (root.watching && root.ready) previewTimer.restart(); }
    Timer { id: previewTimer; interval: 600; onTriggered: root._preview() }
    function _preview() {
        if (!root.watching || !root.ready) return;
        if (Object.keys(root._pending).length > 0 || writeTimer.running) { previewTimer.restart(); return; }
        const sc = root.scenario;
        root._enqueue({ kind: "preview", args: ["preview", "--scenario", sc, "--size", "1280x720"], done: (doc) => {
            if (doc && doc.ok === true && doc.png) {
                root._previewSerial++;
                // otra URL en cada vista previa: la Image no reutiliza la anterior de su caché
                root.previewUrl = "file://" + String(doc.png) + "?v=" + root._previewSerial;
                root.previewStamp = String(doc.stamp || "");
                root._previewScenario = sc;
                root.previewFailed = false;
            } else {
                root.previewFailed = true;
                root.error = doc && doc.error ? String(doc.error) : "The preview could not be made";
            }
        } });
    }

    // ---- filas para Settings ----------------------------------------------------------------------------------------
    /** Filas de un grupo del esquema (kind «sddm»: las pinta components/SddmField). */
    function rows(group) {
        if (!root.ready) return [];
        return root.order.filter(k => root.keys[k].group === group).map(k => {
            const e = root.keys[k];
            return { id: "sddm:" + k, prop: "", kind: "sddm", key: k, name: String(e.label || k),
                     caption: root.captionFor(k) };
        });
    }
    function captionFor(key) {
        const w = root.warnings.find(x => x.key === key);
        if (w) return String(w.message);
        const e = root.keys[key];
        return e && e.help ? String(e.help) : "";
    }
    /** Etiqueta de un valor de enum ("top-left" → «Top left», "24h" → «24 h»). */
    function enumLabel(v) {
        const s = String(v);
        if (/^\d+h$/.test(s)) return s.replace("h", " h");
        const t = s.replace(/-/g, " ");
        return t.charAt(0).toUpperCase() + t.slice(1);
    }
    /** Un paso de teclado sobre la clave (←/→, Enter), como `adjust` de Settings. */
    function step(key, dir) {
        const e = root.keys[key];
        if (!e || !root.ready) return;
        const v = root.valueOf(key);
        if (e.type === "bool") root.set(key, dir === 0 ? !v : dir > 0);
        else if (e.type === "enum") {
            const vals = e.values || [];
            let i = Math.max(0, vals.indexOf(v));
            const d = dir === 0 ? 1 : dir;
            root.set(key, vals[((i + d) % vals.length + vals.length) % vals.length]);
        } else if ((e.type === "number" || e.type === "integer") && dir !== 0) {
            const lo = e.allowZero ? 0 : e.min;
            let n = Number(v) + dir * (e.step || 1);
            if (e.allowZero && n > 0 && n < e.min) n = dir > 0 ? e.min : 0;
            root.set(key, Math.max(lo, Math.min(e.max, Math.round(n * 1000) / 1000)));
        }
    }
}

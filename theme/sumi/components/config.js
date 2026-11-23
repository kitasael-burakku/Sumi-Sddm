.pragma library
.import "schema.js" as Schema

/*
 * Lectura tolerante de la configuración: el equivalente exacto de `lenient()` en
 * tools/sumiconf/schema.py. Ambas se prueban con los mismos casos (tests/fixtures/config-vectors.js).
 * Nunca lanza: un valor que no se entiende vuelve al defecto; un número fuera de rango se acota.
 */

var NUM_RE = /^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/;
var COLOR_RE = /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
var CONTROL_RE = /[\x00-\x1f\x7f]/;
var TRUE = ["true", "1", "yes", "on"];
var FALSE = ["false", "0", "no", "off"];

function entry(key) {
    return Schema.KEYS[key];
}

function parseNumber(v) {
    if (!NUM_RE.test(v))
        return null;
    var n = Number(v);
    return isFinite(n) ? n : null;
}

function lenientPath(e, v) {
    if (v === "" || v.indexOf("..") >= 0 || CONTROL_RE.test(v))
        return e["default"];
    if (v.indexOf("file:///") !== 0 && v.indexOf(":") >= 0)
        return e["default"];
    var base = v.substring(v.lastIndexOf("/") + 1);
    var ext = base.indexOf(".") >= 0 ? base.substring(base.lastIndexOf(".") + 1).toLowerCase() : "";
    if ((e.extensions || []).indexOf(ext) < 0)
        return e["default"];
    return v;
}

/** `raw`: cadena de QSettings, lista (QSettings partió en comas) o undefined/null. */
function lenient(e, raw) {
    var d = e["default"];
    if (raw === undefined || raw === null)
        return d;
    var v = raw;
    if (typeof v === "object" && v.length !== undefined)
        v = Array.prototype.join.call(v, ", ");
    v = String(v).trim();
    var t = e.type;
    if (t === "path")
        return lenientPath(e, v);
    if (v === "")
        return d;
    if (t === "number" || t === "integer") {
        var n = parseNumber(v);
        if (n === null)
            return d;
        if (t === "integer") {
            n = Math.round(n);
            if (e.allowZero && n <= 0)
                return 0;
        }
        return Math.min(e.max, Math.max(e.min, n));
    }
    if (t === "bool") {
        var lb = v.toLowerCase();
        return TRUE.indexOf(lb) >= 0 ? true : FALSE.indexOf(lb) >= 0 ? false : d;
    }
    if (t === "enum") {
        var le = v.toLowerCase();
        return e.values.indexOf(le) >= 0 ? le : d;
    }
    if (t === "color")
        return COLOR_RE.test(v) ? v : d;
    if (t === "string") {
        var ok = v.length <= (e.maxLength || 256) && !CONTROL_RE.test(v) && new RegExp(e.pattern).test(v);
        return ok ? v : d;
    }
    return d;
}

/** Valor de `key` leído de `source` (el `config` de SDDM o un objeto JS). */
function read(source, key) {
    var e = Schema.KEYS[key];
    if (!e)
        return undefined;
    var raw;
    try {
        raw = source ? source[key] : undefined;
    } catch (err) {
        raw = undefined;
    }
    return lenient(e, raw);
}

/** Cuántas claves difieren de su defecto tras la lectura tolerante (diagnóstico sin datos: sólo un número). */
function customCount(source) {
    var n = 0;
    for (var k in Schema.KEYS) {
        var e = Schema.KEYS[k];
        if (read(source, k) !== e["default"])
            n++;
    }
    return n;
}

pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../../theme/sumi/components"
import "../../theme/sumi/components/config.js" as Config
import "../../theme/sumi/components/schema.js" as Schema
import "../fixtures/config-vectors.js" as Vectors

/*
 * Paridad de la lectura tolerante: config.js (tema) frente a los casos que también ejecuta la
 * implementación de Python (tests/py/test_config.py). Y que Style no inventa defaults propios.
 */
TestCase {
    id: tc
    name: "Config"

    Component {
        id: styleC
        Style {}
    }

    function test_vectors() {
        verify(Vectors.VECTORS.length > 40);
        for (let i = 0; i < Vectors.VECTORS.length; i++) {
            const v = Vectors.VECTORS[i];
            const got = Config.lenient(Config.entry(v.key), v.raw);
            const label = v.key + "=" + JSON.stringify(v.raw);
            if (typeof v.expect === "number") {
                compare(typeof got, "number", label);
                fuzzyCompare(got, v.expect, 1e-9, label);
            } else {
                compare(got, v.expect, label);
            }
        }
    }

    function test_qsettings_list_is_joined() {
        compare(Config.lenient(Config.entry("dateFormat"), ["dddd", "d MMMM"]), "dddd, d MMMM");
    }

    function test_read_survives_hostile_source() {
        const hostile = {};
        Object.defineProperty(hostile, "notchRadius", { get: function () { throw new Error("boom"); } });
        compare(Config.read(hostile, "notchRadius"), 22);
        compare(Config.read(null, "notchRadius"), 22);
        compare(Config.read({}, "noSuchKey"), undefined);
    }

    function test_style_uses_schema_defaults() {
        const st = createTemporaryObject(styleC, tc, { source: ({}) });
        compare(st.notchRadius, Schema.KEYS.notchRadius["default"]);
        compare(st.notchIdleCollapse, Schema.KEYS.notchIdleCollapse["default"]);
        compare(st.avatarSize, Schema.KEYS.avatarSize["default"]);
        compare(st.userInactiveOpacity, Schema.KEYS.userInactiveOpacity["default"]);
        compare(st.accent.toString(), Schema.KEYS.accentColor["default"]);
        compare(st.clock24h, Schema.KEYS.clockFormat["default"] === "24h");
        compare(st.clockWeight, Font.Light);
        compare(st.animate, Schema.KEYS.animations["default"]);
        compare(st.background.toString(), "");
        compare(st.fontFamily, "Inter", "no bundled font loaded in a bare Style");
    }

    function test_style_new_keys() {
        const st = createTemporaryObject(styleC, tc, { source: {
                "fontScale": "1.5", "clockWeight": "THIN", "userNames": "false", "clockOffsetX": "-40",
                "background": "backgrounds/user.png", "fontFamily": "IBM Plex Sans" } });
        compare(st.fs(10), 15);
        compare(st.clockWeight, Font.Thin);
        compare(st.userNames, false);
        compare(st.clockOffsetX, -40);
        verify(st.background.toString().endsWith("/theme/sumi/backgrounds/user.png"), st.background);
        compare(st.fontFamily, "IBM Plex Sans");
    }
}

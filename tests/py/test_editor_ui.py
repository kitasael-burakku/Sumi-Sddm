"""Ventana del editor (Main.qml + Field.qml) offscreen, con eventos de verdad (clic, teclas) sobre cada control.

Contra la CLI falsa (fake_sumi_sddm.py) se comprueba que cada tipo del esquema produce el valor en el formato que
espera `config set`, que lo que no vale no se envía y que los controles vuelven a enseñar lo guardado. Contra la CLI
del repositorio, con XDG_CONFIG_HOME temporal, el criterio de salida de la fase 2: las escrituras llegan a
theme.conf.user y un `config set` desde la terminal con la ventana abierta produce un aviso y no se pierde.
Se salta sin PySide6.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "editor"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from qt_support import QGuiApplication, app, spin, wait  # noqa: E402

if QGuiApplication is not None:
    from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QEvent, QMetaObject, Qt, QUrl, qInstallMessageHandler
    from PySide6.QtGui import QColor, QKeyEvent
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickItem
    from PySide6.QtQuickControls2 import QQuickStyle
    from sumi_sddm_editor.backend import Backend

FAKE = Path(__file__).resolve().parent / "fake_sumi_sddm.py"
MAIN = ROOT / "editor" / "sumi_sddm_editor" / "Main.qml"
CLI = ROOT / "tools" / "sumi-sddm"


class WindowCase(unittest.TestCase):
    """Una ventana por prueba; recoge los mensajes de QML para exigir que no haya avisos."""

    def setUp(self):
        QQuickStyle.setStyle("Fusion")
        app()
        self.messages: list[str] = []
        self._old_handler = qInstallMessageHandler(lambda _mode, _ctx, m: self.messages.append(m))
        self._tmp = tempfile.TemporaryDirectory(prefix="sumi-editor-ui-")
        self.dir = Path(self._tmp.name)
        self.engine = None
        self.win = None

    def tearDown(self):
        warnings = self.qml_warnings()
        if self.win is not None:
            wait(lambda: not self.b.busy, 5)
            self.win.setProperty("closeWhenIdle", False)
            self.win.close()
        if self.engine is not None:
            self.engine.deleteLater()
        spin(0.05)
        qInstallMessageHandler(self._old_handler)
        self._tmp.cleanup()
        self.assertEqual(warnings, [], "avisos de QML")

    def open(self, **kw) -> None:
        kw.setdefault("write_delay_ms", 40)
        self.b = Backend(**kw)
        self.b.previewEnabled = False
        self.engine = QQmlApplicationEngine()
        self.engine.setInitialProperties({"backend": self.b})
        self.engine.load(QUrl.fromLocalFile(str(MAIN)))
        self.assertTrue(self.engine.rootObjects(), self.messages)
        self.win = self.engine.rootObjects()[0]
        self.b.load()

    def ready(self) -> None:
        self.assertTrue(wait(lambda: self.b.ready and not self.b.busy), (self.b.status, self.b.statusDetail))
        spin(0.05)

    def idle(self) -> None:
        self.assertTrue(wait(lambda: not self.b.busy), "el backend no quedó quieto")
        spin(0.05)

    def qml_warnings(self) -> list[str]:
        return [m for m in self.messages if ".qml:" in m or "qml" in m.lower() or "binding" in m.lower()]

    def no_warnings(self) -> None:
        self.assertEqual(self.qml_warnings(), [])

    # ---- buscar y tocar -------------------------------------------------------------------------------------------
    def items(self, root=None):
        stack = [root or self.win.contentItem()]
        while stack:
            it = stack.pop()
            yield it
            stack.extend(reversed(it.childItems()))        # en el orden del archivo

    def item(self, name: str, root=None):
        for it in self.items(root):
            if it.objectName() == name:
                return it
        self.fail(f"no hay ningún elemento «{name}»")

    def visible_items(self, prefix: str):
        return [it for it in self.items() if it.objectName().startswith(prefix) and it.isVisible()]

    def control(self, key: str, name: str):
        return self.item(name, self.item("field-" + key))

    def show(self, group: str) -> None:
        self.click(self.item("group-" + group))

    def click(self, it) -> None:
        self.assertTrue(it.isEnabled(), it.objectName())
        QMetaObject.invokeMethod(it, "click")
        spin(0.02)

    def key(self, it, k) -> None:
        for t in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
            app().sendEvent(it, QKeyEvent(t, k, Qt.KeyboardModifier.NoModifier))
        spin(0.02)

    def type_in(self, it, text: str) -> None:
        # Como una persona: el campo tiene el foco (sin él, Enter no emite editingFinished).
        it.forceActiveFocus()
        it.setProperty("text", text)
        self.key(it, Qt.Key.Key_Return)


@unittest.skipIf(QGuiApplication is None, "PySide6 no está instalado")
class EditorUiFakeTest(WindowCase):
    def setUp(self):
        super().setUp()
        exe = self.dir / "sumi-sddm"
        exe.write_text(f"#!{sys.executable} -IB\n" + FAKE.read_text())
        exe.chmod(0o755)
        self.exe = str(exe)
        self.state({})

    def state(self, st: dict | None = None, **update) -> dict:
        p = self.dir / "state.json"
        cur = json.loads(p.read_text()) if st is None else st
        cur.update(update)
        p.write_text(json.dumps(cur))
        return cur

    def sets(self) -> list[list[str]]:
        p = self.dir / "log.jsonl"
        log = [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []
        return [a[2:a.index("--expect")] if "--expect" in a else a[2:-1] for a in log if a[:2] == ["config", "set"]]

    def loaded(self, **kw) -> None:
        self.open(program=self.exe, **kw)
        self.ready()

    # ---- ventana -----------------------------------------------------------------------------------------------------
    def test_loads_groups_and_fields(self):
        self.loaded()
        self.assertEqual([g.objectName() for g in self.visible_items("group-")],
                         ["group-colors", "group-clock", "group-users"])
        self.assertEqual(self.item("pageTitle").property("text"), "Colors")
        self.assertEqual({f.objectName() for f in self.visible_items("field-")},
                         {"field-accentColor", "field-dim", "field-blur"})
        self.show("clock")
        self.assertEqual(self.item("pageTitle").property("text"), "Clock")
        self.assertEqual({f.objectName() for f in self.visible_items("field-")},
                         {"field-clockFormat", "field-showClock", "field-clockPosition", "field-dateFormat",
                          "field-fontFamily"})
        self.assertEqual(self.item("customCount").property("text"), "All defaults")
        self.assertFalse(self.item("resetAll").isEnabled())
        self.no_warnings()

    def test_search_across_groups(self):
        self.loaded()
        self.item("search").setProperty("text", "CLOCK")        # por etiqueta («Show clock») o clave
        spin(0.05)
        self.assertEqual({f.objectName() for f in self.visible_items("field-")},
                         {"field-clockFormat", "field-showClock", "field-clockPosition"})
        self.assertEqual(self.item("pageTitle").property("text"), "3 results")
        self.assertFalse(any(g.property("highlighted") for g in self.visible_items("group-")))
        self.item("search").setProperty("text", "wallpaper")
        spin(0.05)
        self.assertEqual([f.objectName() for f in self.visible_items("field-")], ["field-background"])
        self.item("search").setProperty("text", "zzz")
        spin(0.05)
        self.assertEqual(self.visible_items("field-"), [])

    def test_missing_then_retry(self):
        self.open(program=str(self.dir / "not-here"))
        self.assertTrue(wait(lambda: self.b.status == "missing"))
        spin(0.05)
        self.assertEqual(self.item("statusTitle").property("text"), "The sumi-sddm command was not found")
        self.assertFalse(self.item("form").isVisible())
        (self.dir / "not-here").symlink_to(self.exe)
        self.click(self.item("retry"))
        self.ready()
        self.assertTrue(self.item("form").isVisible())
        self.assertFalse(self.item("statusPage").isVisible())

    def test_broken_shows_detail(self):
        self.state(None, garbage=True)
        self.open(program=self.exe)
        self.assertTrue(wait(lambda: self.b.status == "broken"))
        spin(0.05)
        self.assertEqual(self.item("statusDetail").property("text"), "something broke")
        self.assertTrue(self.item("retry").isVisible())

    # ---- un control por tipo ---------------------------------------------------------------------------------------
    def test_bool_switch(self):
        self.loaded()
        self.show("clock")
        sw = self.control("showClock", "switch")
        self.assertTrue(sw.property("checked"))
        self.click(sw)
        self.idle()
        self.assertEqual(self.sets(), [["showClock=false"]])
        self.assertFalse(sw.property("checked"))
        self.assertTrue(self.control("showClock", "customDot").isVisible())

    def test_enum_segments(self):
        self.loaded()
        self.show("clock")
        seg = self.control("clockFormat", "segment-12h")
        self.assertEqual(seg.property("text"), "12 h")
        self.assertFalse(seg.property("checked"))
        self.click(seg)
        self.idle()
        self.assertEqual(self.sets(), [["clockFormat=12h"]])
        self.assertTrue(seg.property("checked"))
        self.assertFalse(self.control("clockFormat", "segment-24h").property("checked"))
        self.click(seg)                                   # el valor que ya está: nada que escribir
        self.idle()
        self.assertEqual(len(self.sets()), 1)

    def test_enum_combo_by_keyboard(self):
        self.loaded()
        self.show("clock")
        combo = self.control("clockPosition", "combo")
        self.assertEqual(combo.property("currentIndex"), 0)
        self.key(combo, Qt.Key.Key_Down)
        self.idle()
        self.assertEqual(self.sets(), [["clockPosition=top-left"]])
        self.assertEqual(combo.property("currentText"), "Top left")

    def test_number_slider_and_field(self):
        self.loaded()
        slider = self.control("dim", "slider")
        self.key(slider, Qt.Key.Key_Right)
        self.key(slider, Qt.Key.Key_Right)
        self.idle()
        self.assertEqual(self.sets(), [["dim=0.5"]], "dos pasos agrupados en una escritura")
        field = self.control("dim", "number")
        self.assertEqual(field.property("text"), "0.5")
        self.type_in(field, "0,7")
        self.idle()
        self.assertEqual(self.sets()[-1], ["dim=0.7"])
        self.assertAlmostEqual(slider.property("value"), 0.7)
        self.type_in(field, "5")
        self.idle()
        self.assertEqual(len(self.sets()), 2, "fuera de rango no se envía")
        self.assertEqual(self.control("dim", "caption").property("text"), "Use a value between 0 and 1")
        self.assertEqual(field.property("text"), "0.7", "el campo vuelve a lo guardado")

    def test_integer_allow_zero(self):
        self.loaded()
        off = self.control("blur", "off")
        self.assertTrue(off.property("checked"))
        self.assertFalse(self.control("blur", "slider").isEnabled())
        self.click(off)
        self.idle()
        self.assertEqual(self.sets(), [["blur=8"]], "sin un defecto mayor que 0, vuelve al mínimo")
        slider = self.control("blur", "slider")
        self.assertTrue(slider.isEnabled())
        self.key(slider, Qt.Key.Key_Right)
        self.idle()
        self.assertEqual(self.sets()[-1], ["blur=12"])
        self.type_in(self.control("blur", "number"), "13.6")
        self.idle()
        self.assertEqual(self.sets()[-1], ["blur=14"])
        self.click(self.control("blur", "off"))
        self.idle()
        self.assertEqual(self.sets()[-1], ["blur=0"])

    def test_colour_field(self):
        self.loaded()
        hexf = self.control("accentColor", "hex")
        self.type_in(hexf, "FF8800")
        self.idle()
        self.assertEqual(self.sets(), [["accentColor=#ff8800"]])
        self.type_in(hexf, "#80112233")
        self.idle()
        self.assertEqual(self.sets()[-1], ["accentColor=#80112233"])
        self.type_in(hexf, "red")
        self.idle()
        self.assertEqual(len(self.sets()), 2)
        self.assertIn("is not a colour", self.control("accentColor", "caption").property("text"))
        self.assertEqual(hexf.property("text"), "#80112233")

    def test_colour_dialog_value(self):
        self.loaded()
        field = self.item("field-accentColor")
        col = self.item("swatch", field).parentItem()
        for c in ("#ff8800", "#80112233"):          # lo que enviaría el ColorDialog (con y sin alfa)
            out = QMetaObject.invokeMethod(col, "hexOf", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", QColor(c)))
            self.assertEqual(out, c)

    def test_string_pattern_and_empty(self):
        self.loaded()
        self.show("clock")
        f = self.control("dateFormat", "text")
        self.type_in(f, "%Y")
        self.idle()
        self.assertEqual(self.sets(), [])
        self.assertEqual(self.control("dateFormat", "caption").property("text"), "Some characters are not allowed here")
        self.type_in(f, "  d MMM yyyy ")
        self.idle()
        self.assertEqual(self.sets(), [["dateFormat=d MMM yyyy"]])
        self.assertEqual(self.control("dateFormat", "caption").property("text"), "")
        self.type_in(f, "")
        self.idle()
        self.assertEqual(self.sets()[-1], ["dateFormat="])
        self.assertEqual(f.property("text"), "dddd, d MMMM")

    def test_path_remove(self):
        self.state(None, values={"background": "backgrounds/user.png"})
        self.loaded()
        self.show("users")
        self.assertEqual(self.control("background", "pathValue").property("text"), "user.png")
        self.click(self.control("background", "remove"))
        self.idle()
        self.assertEqual(self.control("background", "pathValue").property("text"), "Built-in background")
        self.assertFalse(self.control("background", "remove").isVisible())

    def test_reset_field_and_reset_all(self):
        self.state(None, values={"dim": 0.7, "showClock": False})
        self.loaded()
        self.assertEqual(self.item("customCount").property("text"), "2 customised")
        self.assertTrue(self.control("dim", "reset").isEnabled())
        self.assertFalse(self.control("accentColor", "reset").isEnabled())
        self.click(self.control("dim", "reset"))
        self.idle()
        self.assertEqual(self.sets(), [["dim="]])
        self.assertEqual(self.item("customCount").property("text"), "1 customised")
        ra = self.item("resetAll")
        self.click(ra)
        self.assertEqual(ra.property("text"), "Press again to reset")
        self.click(ra)
        self.idle()
        self.assertEqual(self.item("customCount").property("text"), "All defaults")
        self.assertFalse(ra.isEnabled())
        self.click(self.item("restore"))
        self.idle()
        self.assertEqual(self.item("customCount").property("text"), "1 customised")

    def test_controls_follow_outside_changes_after_editing(self):
        # Tras una edición, el control debe seguir enlazado a lo guardado (no quedarse con lo que tocó la persona).
        self.loaded()
        self.show("clock")
        sw = self.control("showClock", "switch")
        combo = self.control("clockPosition", "combo")
        self.click(sw)
        self.key(combo, Qt.Key.Key_Down)
        self.idle()
        self.state(None, values={"showClock": True, "clockPosition": "bottom-right"})
        self.b.recheck()
        self.idle()
        self.assertTrue(sw.property("checked"))
        self.assertEqual(combo.property("currentText"), "Bottom right")
        self.assertEqual(self.item("message").property("text"), "Changed outside the editor · reloaded")
        self.click(self.item("dismiss"))
        self.assertEqual(self.item("message").property("text"), "")

    def test_cli_error_is_shown(self):
        self.state(None, busy_next=1)
        self.loaded()
        self.click(self.control("blur", "off"))
        self.idle()
        self.assertEqual(self.item("message").property("text"), "another sumi-sddm operation is running")
        self.assertTrue(self.control("blur", "off").property("checked"), "vuelve a lo guardado")

    def test_close_writes_pending_changes_first(self):
        self.loaded(write_delay_ms=5000)
        self.type_in(self.control("accentColor", "hex"), "#123456")
        self.assertEqual(self.sets(), [])
        self.win.close()
        self.assertTrue(self.win.isVisible(), "no se cierra con una escritura pendiente")
        self.assertTrue(wait(lambda: not self.win.isVisible(), 5))
        self.assertEqual(self.sets(), [["accentColor=#123456"]])
        self.win = None


@unittest.skipIf(QGuiApplication is None, "PySide6 no está instalado")
class EditorUiRealCliTest(WindowCase):
    """Criterio de salida de la fase 2 con la CLI del repositorio (configuración en un directorio temporal)."""

    def setUp(self):
        super().setUp()
        self._env = {k: os.environ.get(k) for k in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME")}
        os.environ["XDG_CONFIG_HOME"] = str(self.dir / "config")
        os.environ["XDG_CACHE_HOME"] = str(self.dir / "cache")
        self.conf = self.dir / "config" / "sumi-sddm" / "theme.conf.user"

    def tearDown(self):
        super().tearDown()
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def terminal(self, *args: str) -> str:
        return subprocess.run([sys.executable, "-B", str(CLI), *args], check=True, capture_output=True, text=True,
                              timeout=60).stdout

    def saved(self) -> dict:
        """Lo que hay en theme.conf.user, leído por la CLI (sólo las claves personalizadas)."""
        self.assertTrue(self.conf.is_file())
        vals = json.loads(self.terminal("config", "show", "--json"))["values"]
        return {k: v["value"] for k, v in vals.items() if v["set"]}

    def test_writes_reach_theme_conf_and_outside_changes_survive(self):
        self.open(program=str(CLI))
        self.ready()
        self.assertGreater(len(self.b.order), 30)
        self.show("colors")
        self.type_in(self.control("accentColor", "hex"), "#ff8800")
        self.show("notch")
        self.click(self.control("notchIdleCollapse", "off"))
        self.idle()
        self.assertEqual(self.saved(), {"accentColor": "#ff8800", "notchIdleCollapse": 0})

        # Con la ventana abierta, alguien cambia otra clave desde la terminal…
        self.terminal("config", "set", "clockFormat=12h")
        self.b.recheck()                                   # lo que hace la ventana al recuperar el foco
        self.idle()
        self.assertEqual(self.item("message").property("text"), "Changed outside the editor · reloaded")
        self.show("clock")
        self.assertTrue(self.control("clockFormat", "segment-12h").property("checked"))

        # …y la siguiente edición desde la ventana no la pisa.
        self.type_in(self.control("dateFormat", "text"), "d MMM")
        self.idle()
        self.assertEqual(self.saved(), {"accentColor": "#ff8800", "notchIdleCollapse": 0, "clockFormat": "12h",
                                        "dateFormat": "d MMM"})

        # Sin recargar: la escritura choca (--expect), se recarga, se avisa y lo de la terminal sigue ahí.
        self.terminal("config", "set", "accentColor=#00ff00")
        self.type_in(self.control("dateFormat", "text"), "d MMMM yyyy")
        self.idle()
        self.assertEqual(self.item("message").property("text"), "Changed outside the editor · reloaded")
        self.assertEqual(self.saved(), {"accentColor": "#00ff00", "notchIdleCollapse": 0, "clockFormat": "12h",
                                        "dateFormat": "d MMM"})
        self.assertEqual(self.control("dateFormat", "text").property("text"), "d MMM", "enseña lo guardado")
        self.no_warnings()


if __name__ == "__main__":
    unittest.main()

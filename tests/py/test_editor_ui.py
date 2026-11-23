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

from qt_support import QGuiApplication, app, flush_deletes, spin, wait  # noqa: E402

if QGuiApplication is not None:
    from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QEvent, QMetaObject, QObject, QPointF, Qt, QUrl, qInstallMessageHandler
    from PySide6.QtGui import QAccessible, QColor, QImage, QKeyEvent
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
        if QQuickStyle.name() != "Fusion":
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
        self.close_window()
        qInstallMessageHandler(self._old_handler)
        self._tmp.cleanup()
        self.assertEqual(warnings, [], "avisos de QML")

    def close_window(self) -> None:
        """Desmontaje en orden y completo AHORA: nada de esta ventana debe destruirse durante la prueba siguiente."""
        if self.engine is None:
            return
        wait(lambda: self.quiet(), 5)
        self.b.shutdown()
        if self.win is not None:
            self.win.setProperty("closeWhenIdle", False)
            self.win.close()
        win = self.engine.rootObjects()[0] if self.engine.rootObjects() else None
        self.engine.deleteLater()
        flush_deletes()
        # La ventana se destruye en diferido: el backend, sólo cuando ya no existe (si no, sus enlaces se
        # reevalúan con backend = null y QML avisa).
        import shiboken6
        wait(lambda: win is None or not shiboken6.isValid(win), 2)
        flush_deletes()
        self.b.deleteLater()
        flush_deletes()
        self.engine = self.win = None

    def open(self, **kw) -> None:
        kw.setdefault("write_delay_ms", 40)
        kw.setdefault("preview_delay_ms", 60)
        self.b = Backend(**kw)
        self.engine = QQmlApplicationEngine()
        self.engine.setInitialProperties({"backend": self.b})
        self.engine.load(QUrl.fromLocalFile(str(MAIN)))
        self.assertTrue(self.engine.rootObjects(), self.messages)
        self.win = self.engine.rootObjects()[0]
        self.win.resize(1440, 860)
        self.b.load()

    def quiet(self) -> bool:
        b = self.b
        return not b.busy and b.systemBusy == "" and not b._preview_timer.isActive() and not b._apply_retry.isActive()

    def ready(self) -> None:
        self.assertTrue(wait(lambda: self.b.ready and self.quiet()), (self.b.status, self.b.statusDetail))
        spin(0.05)

    def idle(self) -> None:
        self.assertTrue(wait(self.quiet), "el backend no quedó quieto")
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

    def obj(self, name: str):
        """Un objeto no visual (p. ej. un Popup): hijo QObject de algún elemento visible del árbol visual."""
        for it in self.items(self.win.contentItem()):
            if not it.isVisible():                        # p. ej. campos de otro grupo, ya en deleteLater
                continue
            o = it.findChild(QObject, name, Qt.FindChildOption.FindDirectChildrenOnly)
            if o is not None:
                return o
        self.fail(f"no hay ningún objeto «{name}»")

    def texts(self, root) -> list[str]:
        return [str(i.property("text")) for i in self.items(root) if i.isVisible() and i.property("text")]

    @staticmethod
    def loaded_image(img) -> bool:
        return img.property("sourceSize").width() > 0 and img.property("progress") == 1.0

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
        self.assertEqual(self.item("message").property("text"), "Another sumi-sddm operation is running; try again")
        self.assertTrue(self.control("blur", "off").property("checked"), "vuelve a lo guardado")

    # ---- fase 3: vista previa, fuentes, avatar, fondo ---------------------------------------------------------------
    def log(self, *prefix: str) -> list[list[str]]:
        p = self.dir / "log.jsonl"
        log = [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []
        return [a for a in log if a[:len(prefix)] == list(prefix)]

    def dialog(self, owner: str, path: str) -> None:
        """Lo que pasa cuando la persona elige (FileDialog) o suelta un archivo sobre `owner`: su `choose(url)`.

        Python no toca el FileDialog: PySide no convierte QQuickFileDialog* y findChild devuelve otro objeto.
        """
        QMetaObject.invokeMethod(self.item(owner), "choose", Q_ARG("QVariant", QUrl.fromLocalFile(path)))
        spin(0.02)

    def test_preview_shows_and_follows_changes(self):
        self.loaded()
        img = self.item("previewImage")
        self.assertTrue(wait(lambda: self.loaded_image(img)))
        first = img.property("source").toString()
        self.assertTrue(first.endswith("?v=1"))
        size = self.b.previewSize
        self.assertEqual(self.log("preview")[0][:5], ["preview", "--scenario", "expanded", "--size", size])
        self.type_in(self.control("accentColor", "hex"), "#ff0000")
        self.idle()
        self.assertNotEqual(img.property("source").toString(), first, "cada cambio guardado, otra vista previa")
        self.assertEqual(self.b.previewStamp, self.b.stamp)
        self.assertFalse(self.item("stale").isVisible())

    def test_preview_scene_and_size(self):
        self.loaded()
        scene = self.item("scenario")
        self.assertEqual(scene.property("currentText"), "Password")
        self.key(scene, Qt.Key.Key_Down)
        self.idle()
        self.assertEqual(self.log("preview")[-1][:3], ["preview", "--scenario", "sessions"])
        size = self.item("size")
        self.assertIn("(this screen)", size.property("displayText"))
        self.key(size, Qt.Key.Key_Down)
        self.assertTrue(self.b.previewStale)
        self.idle()
        self.assertFalse(self.b.previewStale)
        self.assertNotEqual(self.log("preview")[-1][4], size.property("model")[0])
        self.assertEqual(self.log("preview")[-1][4], self.b.previewSize)
        self.assertNotIn("(this screen)", size.property("displayText"))

    def test_hidden_preview_makes_none(self):
        self.loaded()
        n = len(self.log("preview"))
        self.click(self.item("togglePreview"))
        self.assertFalse(self.item("preview").isVisible())
        self.assertFalse(self.b.previewEnabled)
        self.type_in(self.control("accentColor", "hex"), "#00ff00")
        self.idle()
        spin(0.15)
        self.assertEqual(len(self.log("preview")), n)
        self.click(self.item("togglePreview"))
        self.idle()
        self.assertEqual(len(self.log("preview")), n + 1, "al volver a enseñarla, se pone al día")

    def test_preview_keeps_scene_and_resolution_across_layouts(self):
        self.loaded()
        self.b.scenario = "sessions"
        self.b.previewSize = "1366x768"
        self.idle()
        preview = self.item("preview")
        shot = self.item("previewImage")
        source = shot.property("source")
        count = len(self.log("preview"))

        self.click(self.item("expandPreview"))
        self.assertTrue(preview.property("expanded"))
        self.assertFalse(self.item("scroll").isVisible())
        self.idle()
        self.assertEqual(len(self.log("preview")), count)
        self.assertEqual(shot.property("source"), source)
        self.click(self.item("expandPreview"))

        self.win.resize(360, 420)
        spin(0.1)
        self.assertFalse(preview.isVisible())
        self.assertFalse(self.b.previewEnabled)
        self.click(self.item("togglePreview"))
        self.idle()
        self.assertTrue(preview.isVisible())
        self.assertEqual(self.b.scenario, "sessions")
        self.assertEqual(self.b.previewSize, "1366x768")
        self.assertEqual(cpp(shot), cpp(self.item("previewImage")))

        self.click(self.item("togglePreview"))
        self.assertTrue(self.item("scroll").isVisible())
        section_picker = self.item("sectionPicker")
        section_picker.forceActiveFocus()
        self.key(section_picker, Qt.Key.Key_Down)
        self.assertEqual(self.item("pageTitle").property("text"), "Clock")

    def test_try_in_a_window(self):
        self.loaded()
        btn = self.item("tryWindow")
        self.click(btn)
        self.assertEqual(btn.property("text"), "Press again to open")
        spin(0.1)
        self.assertEqual(self.log("try"), [])
        self.click(btn)
        self.assertTrue(wait(lambda: self.log("try")))
        self.assertEqual(self.log("try")[0], ["try", "--yes"])
        self.assertEqual(btn.property("text"), "Try in a window")

    def test_font_picker(self):
        self.state(None, warnings=[{"key": "fontFamily", "message": "Mine is only in your home folder"}],
                   values={"fontFamily": "Mine"})
        self.loaded()
        self.show("clock")
        btn = self.control("fontFamily", "fontButton")
        self.assertEqual(btn.property("text"), "Mine")
        self.assertEqual(self.control("fontFamily", "caption").property("text"), "Mine is only in your home folder")
        self.click(btn)
        popup = self.obj("fontPopup")
        self.assertTrue(popup.property("opened") or wait(lambda: popup.property("opened"), 2))
        names = lambda: [i.objectName() for i in self.items(self.win.contentItem()) if i.objectName().startswith("font-")
                         and i.isVisible()]
        self.assertEqual(names()[:3], ["font-bundled", "font-Inter", "font-Mine"])
        self.assertIn("Only in your home folder · the login screen can't use it", self.texts(self.item("font-Mine")))
        self.assertEqual(self.texts(self.item("font-Inter")), ["Inter"])
        search = self.item("fontSearch")
        search.setProperty("text", "int")              # «Bundled Inter» también es Inter
        spin(0.05)
        self.assertEqual(names(), ["font-bundled", "font-Inter"])
        search.setProperty("text", "MIN")
        spin(0.05)
        self.assertEqual(names(), ["font-Mine"])
        search.setProperty("text", "int")
        spin(0.05)
        self.click(self.item("font-Inter"))
        self.idle()
        self.assertEqual(self.sets(), [["fontFamily=Inter"]])
        self.assertFalse(popup.property("opened"))
        self.click(btn)
        self.item("fontSearch").setProperty("text", "")
        spin(0.05)
        self.click(self.item("font-bundled"))
        self.idle()
        self.assertEqual(self.sets()[-1], ["fontFamily="])
        self.assertEqual(btn.property("text"), "Bundled Inter")

    def test_font_text_field_without_list(self):
        self.loaded()
        self.b._put("fonts", [])                    # fc-list no disponible
        spin(0.05)
        self.show("clock")
        self.type_in(self.control("fontFamily", "text"), "Mine")
        self.idle()
        self.assertEqual(self.sets(), [["fontFamily=Mine"]])

    def test_avatar_row(self):
        self.loaded()
        self.show("users")
        row = self.item("field-avatar")
        self.assertTrue(row.isVisible())
        self.assertEqual(self.item("caption", row).property("text"),
                         "Choose a picture · without one, your initials are shown")
        self.assertFalse(self.item("removeAvatar", row).isVisible())
        pic = str(self.dir / "my pic.png")
        self.dialog("field-avatar", pic)
        self.idle()
        self.assertEqual(self.log("avatar", "set")[0][:3], ["avatar", "set", pic])
        img = self.item("avatarImage", row)
        self.assertTrue(wait(lambda: self.loaded_image(img)))
        self.assertTrue(self.item("removeAvatar", row).isVisible())
        self.assertEqual(self.item("message").property("text"), "Avatar saved")
        # Otra foto: AccountsService la guarda con el mismo nombre; la URL debe cambiar o se vería la anterior.
        first = img.property("source").toString()
        self.dialog("field-avatar", str(self.dir / "other.png"))
        self.idle()
        self.assertEqual(QUrl(first).toLocalFile(), QUrl(img.property("source").toString()).toLocalFile())
        self.assertNotEqual(img.property("source").toString(), first)
        self.click(self.item("removeAvatar", row))
        self.idle()
        self.assertEqual(self.log("avatar", "clear")[0][:2], ["avatar", "clear"])
        self.assertFalse(self.item("removeAvatar", row).isVisible())
        self.show("colors")
        self.assertFalse(row.isVisible())
        self.item("search").setProperty("text", "pict")
        spin(0.05)
        self.assertTrue(self.item("field-avatar").isVisible())
        self.assertEqual(self.item("pageTitle").property("text"), "1 result")

    def test_wallpaper_dialog(self):
        self.loaded()
        self.show("users")
        wall = str(self.dir / "wall paper.jpg")
        self.dialog("wallpaperRow", wall)
        self.idle()
        self.assertEqual(self.log("wallpaper", "set")[0][:3], ["wallpaper", "set", wall])
        self.assertEqual(self.control("background", "pathValue").property("text"), "user.png")

    # ---- fase 4: la pantalla de inicio (pkexec) --------------------------------------------------------------------
    def system_page(self) -> None:
        self.click(self.item("page-system"))
        self.idle()

    def text(self, name: str) -> str:
        return str(self.item(name).property("text"))

    def test_system_page_status(self):
        self.loaded()
        self.assertTrue(self.item("applyDot").isVisible())
        self.assertTrue(self.item("quickApply").isVisible())
        self.system_page()
        self.assertFalse(self.item("scroll").isVisible())
        self.assertEqual(self.text("installedText"), "Sumi SDDM 9.9.9 is installed")
        self.assertEqual(self.text("activeText"), "Your login screen uses “orbital”")
        self.assertTrue(self.text("syncText").startswith("Not applied yet"))
        self.assertTrue(self.item("apply").isEnabled())
        self.assertTrue(self.item("activate").isVisible())
        self.assertFalse(self.item("deactivate").isVisible())
        self.assertEqual(self.text("logText"), "Last login screen: Sumi started correctly")
        self.assertEqual(self.text("recoveryCommand"), "sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate")
        self.assertTrue(self.item("recoveryDoc").isVisible())
        self.assertFalse(self.item("quickApply").isVisible(), "en la página ya está el botón grande")
        self.assertEqual(self.log("system", "status")[-1], ["system", "status", "--json"])
        self.assertTrue(self.log("system", "log"))
        self.item("search").setProperty("text", "dim")
        spin(0.05)
        self.assertTrue(self.item("scroll").isVisible(), "buscar vuelve a los ajustes")

    def test_apply_from_the_page(self):
        self.loaded()
        self.system_page()
        self.click(self.item("apply"))
        self.idle()
        self.assertEqual(self.log("system", "apply"), [["system", "apply", "--json"]])
        self.assertEqual(self.text("message"), "Applied to the login screen")
        self.assertTrue(self.text("syncText").startswith("Applied"))
        self.assertFalse(self.item("apply").isEnabled())
        self.assertEqual(self.text("apply"), "Already applied", "no sólo con el gris de desactivado")
        self.assertFalse(self.item("applyDot").isVisible())

    def test_quick_apply_after_pending_writes(self):
        self.loaded(write_delay_ms=300)
        self.type_in(self.control("accentColor", "hex"), "#ff8800")
        self.click(self.item("quickApply"))
        self.idle()
        heads = [a[:2] for a in self.log() if a[:2] in (["config", "set"], ["system", "apply"])]
        self.assertEqual(heads, [["config", "set"], ["system", "apply"]], "se aplica lo que se ve")
        self.assertFalse(self.item("quickApply").isVisible())
        self.assertTrue(self.b.system["inSync"])

    def test_cancelled_password_changes_nothing(self):
        self.state(None, deny=True)
        self.loaded()
        self.system_page()
        self.click(self.item("apply"))
        self.idle()
        self.assertEqual(self.text("message"), "Authentication cancelled · nothing changed")
        self.assertTrue(self.text("syncText").startswith("Not applied yet"))
        self.click(self.item("activate"))
        self.click(self.item("activate"))
        self.idle()
        self.assertEqual(self.text("activeText"), "Your login screen uses “orbital”")

    def test_failed_probe_is_explained(self):
        self.state(None, sys_fail={"code": "probe", "error": "probe failed", "problems": ["Main.qml:12: boom"]})
        self.loaded()
        self.system_page()
        self.click(self.item("apply"))
        self.idle()
        self.assertEqual(self.text("message"),
                         "The theme failed its test with these settings · nothing changed · Main.qml:12: boom")

    def test_use_and_restore_need_two_presses(self):
        self.loaded()
        self.system_page()
        use = self.item("activate")
        self.click(use)
        self.assertEqual(use.property("text"), "Press again to use Sumi")
        self.assertIn("Makes Sumi your login screen the next time", self.text("switchHelp"))
        spin(0.1)
        self.assertEqual(self.log("system", "activate"), [])
        self.click(use)
        self.idle()
        self.assertEqual(self.text("message"), "Sumi will be your login screen the next time it appears")
        self.assertEqual(self.text("activeText"), "Sumi is your login screen")
        restore = self.item("deactivate")
        self.assertTrue(restore.isVisible())
        self.assertIn("Goes back to “orbital”", self.text("switchHelp"))
        self.click(restore)
        self.assertEqual(restore.property("text"), "Press again to restore")
        self.click(restore)
        self.idle()
        self.assertIn("Back to orbital", self.text("message"))
        self.assertEqual(len(self.log("system", "deactivate")), 1)
        self.assertEqual(self.text("activeText"), "Your login screen uses “orbital”")

    def test_not_installed(self):
        self.state(None, installed=False)
        self.loaded()
        self.assertFalse(self.item("quickApply").isVisible())
        self.system_page()
        self.assertTrue(self.text("notInstalled").startswith("The Sumi SDDM theme is not installed system-wide"))
        self.assertFalse(self.item("statusGrid").isVisible())
        self.assertFalse(self.item("apply").isVisible())
        self.assertFalse(self.item("activate").isVisible())

    def test_log_with_problems(self):
        self.state(None, log={"greeters": [{"pid": "1", "time": 0, "theme": "file:///x/sumi/", "sumi": True,
                                            "ok": False, "ready": "", "problems": ["no ready line", "QML error"]}]})
        self.loaded()
        self.system_page()
        self.assertEqual(self.text("logText"), "Last login screen: Sumi had problems")
        self.assertEqual(self.texts(self.item("logText").parentItem().parentItem())[-2:],
                         ["· no ready line", "· QML error"])

    def test_log_without_greeters(self):
        self.state(None, log=None)
        self.loaded()
        self.system_page()
        self.assertEqual(self.text("logText"), "No login screen has been shown since this computer started")

    def test_close_waits_for_the_system_change(self):
        self.state(None, delay={"apply": 0.6})
        self.loaded()
        self.system_page()
        self.click(self.item("apply"))
        self.assertTrue(self.item("busyRow").isVisible())
        self.win.close()
        spin(0.1)
        self.assertTrue(self.win.isVisible(), "no se cierra mientras pkexec espera o trabaja")
        self.assertEqual(self.text("message"), "The window will close when the login screen change finishes")
        self.assertTrue(wait(lambda: not self.win.isVisible(), 5))
        self.assertEqual(len(self.log("system", "apply")), 1)
        self.win = None

    def test_rejected_value_shown_next_to_its_field(self):
        self.state(None, reject={"dateFormat": "Some characters are not allowed here"})
        self.loaded()
        self.show("clock")
        self.type_in(self.control("dateFormat", "text"), "d MMM")   # pasa el filtro de la ventana; la CLI no
        self.idle()
        cap = self.control("dateFormat", "caption")
        self.assertEqual(cap.property("text"), "Some characters are not allowed here")
        self.assertEqual(self.text("message"), "1 setting was not saved · see the field")
        self.assertEqual(self.control("dateFormat", "text").property("text"), "dddd, d MMMM", "lo guardado")
        self.state(None, reject={})
        self.type_in(self.control("dateFormat", "text"), "d MMMM")
        self.idle()
        self.assertEqual(cap.property("text"), "")

    def test_close_writes_pending_changes_first(self):
        self.loaded(write_delay_ms=5000)
        self.type_in(self.control("accentColor", "hex"), "#123456")
        self.assertEqual(self.sets(), [])
        self.win.close()
        self.assertTrue(self.win.isVisible(), "no se cierra con una escritura pendiente")
        self.assertTrue(wait(lambda: not self.win.isVisible(), 5))
        self.assertEqual(self.sets(), [["accentColor=#123456"]])
        self.win = None


class RealCliCase(WindowCase):
    """La CLI del repositorio con la configuración en un directorio temporal (nunca la del usuario)."""

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


@unittest.skipIf(QGuiApplication is None, "PySide6 no está instalado")
class EditorUiRealCliTest(RealCliCase):
    """Criterios de salida de las fases 2 y 3 con la CLI del repositorio."""

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

    def test_path_shows_its_help(self):
        """Como la ventana de Sumi Shell: la fila del fondo enseña la ayuda del esquema."""
        self.open(program=str(CLI))
        self.ready()
        self.show("background")
        self.assertEqual(self.control("background", "caption").property("text"), self.b.keys["background"]["help"])
        self.assertTrue(self.control("background", "caption").isVisible())

    def test_preview_reflects_each_change(self):
        """La vista previa real (qml offscreen) cambia con lo guardado: el color base se ve en la esquina."""
        self.open(program=str(CLI), preview_timeout_ms=120_000)
        self.b.previewSize = "640x360"
        self.ready()

        def corner() -> tuple[int, int, int]:
            png = QUrl(self.b.previewUrl).toLocalFile()
            c = QImage(png).pixelColor(3, 3)
            return c.red(), c.green(), c.blue()

        self.assertTrue(wait(lambda: self.b.previewUrl and not self.b.previewStale, 60), self.b.error)
        for colour, channel in (("#ff0000", 0), ("#00ff00", 1)):
            before = self.b.previewUrl
            self.type_in(self.control("backgroundColor", "hex"), colour)
            self.assertTrue(wait(lambda: self.b.previewUrl != before and not self.b.previewStale
                                 and self.quiet(), 60), self.b.error)
            rgb = corner()
            self.assertEqual(max(range(3), key=lambda i: rgb[i]), channel, (colour, rgb))
        self.assertEqual(self.saved(), {"backgroundColor": "#00ff00"})



def cpp(obj) -> int:
    """Identidad del objeto C++ (PySide puede dar envoltorios distintos para el mismo elemento)."""
    import shiboken6
    return shiboken6.getCppPointer(obj)[0]


def luminance(c) -> float:
    def ch(v: float) -> float:
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c.redF()) + 0.7152 * ch(c.greenF()) + 0.0722 * ch(c.blueF())


def contrast(a, b) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


@unittest.skipIf(QGuiApplication is None, "PySide6 no está instalado")
class EditorUiAccessTest(RealCliCase):
    """Fase 5 con el esquema real (todas las claves): nombres accesibles, teclado y tema claro/oscuro."""

    INTERACTIVE = {QAccessible.Role.Button, QAccessible.Role.CheckBox, QAccessible.Role.Slider,
                   QAccessible.Role.ComboBox, QAccessible.Role.EditableText, QAccessible.Role.RadioButton,
                   QAccessible.Role.PageTab, QAccessible.Role.ListItem, QAccessible.Role.SpinBox} \
        if QGuiApplication is not None else set()

    def controls(self):
        """Cada control visible y activo, con su interfaz accesible."""
        for it in self.items(self.win.contentItem()):
            if not (it.isVisible() and it.isEnabled() and it.opacity() > 0):
                continue
            acc = QAccessible.queryAccessibleInterface(it)
            if acc is not None and acc.role() in self.INTERACTIVE and it.property("focusPolicy") is not None:
                yield it, acc

    def pages(self):
        """Cada grupo del esquema y la página del sistema, una a una."""
        for g in self.b.groups:
            self.show(g["id"])
            spin(0.05)
            yield g["id"]
        self.click(self.item("page-system"))
        self.idle()
        yield "system"

    def test_every_control_has_a_name(self):
        self.open(program=str(CLI))
        self.ready()
        missing, seen = [], 0
        for page in self.pages():
            for it, acc in self.controls():
                seen += 1
                if not acc.text(QAccessible.Text.Name).strip():
                    missing.append(f"{page}: {it.objectName() or it.metaObject().className()}")
        self.assertGreater(seen, 100)
        self.assertEqual(missing, [])

    def test_every_control_is_reachable_with_tab(self):
        # La cadena de Tab se recorre en QML: los envoltorios que PySide crea para nextItemInFocusChain acaban en
        # un segfault en la recolección final de Python (shiboken los invalida sobre memoria ya liberada).
        from PySide6.QtCore import QByteArray
        from PySide6.QtQml import QQmlComponent
        self.open(program=str(CLI))
        self.ready()
        comp = QQmlComponent(self.engine)
        comp.setData(QByteArray(b"""import QtQuick
QtObject {
    function outside(start, controls) {
        const seen = new Set();
        let it = start;
        for (let i = 0; i < 5000 && it; i++) {
            seen.add(it);
            it = it.nextItemInFocusChain(true);
            if (it === start) break;
        }
        return controls.filter(c => !seen.has(c)).map(c => c.objectName || c.toString()).join(", ");
    }
}"""), QUrl())
        walker = comp.create()
        self.assertIsNotNone(walker, comp.errorString())
        for page in self.pages():
            controls = [x for x, _acc in self.controls()]       # todos, no sólo los que ya aceptan Tab
            self.assertGreater(len(controls), 3, page)
            out = QMetaObject.invokeMethod(walker, "outside", Q_RETURN_ARG("QVariant"),
                                           Q_ARG("QVariant", self.item("search")), Q_ARG("QVariant", controls))
            self.assertEqual(out, "", page)

    def test_keyboard_switches_pages(self):
        self.open(program=str(CLI))
        self.ready()
        clock = self.item("group-clock")
        clock.forceActiveFocus()
        self.key(clock, Qt.Key.Key_Space)
        self.assertEqual(self.item("pageTitle").property("text"), "Clock")
        sysitem = self.item("page-system")
        sysitem.forceActiveFocus()
        self.key(sysitem, Qt.Key.Key_Space)
        self.idle()
        self.assertTrue(self.item("installedText").isVisible() or self.item("notInstalled").isVisible())

    def test_focus_scrolls_to_the_focused_setting(self):
        self.open(program=str(CLI))
        self.ready()
        self.win.resize(360, 420)
        self.win.setProperty("selectedGroup", "clock")
        spin(0.25)
        scroll = self.item("scroll")
        field = self.control("clockOffsetY", "number")
        self.assertGreater(field.mapToItem(scroll, QPointF()).y(), scroll.height())
        field.forceActiveFocus(Qt.FocusReason.TabFocusReason)
        spin(0.1)
        top = field.mapToItem(scroll, QPointF()).y()
        self.assertGreaterEqual(top, 0)
        self.assertLessEqual(top + field.height(), scroll.height())

    def test_every_schema_group_fits_at_each_window_size(self):
        self.open(program=str(CLI))
        self.ready()
        self.win.setProperty("reduceMotion", True)
        self.assertEqual(self.win.property("tones").property("duration"), 0)
        for width, height in ((360, 420), (640, 480), (1024, 680), (1180, 700), (1440, 860)):
            self.win.resize(width, height)
            for group in self.b.groups:
                group_id = group["id"]
                self.win.setProperty("selectedGroup", group_id)
                spin(0.045)
                fields = self.visible_items("field-")
                expected = {"field-" + key for key in self.b.order if self.b.keys[key]["group"] == group_id}
                if group_id == "users":
                    expected.add("field-avatar")
                self.assertEqual({field.objectName() for field in fields}, expected)
                for field in fields:
                    for control in self.items(field):
                        if not control.isVisible() or control.property("focusPolicy") is None:
                            continue
                        left = control.mapToItem(field, QPointF()).x()
                        right = left + control.width()
                        context = (width, group_id, field.objectName(), control.objectName())
                        self.assertGreaterEqual(left, -1, context)
                        self.assertLessEqual(right, field.width() + 1, context)

    def tones(self) -> dict:
        t = self.win.property("tones")
        return {k: t.property(k) for k in ("dark", "error", "pending", "window")}

    def test_light_and_dark(self):
        # Lo que hacen KDE, GNOME (su tema de plataforma) o qt6ct: dar a la aplicación una paleta clara u oscura,
        # también con la ventana abierta (quien cambia el modo del escritorio con el editor en marcha). Fusion y
        # los tonos propios (Tones) deben seguirla. Offscreen no tiene tema de plataforma: se fija la paleta.
        from PySide6.QtGui import QPalette
        self.open(program=str(CLI))
        self.ready()
        try:
            for base, dark in (("#2b2d31", True), ("#efefef", False)):
                QGuiApplication.setPalette(QPalette(QColor(base)))
                spin(0.1)
                t = self.tones()
                self.assertEqual(t["dark"], dark, base)
                img = self.win.grabWindow()
                bg = img.pixelColor(img.width() // 2, img.height() // 2)
                self.assertEqual(luminance(bg) < 0.2, dark, (base, bg.name()))
                for k in ("error", "pending"):
                    self.assertGreaterEqual(contrast(t[k], t["window"]), 4.5, (base, k, t[k].name()))
        finally:
            QGuiApplication.setPalette(QPalette())

if __name__ == "__main__":
    unittest.main()

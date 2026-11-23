"""Backend del editor (editor/sumi_sddm_editor/backend.py) contra una `sumi-sddm` falsa (fake_sumi_sddm.py).

Sin ventana: QCoreApplication y el bucle de eventos a mano. Se salta si PySide6 no está instalado (el tema no lo
necesita; sólo el paquete del editor).
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "editor"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from qt_support import QGuiApplication as QCoreApplication, app  # noqa: E402  (None sin PySide6)

if QCoreApplication is not None:
    from PySide6.QtCore import QEventLoop, QProcess, QUrl
    from sumi_sddm_editor.backend import Backend, enum_label, local_path, raw_value

FAKE = Path(__file__).resolve().parent / "fake_sumi_sddm.py"


@unittest.skipIf(QCoreApplication is None, "PySide6 no está instalado")
class EditorBackendTest(unittest.TestCase):
    def setUp(self):
        app()
        self._tmp = tempfile.TemporaryDirectory(prefix="sumi-editor-")
        self.dir = Path(self._tmp.name)
        exe = self.dir / "sumi-sddm"
        exe.write_text(f"#!{sys.executable} -IB\n" + FAKE.read_text())
        exe.chmod(0o755)
        self.exe = str(exe)
        self.state({})
        self._path = os.environ.get("PATH", "")
        os.environ["PATH"] = f"{self.dir}:{self._path}"
        self.backends = []

    def tearDown(self):
        os.environ["PATH"] = self._path
        for b in self.backends:          # que no queden procesos colgando de un objeto ya destruido
            self.wait(lambda: not b.busy and b.systemBusy == "", 5)
            b.deleteLater()
        self.spin(0.05)
        self._tmp.cleanup()

    # ---- ayudas ------------------------------------------------------------------------------------------------------
    def state(self, st: dict | None = None, **update) -> dict:
        p = self.dir / "state.json"
        cur = json.loads(p.read_text()) if st is None else st
        cur.update(update)
        p.write_text(json.dumps(cur))
        return cur

    def log(self) -> list[list[str]]:
        p = self.dir / "log.jsonl"
        return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []

    def calls(self, *prefix: str) -> list[list[str]]:
        return [a for a in self.log() if a[:len(prefix)] == list(prefix)]

    def spin(self, seconds: float) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 20)
            time.sleep(0.002)

    def wait(self, cond, timeout: float = 10) -> bool:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if cond():
                return True
            app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 20)
            time.sleep(0.002)
        return cond()

    def make(self, **kw) -> Backend:
        kw.setdefault("write_delay_ms", 40)
        kw.setdefault("preview_delay_ms", 60)
        kw.setdefault("disarm_ms", 4000)
        b = Backend(**kw)
        self.backends.append(b)
        return b

    @staticmethod
    def quiet(b: Backend) -> bool:
        # `busy` no cuenta la vista previa programada (como en Settings): aquí sí se espera a ella.
        return not b.busy and b.systemBusy == "" and not b._preview_timer.isActive() \
            and not b._apply_retry.isActive()

    def loaded(self, **kw) -> Backend:
        b = self.make(**kw)
        b.load()
        self.assertTrue(self.wait(lambda: b.ready and self.quiet(b)), (b.status, b.statusDetail))
        return b

    def idle(self, b: Backend) -> None:
        self.assertTrue(self.wait(lambda: self.quiet(b)), "el backend no quedó quieto")

    # ---- carga -------------------------------------------------------------------------------------------------------
    def test_load(self):
        b = self.loaded()
        self.assertEqual(b.version, "9.9.9")
        self.assertEqual([g["id"] for g in b.groups], ["colors", "clock", "users"])
        self.assertEqual(b.order[:2], ["accentColor", "dim"])
        self.assertEqual(b.values["accentColor"], {"value": "#a9bdff", "default": "#a9bdff", "set": False})
        self.assertEqual(len(b.stamp), 32)
        self.assertEqual([f["family"] for f in b.fonts], ["Inter", "Mine"])
        self.assertTrue(b.system["installed"])
        self.assertFalse(b.avatar["exists"])
        self.assertTrue(b.previewUrl.startswith("file://") and b.previewUrl.endswith("?v=1"))
        self.assertFalse(b.previewStale)
        self.assertEqual(b.customCount, 0)
        heads = [a[:2] if a[0] in ("config", "system", "avatar") else a[:1] for a in self.log()]
        self.assertEqual(heads[:3], [["version"], ["config", "schema"], ["config", "show"]])
        self.assertTrue(all(a[-1] == "--json" for a in self.log()))

    def test_missing_in_path(self):
        os.environ["PATH"] = "/nonexistent"
        b = self.make()
        b.load()
        self.assertEqual(b.status, "missing")
        self.assertEqual(self.log(), [])

    def test_missing_program_fails_to_start(self):
        b = self.make(program=str(self.dir / "nope"))
        b.load()
        self.assertTrue(self.wait(lambda: b.status == "missing"), b.status)

    def test_incompatible_api(self):
        self.state(None, api=2)
        b = self.make()
        b.load()
        self.assertTrue(self.wait(lambda: b.status == "incompatible"))
        self.assertIn("version 2", b.statusDetail)
        self.assertEqual(len(self.log()), 1, "no sigue hablando con una CLI de otro api")

    def test_garbage_is_broken_with_stderr(self):
        self.state(None, garbage=True)
        b = self.make()
        b.load()
        self.assertTrue(self.wait(lambda: b.status == "broken"))
        self.assertEqual(b.statusDetail, "something broke")

    def test_timeout(self):
        self.state(None, delay={"version": 3})
        b = self.make(job_timeout_ms=300)
        t0 = time.monotonic()
        b.load()
        self.assertTrue(self.wait(lambda: b.status == "broken", 5))
        self.assertLess(time.monotonic() - t0, 2.5)
        self.assertEqual(b.statusDetail, "sumi-sddm did not answer in time")
        self.assertFalse(b.busy)

    # ---- escribir ----------------------------------------------------------------------------------------------------
    def test_grouped_write_with_expect(self):
        b = self.loaded()
        stamp = b.stamp
        b.set("accentColor", "#ff8800")
        b.set("showClock", False)
        b.set("blur", 15.6)
        b.set("dim", 0.12345)
        # la vista cambia al momento, antes de escribir
        self.assertEqual(b.values["accentColor"]["value"], "#ff8800")
        self.assertTrue(b.values["showClock"]["set"])
        self.assertTrue(b.busy)
        self.idle(b)
        sets = self.calls("config", "set")
        self.assertEqual(sets, [["config", "set", "accentColor=#ff8800", "showClock=false", "blur=16", "dim=0.123",
                                 "--expect", stamp, "--json"]])
        self.assertEqual(b.writeCount, 1)
        self.assertNotEqual(b.stamp, stamp)
        self.assertEqual(b.values["blur"]["value"], 16)
        self.assertEqual(b.customCount, 4)
        self.assertFalse(b.system["inSync"], "después de escribir se relee system status")

    def test_unset_sends_empty_value(self):
        self.state(None, values={"clockFormat": "12h"})
        b = self.loaded()
        self.assertTrue(b.isSet("clockFormat"))
        b.unset("clockFormat")
        self.assertEqual(b.values["clockFormat"]["value"], "24h")
        self.idle(b)
        self.assertEqual(self.calls("config", "set")[-1][:3], ["config", "set", "clockFormat="])
        self.assertFalse(b.isSet("clockFormat"))

    def test_write_while_previous_write_runs_is_regrouped(self):
        self.state(None, delay={"set": 0.4})
        b = self.loaded()
        b.set("accentColor", "#111111")
        self.assertTrue(self.wait(lambda: self.calls("config", "set")))
        b.set("accentColor", "#222222")
        b.set("dim", 0.5)
        self.idle(b)
        sets = [a[2:-3] for a in self.calls("config", "set")]
        self.assertEqual(sets, [["accentColor=#111111"], ["accentColor=#222222", "dim=0.5"]])
        self.assertEqual(b.values["accentColor"]["value"], "#222222")
        self.assertEqual(b.writeCount, 2)

    def test_conflict_reloads_and_keeps_outside_change(self):
        b = self.loaded()
        self.state(None, values={"clockFormat": "12h"})       # alguien, desde la terminal
        b.set("accentColor", "#ff8800")
        self.idle(b)
        self.assertEqual(b.notice, "Changed outside the editor · reloaded")
        self.assertEqual(b.values["clockFormat"]["value"], "12h")
        self.assertEqual(b.values["accentColor"]["value"], "#a9bdff", "lo enviado no se guardó")
        self.assertEqual(b.writeCount, 0)
        self.assertEqual(json.loads((self.dir / "state.json").read_text())["values"], {"clockFormat": "12h"})

    def test_conflict_drops_later_pending_changes(self):
        # Lo que se tocó mientras viajaba la escritura rechazada se hizo sobre una base que ya no vale.
        b = self.loaded()
        self.state(None, values={"clockFormat": "12h"}, delay={"set": 0.3})
        b.set("accentColor", "#ff8800")
        self.assertTrue(self.wait(lambda: self.calls("config", "set")))
        b.set("dim", 0.9)
        self.idle(b)
        self.spin(0.1)
        self.assertEqual(len(self.calls("config", "set")), 1, "lo pendiente no se escribe sobre la base nueva")
        self.assertEqual(b.values["dim"]["value"], 0.4)
        self.assertEqual(b.notice, "Changed outside the editor · reloaded")

    def test_recheck_announces_outside_change(self):
        b = self.loaded()
        b.recheck()
        self.idle(b)
        self.assertEqual(b.notice, "")
        self.state(None, values={"showClock": False})
        b.recheck()
        self.idle(b)
        self.assertEqual(b.notice, "Changed outside the editor · reloaded")
        self.assertIs(b.values["showClock"]["value"], False)

    def test_busy_error_is_reported(self):
        self.state(None, busy_next=1)
        b = self.loaded()
        b.set("dim", 0.3)
        self.idle(b)
        self.assertEqual(b.error, "another sumi-sddm operation is running")
        self.assertEqual(b.values["dim"]["value"], 0.4)

    def test_arguments_reach_the_cli_intact(self):
        b = self.loaded()
        weird = str(self.dir / "my pics" / "it's \"$HOME\"; rm -rf ~ `x` *.png")
        b.setWallpaper(weird)
        self.idle(b)
        self.assertEqual(self.calls("wallpaper", "set")[-1][:3], ["wallpaper", "set", weird])
        b.setWallpaper("file:///tmp/a%20b%23c.jpg")
        self.idle(b)
        self.assertEqual(self.calls("wallpaper", "set")[-1][2], "/tmp/a b#c.jpg")
        self.assertEqual(b.values["background"]["value"], "backgrounds/user.png")

    def test_reset_needs_two_presses_and_restore(self):
        self.state(None, values={"dim": 0.7})
        b = self.loaded()
        b.resetAll()
        self.assertTrue(b.resetArmed)
        self.spin(0.1)
        self.assertEqual(self.calls("config", "reset"), [])
        b.resetAll()
        self.idle(b)
        self.assertFalse(b.resetArmed)
        self.assertEqual(len(self.calls("config", "reset")), 1)
        self.assertEqual(b.customCount, 0)
        b.restorePrevious()
        self.idle(b)
        self.assertEqual(b.values["dim"]["value"], 0.7)

    def test_arm_expires(self):
        self.state(None, values={"dim": 0.7})
        b = self.loaded(disarm_ms=100)
        b.resetAll()
        self.assertTrue(self.wait(lambda: not b.resetArmed, 2))
        b.resetAll()
        self.spin(0.1)
        self.assertEqual(self.calls("config", "reset"), [], "tras caducar, vuelve a ser la primera pulsación")

    # ---- cola --------------------------------------------------------------------------------------------------------
    def test_queue_does_not_repeat_loads(self):
        b = self.loaded()
        self.state(None, delay={"preview": 0.4})
        n = len(self.calls("preview"))
        b.schedulePreview()
        self.assertTrue(self.wait(lambda: len(self.calls("preview")) == n + 1))
        before = len(self.calls("config", "show"))
        for _ in range(5):
            b.reload()
        b.refreshSystem()
        b.refreshSystem()
        self.idle(b)
        self.assertEqual(len(self.calls("config", "show")) - before, 1)

    def test_one_process_at_a_time(self):
        self.state(None, delay={"show": 0.15, "status": 0.15, "info": 0.15, "fonts": 0.15, "preview": 0.15})
        b = self.make()
        b.load()
        peak = 0
        end = time.monotonic() + 10
        while time.monotonic() < end and not (b.ready and not b.busy):
            app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 10)
            running = [p for p in b.findChildren(QProcess) if p.state() != QProcess.ProcessState.NotRunning]
            peak = max(peak, len(running))
            time.sleep(0.005)
        self.assertTrue(b.ready)
        self.assertEqual(peak, 1)

    # ---- vista previa ------------------------------------------------------------------------------------------------
    def test_preview_follows_saved_changes(self):
        b = self.loaded()
        first = b.previewUrl
        b.set("accentColor", "#00ff00")
        self.assertTrue(b.previewStale or b.busy)
        self.idle(b)
        log = self.log()
        i_set = max(i for i, a in enumerate(log) if a[:2] == ["config", "set"])
        i_prev = max(i for i, a in enumerate(log) if a[0] == "preview")
        self.assertGreater(i_prev, i_set, "se previsualiza lo guardado")
        self.assertNotEqual(b.previewUrl, first)
        self.assertEqual(b.previewStamp, b.stamp)
        self.assertFalse(b.previewStale)
        self.assertEqual(log[i_prev][:5], ["preview", "--scenario", "expanded", "--size", "1280x720"])

    def test_preview_waits_for_slow_writes(self):
        # La escritura agrupada tarda más que la vista previa: aun así se previsualiza lo guardado.
        b = self.loaded(write_delay_ms=300, preview_delay_ms=30)
        n = len(self.calls("preview"))
        b.set("accentColor", "#00ff00")
        b.schedulePreview()
        self.spin(0.2)
        self.assertEqual(len(self.calls("preview")), n, "ninguna vista previa con cambios sin guardar")
        self.idle(b)
        self.assertEqual(b.previewStamp, b.stamp)

    def test_reload_keeps_pending_changes_on_top(self):
        b = self.loaded(write_delay_ms=400)
        b.set("accentColor", "#00ff00")
        b.unset("dim")
        b.reload()
        self.assertTrue(self.wait(lambda: len(self.calls("config", "show")) >= 2 and not b._running))
        self.assertEqual(self.calls("config", "set"), [], "la recarga llegó antes de escribir")
        self.assertEqual(b.values["accentColor"], {"value": "#00ff00", "default": "#a9bdff", "set": True})
        self.assertFalse(b.values["dim"]["set"])
        self.idle(b)
        self.assertEqual(self.calls("config", "set")[0][2:4], ["accentColor=#00ff00", "dim="])

    def test_scenario_and_size_change_the_preview(self):
        b = self.loaded()
        b.scenario = "failed"
        self.assertTrue(b.previewStale)
        b.previewSize = "800x600"
        self.idle(b)
        self.assertEqual(self.calls("preview")[-1][:5], ["preview", "--scenario", "failed", "--size", "800x600"])
        self.assertFalse(b.previewStale)

    def test_preview_disabled(self):
        b = self.make()
        b.previewEnabled = False
        b.load()
        self.assertTrue(self.wait(lambda: b.ready and self.quiet(b)))
        self.spin(0.15)
        self.assertEqual(self.calls("preview"), [])

    # ---- sistema -----------------------------------------------------------------------------------------------------
    def test_apply_waits_for_pending_writes(self):
        b = self.loaded()
        b.set("dim", 0.6)
        b.systemApply()
        self.assertEqual(b.systemBusy, "", "no se aplica con escrituras pendientes")
        self.idle(b)
        self.assertTrue(self.wait(lambda: b.notice == "Applied to the login screen" and b.systemBusy == ""))
        log = self.log()
        i_set = next(i for i, a in enumerate(log) if a[:2] == ["config", "set"])
        i_apply = next(i for i, a in enumerate(log) if a[:2] == ["system", "apply"])
        self.assertLess(i_set, i_apply)
        self.assertEqual(log[i_apply], ["system", "apply", "--json"])
        self.idle(b)
        self.assertTrue(b.system["inSync"])

    def test_system_runs_beside_the_queue(self):
        self.state(None, delay={"apply": 1.0})
        b = self.loaded()
        b.systemApply()
        self.assertEqual(b.systemBusy, "apply")
        before = len(self.calls("config", "show"))
        b.reload()
        self.assertTrue(self.wait(lambda: len(self.calls("config", "show")) > before and not b.busy, 0.9))
        self.assertEqual(b.systemBusy, "apply", "la cola siguió mientras se esperaba a polkit")
        self.idle(b)

    def test_denied(self):
        self.state(None, deny=True)
        b = self.loaded()
        b.systemApply()
        self.idle(b)
        self.assertEqual(b.notice, "Authentication cancelled · nothing changed")
        self.assertEqual(b.error, "")

    def test_activate_and_deactivate_need_two_presses(self):
        b = self.loaded()
        b.activateSystem()
        self.assertTrue(b.activateArmed)
        self.assertEqual(b.systemBusy, "")
        b.activateSystem()
        self.idle(b)
        self.assertEqual(b.notice, "Sumi will be your login screen the next time it appears")
        self.assertTrue(b.system["active"])
        b.activateSystem()                       # ya activo: nada
        self.assertFalse(b.activateArmed)
        b.deactivateSystem()
        b.deactivateSystem()
        self.idle(b)
        self.assertIn("Back to orbital", b.notice)
        self.assertFalse(b.system["active"])

    def test_try_window_two_presses(self):
        b = self.loaded()
        b.openTestWindow()
        self.spin(0.2)
        self.assertEqual(self.calls("try"), [])
        b.openTestWindow()
        self.assertTrue(self.wait(lambda: self.calls("try")))
        self.assertEqual(self.calls("try")[0], ["try", "--yes"])

    # ---- avatar y formulario ---------------------------------------------------------------------------------------
    def test_avatar(self):
        b = self.loaded()
        self.assertEqual(b.captionFor("avatar"), "Choose a picture · without one, your initials are shown")
        b.setAvatar("~/pic.png")
        self.idle(b)
        self.assertEqual(self.calls("avatar", "set")[0][2], os.path.expanduser("~/pic.png"))
        self.assertTrue(b.isSet("avatar"))
        self.assertEqual(b.notice, "Avatar saved")
        changes = []
        b.avatarChanged.connect(lambda: changes.append(1))
        b.setAvatar("~/other.png")                   # mismo iconFile en la respuesta
        self.idle(b)
        self.assertEqual(len(changes), 1, "otra foto con el mismo nombre también es un cambio")
        b.unset("avatar")
        self.idle(b)
        self.assertFalse(b.isSet("avatar"))

    def test_captions_and_warnings(self):
        self.state(None, warnings=[{"key": "fontFamily", "message": "Only in your home folder"}])
        b = self.loaded()
        self.assertEqual(b.captionFor("accentColor"), "Focus rings")
        self.assertEqual(b.captionFor("fontFamily"), "Only in your home folder")
        self.assertEqual(b.captionFor("dim"), "")

    def test_keyboard_steps(self):
        b = self.loaded()
        b.step("showClock", 0)
        self.assertIs(b.valueOf("showClock"), False)
        b.step("clockFormat", 1)
        self.assertEqual(b.valueOf("clockFormat"), "12h")
        b.step("clockFormat", 1)
        self.assertEqual(b.valueOf("clockFormat"), "24h")
        b.step("blur", 1)                        # allowZero: 0 → min
        self.assertEqual(b.valueOf("blur"), 8)
        b.step("blur", -1)
        self.assertEqual(b.valueOf("blur"), 0)
        b.step("dim", 1)
        self.assertAlmostEqual(b.valueOf("dim"), 0.45)
        self.idle(b)
        self.assertEqual(len(self.calls("config", "set")), 1, "todos los pasos en una escritura")


class HelpersTest(unittest.TestCase):
    @unittest.skipIf(QCoreApplication is None, "PySide6 no está instalado")
    def test_raw_value(self):
        self.assertEqual(raw_value({"type": "bool"}, True), "true")
        self.assertEqual(raw_value({"type": "integer"}, 2.5), "3")       # como Math.round de JS
        self.assertEqual(raw_value({"type": "integer"}, -2.5), "-2")
        self.assertEqual(raw_value({"type": "number"}, 2.0), "2")
        self.assertEqual(raw_value({"type": "number"}, 0.1 + 0.2), "0.3")
        self.assertEqual(raw_value({"type": "color"}, "#AARRGGBB"), "#AARRGGBB")

    @unittest.skipIf(QCoreApplication is None, "PySide6 no está instalado")
    def test_local_path_and_labels(self):
        self.assertEqual(local_path("file:///a/b%20c.png"), "/a/b c.png")
        self.assertEqual(local_path(" ~/x "), os.path.expanduser("~/x"))
        self.assertEqual(local_path("rel/x"), "rel/x")
        self.assertEqual(local_path(QUrl.fromLocalFile("/a b/c#d.png")), "/a b/c#d.png")
        self.assertEqual(enum_label("top-left"), "Top left")
        self.assertEqual(enum_label("24h"), "24 h")


if __name__ == "__main__":
    unittest.main()

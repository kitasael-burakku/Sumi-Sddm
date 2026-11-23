"""Contrato JSON de la CLI (docs/CLI-JSON.md), huella/--expect, bloqueo, fuentes e instalación de usuario.

Todo en un HOME temporal (HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME, XDG_DATA_HOME propios).
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "tools" / "sumi-sddm"
MAGICK = shutil.which("magick")
STAMP_RE = re.compile(r"^[0-9a-f]{32}$")


SPANISH_RE = re.compile(r"[áéíóúñ¿¡«»]|\b(no se|fuera de|se esperaba|clave|archivo|línea)\b", re.I)


def assert_english(t: unittest.TestCase, doc: dict) -> None:
    """Todo error JSON lleva `message` en inglés (para interfaces); `fields`, si está, también."""
    t.assertIsInstance(doc.get("message"), str, doc)
    t.assertTrue(doc["message"].strip(), doc)
    t.assertNotRegex(doc["message"], SPANISH_RE, doc)
    for f in doc.get("fields", []):
        t.assertEqual(set(f), {"key", "message"}, doc)
        t.assertNotRegex(f["message"], SPANISH_RE, doc)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "cfg"),
                        XDG_CACHE_HOME=str(self.home / "cache"), XDG_DATA_HOME=str(self.home / "data"))
        self.cfg = self.home / "cfg" / "sumi-sddm"
        self.conf = self.cfg / "theme.conf.user"

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, exe=None, rc=None):
        cmd = [exe] if exe else [sys.executable, "-B", str(CLI)]
        p = subprocess.run([*cmd, *args], env=self.env, capture_output=True, text=True, timeout=120)
        if rc is not None:
            self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return p

    def ok(self, *args, exe=None):
        p = self.run_cli(*args, "--json", exe=exe, rc=0)
        doc = json.loads(p.stdout)
        self.assertIs(doc["ok"], True)
        self.assertEqual(doc["api"], 1)
        return doc

    def err(self, code, *args, exe=None):
        p = self.run_cli(*args, "--json", exe=exe, rc=1)
        doc = json.loads(p.stdout)
        self.assertEqual((doc["ok"], doc["api"], doc["code"]), (False, 1, code), doc)
        self.assertIsInstance(doc["error"], str)
        assert_english(self, doc)
        return doc

    def stamp(self):
        return self.ok("config", "show")["stamp"]


class EnvelopeTest(Base):
    def test_version(self):
        d = self.ok("version")
        self.assertEqual(d["version"], (ROOT / "VERSION").read_text().strip())
        self.assertEqual((d["schema"], d["kind"]), (1, "checkout"))

    def test_show_schema_get_shapes(self):
        show = self.ok("config", "show")
        self.assertTrue(STAMP_RE.match(show["stamp"]))
        self.assertEqual(show["warnings"], [])
        for k, v in show["values"].items():
            self.assertEqual(set(v), {"value", "default", "set"}, k)
        sch = self.ok("config", "schema")
        self.assertNotIn("$comment", sch)
        self.assertEqual({g["id"] for g in sch["groups"]}, {e["group"] for e in sch["keys"]})
        self.assertEqual(set(show["values"]), {e["key"] for e in sch["keys"]})
        for e in sch["keys"]:
            self.assertTrue({"key", "group", "type", "default", "label"} <= set(e), e["key"])
        self.assertEqual(set(self.ok("config", "get", "notchRadius")), {"ok", "api", "key", "value", "set"})
        self.assertEqual(self.ok("config", "path")["path"], str(self.conf))

    def test_error_codes(self):
        self.err("invalid", "config", "set", "notchRadius=banana")
        self.err("invalid", "config", "unset", "noSuchKey")
        self.err("missing", "config", "restore")
        self.cfg.mkdir(parents=True, exist_ok=True)   # una escritura fallida ya creó el directorio (.lock)
        self.conf.write_text("[General]\nnotchRadius=banana\n")
        self.err("invalid", "config", "show")

    def test_validation_errors_per_field(self):
        d = self.err("invalid", "config", "set", "dateFormat=%%", "accentColor=red", "notchRadius=99",
                     "notchIdleCollapse=2", "clockFormat=12h")
        self.assertEqual(d["fields"], [
            {"key": "dateFormat", "message": "Some characters are not allowed here"},
            {"key": "accentColor", "message": "Expected a colour like #rrggbb or #aarrggbb"},
            {"key": "notchRadius", "message": "Use a value between 4 and 48"},
            {"key": "notchIdleCollapse", "message": "Use a value between 5 and 600, or 0 to turn it off"},
        ])
        self.assertTrue(d["message"].startswith("dateFormat: Some characters"), d)
        self.assertIn("fuera de rango (4–48)", d["error"], "la terminal sigue en español")
        self.assertFalse(self.conf.exists(), "todo o nada: la clave válida tampoco se escribe")
        p = self.run_cli("config", "set", "accentColor=red", rc=1)
        self.assertIn("se esperaba un color", p.stderr)

    def test_every_type_explains_itself_in_english(self):
        cases = {"dimOpacity=x": "Expected a number", "dimOpacity=2": "Use a value between 0 and 0.85",
                 "avatarSize=4.5": "Expected a whole number", "userNames=maybe": "Expected true or false",
                 "clockFormat=36h": "Allowed values: 24h, 12h", "fontFamily=" + "a" * 80: "Too long (at most 64 characters)",
                 "background=/etc/x.png": "Choose the image with “wallpaper set”, or use an image under /usr/share",
                 "background=../x.png": "This path is not allowed", "accentColor=@x": "A value can't start with “@”"}
        for pair, msg in cases.items():
            d = self.err("invalid", "config", "set", pair)
            self.assertEqual(d["fields"], [{"key": pair.split("=")[0], "message": msg}], pair)

    def test_unknown_key_and_malformed_pair(self):
        d = self.err("invalid", "config", "set", "accentColr=#ffffff")
        self.assertEqual(d["fields"], [{"key": "accentColr", "message": "Unknown setting; did you mean “accentColor”?"}])
        d = self.err("invalid", "config", "set", "nope")
        self.assertEqual(d["message"], "“nope”: expected KEY=VALUE")
        self.assertNotIn("fields", d)

    def test_non_field_errors_in_english(self):
        self.assertEqual(self.err("missing", "config", "restore")["message"],
                         "There is no earlier copy to restore (it is made by “Reset all”)")
        bad = self.home / "bad.png"
        bad.write_text("x")
        self.assertEqual(self.err("invalid", "wallpaper", "set", str(bad))["message"],
                         "The file is too small to be an image")
        p = self.run_cli("preview", "--size", "9x9", "--json", rc=2)
        assert_english(self, json.loads(p.stdout))
        self.cfg.mkdir(parents=True, exist_ok=True)
        self.conf.write_text("[General]\naccentColor=#fff\naccentColor=#000\n")
        d = self.err("invalid", "config", "show")
        self.assertEqual(d["message"], "Your settings file, line 3: “accentColor” appears twice")

    def test_errors_an_interface_can_meet_carry_english(self):
        """Cada ConfigError/fail que puede llegar a una interfaz trae su `en=`: no se olvida en errores nuevos.

        Fuera quedan sólo lo de terminal o desarrollo (editar con $EDITOR, install --user, smoke, el esquema mal
        escrito, órdenes de desarrollo) y los errores de uso (code="usage"); esos reciben el texto genérico.
        """
        import ast
        terminal_only = {("sumi-sddm", "find_editor"), ("sumi-sddm", "config_edit"), ("sumi-sddm", "cmd_smoke"),
                         ("sumi-sddm", "main"), ("schema.py", "check_entry"), ("schema.py", "load")}
        files = [CLI] + [f for f in (ROOT / "tools" / "sumiconf").glob("*.py") if f.name != "install.py"]
        missing = []
        for f in files:
            for fn in ast.walk(ast.parse(f.read_text())):
                if not isinstance(fn, ast.FunctionDef) or (f.name, fn.name) in terminal_only:
                    continue
                for n in ast.walk(fn):
                    if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                            and n.func.id in ("ConfigError", "fail")):
                        continue
                    kw = {k.arg: k.value for k in n.keywords}
                    usage = isinstance(kw.get("code"), ast.Constant) and kw["code"].value == "usage"
                    if "en" not in kw and None not in kw and not usage:
                        missing.append(f"{f.name}:{n.lineno} ({fn.name})")
        self.assertEqual(missing, [])

    def test_usage_errors_are_rc2_without_json(self):
        p = self.run_cli("config", "set", "notchRadius=3", "--expect", "nothex", "--json", rc=2)
        self.assertEqual(p.stdout, "")
        p = self.run_cli("preview", "--size", "big", "--json", rc=2)
        self.assertEqual(json.loads(p.stdout)["code"], "usage")

    def test_every_code_is_documented(self):
        doc = (ROOT / "docs" / "CLI-JSON.md").read_text(encoding="utf-8")
        used = set()
        for f in [CLI, *(ROOT / "tools" / "sumiconf").glob("*.py")]:
            used |= set(re.findall(r'code="([a-z]+)"', f.read_text(encoding="utf-8")))
        used.add("invalid")  # el valor por defecto de ConfigError
        for code in used:
            self.assertIn(f"| `{code}` |", doc, code)


class StampTest(Base):
    def test_stamp_changes_only_on_change(self):
        s0 = self.stamp()
        self.assertEqual(self.stamp(), s0, "leer no cambia la huella")
        self.assertFalse(self.cfg.exists(), "leer no crea el directorio")
        s1 = self.ok("config", "set", "notchRadius=30")["stamp"]
        self.assertNotEqual(s1, s0)
        self.assertEqual(self.stamp(), s1)
        self.assertEqual(self.ok("config", "set", "notchRadius=30")["stamp"], s1, "sin cambios, sin escritura")
        self.assertEqual(self.ok("config", "unset", "clockFormat")["stamp"], s1)
        self.conf.write_text(self.conf.read_text() + "; a mano\n")
        self.assertNotEqual(self.stamp(), s1, "un cambio a mano también cuenta")

    def test_unset_without_file_creates_nothing(self):
        self.ok("config", "unset", "notchRadius")
        self.assertFalse(self.conf.exists())

    def test_expect_rejects_stale_writes(self):
        s0 = self.stamp()
        s1 = self.ok("config", "set", "notchRadius=30", "--expect", s0)["stamp"]
        before = self.conf.read_bytes()
        for args in (["config", "set", "notchRadius=40"], ["config", "unset", "notchRadius"], ["config", "reset"],
                     ["wallpaper", "clear"]):
            d = self.err("conflict", *args, "--expect", s0)
            self.assertEqual(d["stamp"], s1)
            self.assertEqual(self.conf.read_bytes(), before, args)
        self.ok("config", "reset", "--expect", s1)
        self.assertFalse(self.conf.exists())
        self.ok("config", "restore", "--expect", self.stamp())
        self.assertEqual(self.ok("config", "get", "notchRadius")["value"], 30)

    @unittest.skipUnless(MAGICK, "ImageMagick no disponible")
    def test_wallpaper_changes_stamp_and_preview_reports_it(self):
        a, b = self.home / "a.png", self.home / "b.png"
        subprocess.run([MAGICK, "-size", "800x600", "xc:#336699", str(a)], check=True)
        subprocess.run([MAGICK, "-size", "800x600", "xc:#996633", str(b)], check=True)
        s1 = self.ok("wallpaper", "set", str(a))["stamp"]
        time.sleep(0.02)
        s2 = self.ok("wallpaper", "set", str(b), "--expect", s1)["stamp"]
        self.assertNotEqual(s1, s2, "misma ruta (backgrounds/user.png), otra imagen: otra huella")
        self.err("conflict", "wallpaper", "set", str(a), "--expect", s1)
        pv = self.ok("preview", "--backend", "software", "--size", "640x360")
        self.assertEqual((pv["stamp"], pv["backend"]), (s2, "software"))

    def test_preview_auto_falls_back_without_graphics_context(self):
        # Sin variables de sesión gráfica, OpenGL offscreen no tiene contexto: auto debe acabar en software.
        env = {k: v for k, v in self.env.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY", "XDG_RUNTIME_DIR")}
        p = subprocess.run([sys.executable, "-B", str(CLI), "preview", "--size", "640x360", "--json"], env=env,
                           capture_output=True, text=True, timeout=120)
        doc = json.loads(p.stdout)
        self.assertTrue(doc["ok"], doc)
        self.assertIn(doc["backend"], ("opengl", "software"))
        self.assertTrue(Path(doc["png"]).is_file())


class LockTest(Base):
    def test_lock_file_is_private(self):
        self.ok("config", "set", "notchRadius=30")
        st = (self.cfg / ".lock").stat()
        self.assertEqual(st.st_mode & 0o777, 0o600)

    def test_symlinked_lock_is_refused(self):
        self.cfg.mkdir(parents=True)
        (self.cfg / ".lock").symlink_to(self.home / "elsewhere")
        self.err("io", "config", "set", "notchRadius=30")
        self.assertFalse((self.home / "elsewhere").exists())

    def test_busy_when_locked(self):
        self.cfg.mkdir(parents=True)
        fd = os.open(self.cfg / ".lock", os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            t = time.monotonic()
            self.err("busy", "config", "set", "notchRadius=30")
            self.assertGreaterEqual(time.monotonic() - t, 4.5)
        finally:
            os.close(fd)
        self.assertFalse(self.conf.exists())


class FontsTest(Base):
    def fake_fc_list(self):
        bindir = self.home / "fakebin"
        bindir.mkdir()
        fc = bindir / "fc-list"
        lines = [
            "Inter Variable\t/usr/share/fonts/inter/InterVariable.ttf",
            "Noto Sans,Noto Sans Display\t/usr/share/fonts/noto/NotoSans.ttf",
            f"Home Only\t{self.home}/.local/share/fonts/HomeOnly.ttf",
            f"Noto Sans\t{self.home}/.local/share/fonts/NotoSans-copy.ttf",
            "Bad;Name\t/usr/share/fonts/x.ttf",
        ]
        fc.write_text("#!/bin/sh\ncat <<'EOF'\n" + "\n".join(lines) + "\nEOF\n")
        fc.chmod(0o755)
        self.env["PATH"] = f"{bindir}:{self.env['PATH']}"

    def test_fonts_classification(self):
        self.fake_fc_list()
        fams = {f["family"]: f["system"] for f in self.ok("config", "fonts")["families"]}
        self.assertEqual(fams, {"Inter Variable": True, "Noto Sans": True, "Noto Sans Display": True,
                                "Home Only": False})

    def test_show_warns_about_fonts_the_greeter_cannot_see(self):
        self.fake_fc_list()
        self.ok("config", "set", "fontFamily=Noto Sans")
        self.assertEqual(self.ok("config", "show")["warnings"], [])
        self.ok("config", "set", "fontFamily=Home Only")
        w = self.ok("config", "show")["warnings"]
        self.assertEqual([x["key"] for x in w], ["fontFamily"])
        self.assertIn("home folder", w[0]["message"])
        self.ok("config", "set", "fontFamily=Not There")
        w = self.ok("config", "show")["warnings"][0]
        self.assertIn("not installed", w["message"])
        self.assertNotIn("suggestion", w, "nada parecido, nada sugerido")

    def test_font_warning_suggests_the_installed_name(self):
        self.fake_fc_list()
        for typed, want in (("Noto", "Noto Sans"), ("noto sans display", "Noto Sans Display"),
                            ("NotoSans", "Noto Sans"), ("Inter Variabel", "Inter Variable")):
            with self.subTest(typed=typed):
                self.ok("config", "set", "fontFamily=" + typed)
                w = self.ok("config", "show")["warnings"][0]
                self.assertEqual(w["suggestion"], want)
                self.assertIn(f"did you mean “{want}”", w["message"])
        self.ok("config", "set", "fontFamily=Home")    # sólo en el $HOME: no se sugiere
        self.assertNotIn("suggestion", self.ok("config", "show")["warnings"][0])

    def test_missing_fc_list(self):
        empty = self.home / "nobin"
        empty.mkdir()
        self.env["PATH"] = str(empty)
        self.err("missing", "config", "fonts")


class InstallTest(Base):
    def launcher(self):
        return self.home / ".local" / "bin" / "sumi-sddm"

    def releases(self):
        return self.home / "data" / "sumi-sddm" / "releases"

    def test_install_use_upgrade_uninstall(self):
        self.assertFalse(self.ok("install", "--status")["installed"])
        r1 = self.ok("install", "--user")
        L = self.launcher()
        self.assertTrue(L.is_file() and not L.is_symlink())
        self.assertEqual(L.stat().st_mode & 0o777, 0o755)
        self.assertIn("# sumi-sddm user launcher v1", L.read_text())
        rel = Path(r1["release"])
        self.assertTrue(rel.is_relative_to(self.releases()))
        for p in rel.rglob("*"):
            self.assertFalse(p.is_symlink(), p)
            self.assertNotIn("__pycache__", p.parts, p)
        self.assertFalse((rel / "tests").exists())
        self.assertFalse(any(rel.rglob("theme.conf.user")))
        self.assertTrue((rel / "docs" / "CONFIG.md").is_file())   # `config show` la enlaza
        # La copia instalada funciona por el lanzador, sin el repositorio.
        self.assertEqual(self.ok("version", exe=str(L))["kind"], "user")
        self.ok("config", "set", "clockFormat=12h", exe=str(L))
        self.assertEqual(self.ok("config", "get", "clockFormat")["value"], "12h")
        self.err("unsupported", "install", "--user", exe=str(L))
        p = self.run_cli("check", exe=str(L), rc=2)
        self.assertIn("sólo está disponible", p.stderr)
        self.assertTrue(self.ok("install", "--status", exe=str(L))["installed"])
        # Actualizar: se conservan la actual y la anterior.
        time.sleep(1.1)
        r2 = self.ok("install", "--user")
        self.assertEqual(r2["previous"], r1["release"])
        time.sleep(1.1)
        r3 = self.ok("install", "--user")
        self.assertEqual(sorted(p.name for p in self.releases().iterdir()),
                         sorted([Path(r2["release"]).name, Path(r3["release"]).name]))
        self.assertIn(Path(r1["release"]).name, r3["removed"])
        # Desinstalar: fuera lanzador y copias; la configuración se queda.
        u = self.ok("uninstall", "--user")
        self.assertEqual(u["kept"], str(self.cfg))
        self.assertFalse(L.exists())
        self.assertFalse((self.home / "data" / "sumi-sddm").exists())
        self.assertTrue(self.conf.is_file())

    def test_foreign_launcher_is_never_touched(self):
        L = self.launcher()
        L.parent.mkdir(parents=True)
        L.write_text("#!/bin/sh\necho mine\n")
        self.err("conflict", "install", "--user")
        self.err("conflict", "uninstall", "--user")
        self.assertEqual(L.read_text(), "#!/bin/sh\necho mine\n")
        self.assertTrue(self.ok("install", "--status")["foreign"])
        L.unlink()
        L.symlink_to(self.home / "target")
        self.err("conflict", "install", "--user")
        self.assertTrue(L.is_symlink())


if __name__ == "__main__":
    unittest.main()

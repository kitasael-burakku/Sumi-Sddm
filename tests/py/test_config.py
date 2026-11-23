"""Pruebas de tools/sumiconf y de la CLI `sumi-sddm` (config, wallpaper, preview, gen).

Ejecutar:  python3 -B -m unittest discover -s tests/py
Todo ocurre en directorios temporales (XDG_CONFIG_HOME/XDG_CACHE_HOME propios); nada toca ~/.config.
"""
from __future__ import annotations

import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from sumiconf import ConfigError, Schema, lenient, strict  # noqa: E402
from sumiconf import gen, image, ini  # noqa: E402
from sumiconf.schema import check_entry  # noqa: E402

CLI = ROOT / "tools" / "sumi-sddm"
MAGICK = shutil.which("magick")


def load_vectors():
    text = (ROOT / "tests" / "fixtures" / "config-vectors.js").read_text(encoding="utf-8")
    m = re.search(r"var VECTORS = (\[.*\]);", text, re.S)
    return json.loads(m.group(1))


class SchemaTest(unittest.TestCase):
    def setUp(self):
        self.s = Schema.load()

    def test_entries_are_consistent(self):
        groups = {g["id"] for g in self.s.groups}
        for k in self.s.order:
            check_entry(self.s.keys[k], groups)
        self.assertGreaterEqual(len(self.s.order), 40)

    def test_every_group_used(self):
        used = {self.s.keys[k]["group"] for k in self.s.order}
        self.assertEqual(used, {g["id"] for g in self.s.groups})

    def test_defaults_pass_strict(self):
        for k in self.s.order:
            e = self.s.keys[k]
            if e["type"] in ("string", "path") and e["default"] == "":
                continue
            self.assertEqual(strict(e, ini.parse(ini.render(self.s, {k: e["default"]}))[k]), e["default"], k)

    def test_generated_files_up_to_date(self):
        self.assertEqual(gen.generate(check=True), [], "ejecuta: tools/sumi-sddm gen")

    def test_theme_conf_parses_and_equals_defaults(self):
        values = ini.validate(self.s, ini.parse((ROOT / "theme" / "sumi" / "theme.conf").read_text(encoding="utf-8")))
        self.assertEqual(set(values), set(self.s.order))
        for k, v in values.items():
            self.assertEqual(v, self.s.keys[k]["default"], k)


class LenientParityTest(unittest.TestCase):
    def test_vectors(self):
        s = Schema.load()
        vectors = load_vectors()
        self.assertGreater(len(vectors), 40)
        for v in vectors:
            got = lenient(s.entry(v["key"]), v["raw"])
            exp = v["expect"]
            with self.subTest(key=v["key"], raw=v["raw"]):
                if isinstance(exp, (int, float)) and not isinstance(exp, bool):
                    self.assertFalse(isinstance(got, bool))
                    self.assertTrue(math.isclose(got, exp), f"{got} != {exp}")
                else:
                    self.assertEqual(got, exp)


class StrictTest(unittest.TestCase):
    def setUp(self):
        self.s = Schema.load()

    def ok(self, key, raw, expect):
        self.assertEqual(strict(self.s.entry(key), raw), expect)

    def bad(self, key, raw):
        with self.assertRaises(ConfigError, msg=f"{key}={raw!r}"):
            strict(self.s.entry(key), raw)

    def test_numbers(self):
        self.ok("blurRadius", "40", 40.0)
        self.ok("dimOpacity", "0.85", 0.85)
        for raw in ("101", "-1", "abc", "0x10", "1e999", "NaN", ""):
            self.bad("blurRadius", raw)

    def test_integers(self):
        self.ok("notchRadius", "30", 30)
        for raw in ("30.5", "3", "49", "1e1"):
            self.bad("notchRadius", raw)
        self.ok("notchIdleCollapse", "0", 0)
        self.bad("notchIdleCollapse", "3")
        self.ok("clockOffsetY", "-400", -400)

    def test_bool_enum_color(self):
        self.ok("animations", "Off", False)
        self.bad("animations", "maybe")
        self.ok("clockFormat", "12H", "12h")
        self.bad("clockFormat", "25h")
        self.ok("accentColor", "#AABBCC", "#aabbcc")
        for raw in ("#abc", "red", "#aabbccd"):
            self.bad("accentColor", raw)

    def test_strings(self):
        self.ok("fontFamily", "IBM Plex Sans", "IBM Plex Sans")
        for raw in ("Evil;Font", "a\nb", "x" * 65, "@Variant(abc)"):
            self.bad("fontFamily", raw)
        self.ok("dateFormat", "dddd, d MMMM yyyy", "dddd, d MMMM yyyy")
        self.bad("dateFormat", "<b>")

    def test_paths(self):
        self.ok("background", "backgrounds/user.jpg", "backgrounds/user.jpg")
        self.ok("background", "/usr/share/backgrounds/a.png", "/usr/share/backgrounds/a.png")
        for raw in ("../x.jpg", "/etc/a.jpg", "/home/u/a.jpg", "backgrounds/../a.jpg", "backgrounds/a.svg",
                    "file:///usr/share/a.jpg", "/usr/share//a.jpg", "backgrounds/Up.jpg", "/usr/share/a b.jpg"):
            self.bad("background", raw)


class IniTest(unittest.TestCase):
    def setUp(self):
        self.s = Schema.load()

    def test_roundtrip_and_quoting(self):
        values = {"dateFormat": "dddd, d MMMM", "fontFamily": "IBM Plex Sans",
                  "accentColor": "#aabbcc", "animations": False, "blurRadius": 12.5, "notchRadius": 30,
                  "clockFormat": "12h"}
        text = ini.render(self.s, values, "cabecera")
        self.assertIn('dateFormat="dddd, d MMMM"', text)
        self.assertIn("blurRadius=12.5", text)
        self.assertEqual(ini.validate(self.s, ini.parse(text)), values)

    def test_escapes(self):
        self.assertEqual(ini.parse('[General]\nfontFamily="a\\"b\\\\c"\n'), {"fontFamily": 'a"b\\c'})

    def test_rejections(self):
        cases = [
            "[Other]\nx=1\n",
            "notchRadius=3\n",                      # fuera de sección
            "[General]\ndateFormat=a, b\n",          # lista de QSettings
            "[General]\nfontFamily=a;b\n",           # comentario
            "[General]\nfontFamily=a\\nb\n",         # escape sin comillas
            '[General]\nfontFamily="abc\n',          # comillas sin cerrar
            '[General]\nfontFamily="a" b\n',         # texto tras las comillas
            '[General]\nfontFamily="a\\x41"\n',      # escape no permitido
            "[General]\nfontFamily=@Variant(x)\n",
            '[General]\nfontFamily="@ByteArray(x)"\n',
            "[General]\nnotchRadius=3\nnotchRadius=4\n",
            "[General]\n9bad=1\n",
            "[General]\njustakey\n",
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ConfigError):
                ini.parse(text)

    def test_unknown_key_rejected(self):
        with self.assertRaises(ConfigError):
            ini.validate(self.s, ini.parse("[General]\nevil=1\n"))

    def test_unknown_key_suggestion(self):
        self.assertEqual(self.s.suggest("notchradius"), "notchRadius")
        self.assertEqual(self.s.suggest("acentColor"), "accentColor")
        self.assertEqual(self.s.suggest("evil"), "")
        with self.assertRaisesRegex(ConfigError, "¿quisiste decir «clockFormat»?"):
            self.s.entry("clockformat")
        with self.assertRaisesRegex(ConfigError, "config schema"):
            self.s.entry("evil")

    def test_comments_and_blank_lines(self):
        self.assertEqual(ini.parse("; c\n# c\n\n[General]\n; x\nnotchRadius = 30 \n"), {"notchRadius": "30"})

    def test_write_atomic_mode_and_symlink(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "sub" / "theme.conf.user"
            ini.write_atomic(p, "[General]\n")
            self.assertEqual(p.stat().st_mode & 0o777, 0o644)
            self.assertEqual([x.name for x in p.parent.iterdir()], ["theme.conf.user"], "sin temporales")
            victim = Path(d) / "victim"
            victim.write_text("keep")
            link = Path(d) / "link.conf"
            link.symlink_to(victim)
            with self.assertRaises(ConfigError):
                ini.write_atomic(link, "x")
            self.assertEqual(victim.read_text(), "keep")
            with self.assertRaises(OSError):
                ini.read_file(link)


@unittest.skipUnless(MAGICK, "ImageMagick no disponible")
class ImageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def make(self, name, size="800x600"):
        p = self.d / name
        subprocess.run([MAGICK, "-size", size, "gradient:#223-#556", str(p)], check=True)
        return p

    def test_kinds_and_dimensions(self):
        for name, kind in (("a.png", "png"), ("a.jpg", "jpg"), ("a.webp", "webp"), ("progressive.jpg", "jpg")):
            p = self.make(name, "1024x576")
            if name.startswith("progressive"):
                subprocess.run([MAGICK, str(p), "-interlace", "JPEG", str(p)], check=True)
            if kind == "webp" and not image.webp_supported():
                continue
            info = image.inspect(p)
            self.assertEqual((info.kind, info.width, info.height), (kind, 1024, 576), name)

    def test_webp_lossless_and_extended(self):
        if not image.webp_supported():
            self.skipTest("sin qt6-imageformats")
        p = self.d / "l.webp"
        subprocess.run([MAGICK, "-size", "640x400", "gradient:", "-define", "webp:lossless=true", str(p)], check=True)
        self.assertEqual(image.inspect(p).width, 640)

    def test_extension_lies_are_ignored(self):
        p = self.make("real.png")
        fake = self.d / "fake.jpg"
        fake.write_bytes(p.read_bytes())
        self.assertEqual(image.inspect(fake).kind, "png")

    def test_rejections(self):
        small = self.make("small.png", "100x100")
        text = self.d / "x.jpg"
        text.write_text("not an image at all, just text" * 4)
        svg = self.d / "x.svg"
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="900" height="900"/>' + " " * 40)
        huge = self.d / "huge.png"
        huge.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 50000, 50000) + b"\x08\x02\x00\x00\x00" + b"\x00" * 40)
        trunc = self.d / "t.jpg"
        trunc.write_bytes(self.make("full.jpg").read_bytes()[:20])
        link = self.d / "link.png"
        link.symlink_to(self.make("target.png"))
        for p in (small, text, svg, huge, trunc, link, self.d / "missing.png", self.d):
            with self.subTest(p=p.name), self.assertRaises(ConfigError):
                image.inspect(p)

    def test_copy_validated(self):
        src = self.make("w.jpg", "1920x1080")
        dest, info = image.copy_validated(src, self.d / "out", "user")
        self.assertEqual(dest.name, "user.jpg")
        self.assertEqual(dest.read_bytes(), src.read_bytes())
        self.assertEqual(dest.stat().st_mode & 0o777, 0o644)
        self.assertEqual(sorted(x.name for x in (self.d / "out").iterdir()), ["user.jpg"])


class CliTest(unittest.TestCase):
    """La CLI real, con HOME/XDG propios."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "cfg"),
                        XDG_CACHE_HOME=str(self.home / "cache"))
        self.env.pop("VISUAL", None)   # tiene prioridad sobre EDITOR en `config edit`
        self.conf = self.home / "cfg" / "sumi-sddm" / "theme.conf.user"

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, ok=True):
        p = subprocess.run([sys.executable, "-B", str(CLI), *args], env=self.env, capture_output=True, text=True,
                           timeout=120)
        if ok:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        else:
            self.assertNotEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def js(self, *args, ok=True):
        return json.loads(self.run_cli(*args, "--json", ok=ok).stdout)

    def test_set_get_show_unset(self):
        self.js("config", "set", "clockFormat=12h", "accentColor=#FFB38A", "dateFormat=dddd, d MMMM yyyy")
        self.assertEqual(self.js("config", "get", "accentColor")["value"], "#ffb38a")
        show = self.js("config", "show")["values"]
        self.assertTrue(show["clockFormat"]["set"])
        self.assertFalse(show["blurRadius"]["set"])
        text = self.conf.read_text()
        self.assertIn('dateFormat="dddd, d MMMM yyyy"', text)
        self.js("config", "unset", "clockFormat")
        self.assertEqual(self.js("config", "get", "clockFormat")["value"], "24h")
        self.js("config", "set", "accentColor=")       # vacío = quitar
        self.assertFalse(self.js("config", "show")["values"]["accentColor"]["set"])
        self.js("config", "validate")

    def test_set_is_all_or_nothing(self):
        self.js("config", "set", "notchRadius=30")
        before = self.conf.read_bytes()
        r = self.js("config", "set", "clockFormat=12h", "notchRadius=999", ok=False)
        self.assertFalse(r["ok"])
        self.assertEqual(self.conf.read_bytes(), before)
        self.js("config", "set", "nope=1", ok=False)
        self.js("config", "set", "background=../../etc/shadow.jpg", ok=False)
        self.js("config", "set", "background=backgrounds/user.jpg", ok=False)   # no existe
        self.assertEqual(self.conf.read_bytes(), before)

    def test_reset_and_restore(self):
        self.js("config", "set", "notchRadius=30")
        self.js("config", "reset")
        self.assertFalse(self.conf.exists())
        self.assertEqual(self.js("config", "get", "notchRadius")["value"], 22)
        self.js("config", "restore")
        self.assertEqual(self.js("config", "get", "notchRadius")["value"], 30)

    def test_broken_user_file_is_reported(self):
        self.conf.parent.mkdir(parents=True)
        self.conf.write_text("[General]\nnotchRadius=banana\n")
        r = self.js("config", "validate", ok=False)
        self.assertIn("notchRadius", r["error"])
        self.js("config", "show", ok=False)

    def edit(self, script: str, ok=True):
        """`config edit` con un «editor» de prueba: un script de Python que recibe la ruta del archivo."""
        ed = self.home / "editor.py"
        ed.write_text("import sys, pathlib\np = pathlib.Path(sys.argv[1])\nt = p.read_text()\n" + script)
        self.env["EDITOR"] = f"{sys.executable} -B {ed}"
        return self.run_cli("config", "edit", ok=ok)

    def edit_leftovers(self):
        return list((self.home / "cache" / "sumi-sddm" / "edit").glob("edit-*"))

    def test_edit_saves_normalized(self):
        self.js("config", "set", "notchRadius=30")
        p = self.edit("t = t.replace(';clockFormat=24h', 'clockFormat=12H')\n"
                      "t = t.replace('notchRadius=30', ';notchRadius=30')\n"
                      "assert 'Radio' in t or 'notch' in t.lower()\np.write_text(t)\n")
        self.assertIn("guardado", p.stdout)
        self.assertEqual(self.js("config", "get", "clockFormat")["value"], "12h")
        self.assertFalse(self.js("config", "show")["values"]["notchRadius"]["set"])
        self.assertEqual(self.edit_leftovers(), [])

    def test_edit_buffer_lists_every_key(self):
        self.js("config", "set", "notchRadius=30")
        out = self.home / "seen.ini"
        self.edit(f"pathlib.Path({str(out)!r}).write_text(t)\n")
        seen = out.read_text()
        body = ini.parse(seen)
        self.assertEqual(body, {"notchRadius": "30"})           # sólo lo personalizado está activo
        for k in Schema.load().order:
            self.assertIn(k, seen)

    def test_edit_invalid_writes_nothing_and_keeps_buffer(self):
        self.js("config", "set", "notchRadius=30")
        before = self.conf.read_bytes()
        p = self.edit("p.write_text(t.replace('notchRadius=30', 'notchRadius=999'))\n", ok=False)
        self.assertIn("fuera de rango", p.stderr)
        self.assertEqual(self.conf.read_bytes(), before)
        left = self.edit_leftovers()
        self.assertEqual(len(left), 1)
        self.assertIn(str(left[0]), p.stderr)

    def test_edit_unknown_key_suggests(self):
        p = self.edit("p.write_text(t + 'accentcolor=\"#ffffff\"\\n')\n", ok=False)
        self.assertIn("¿quisiste decir «accentColor»?", p.stderr)
        self.assertFalse(self.conf.exists())

    def test_edit_no_change_empty_and_editor_failure(self):
        self.assertIn("sin cambios", self.edit("pass\n").stdout)
        self.assertIn("cancelada", self.edit("p.write_text('')\n").stdout)
        p = self.edit("sys.exit(3)\n", ok=False)
        self.assertIn("código 3", p.stderr)
        self.assertFalse(self.conf.exists())
        self.assertEqual(self.edit_leftovers(), [])

    def test_edit_conflict(self):
        # Mientras el editor está abierto, otro programa escribe: no se pisa.
        p = self.edit(f"import subprocess\n"
                      f"subprocess.run([sys.executable, '-B', {str(CLI)!r}, 'config', 'set', 'notchRadius=40'],"
                      f" check=True)\n"
                      f"p.write_text(t.replace(';clockFormat=24h', 'clockFormat=12h'))\n", ok=False)
        self.assertIn("cambió mientras editabas", p.stderr)
        vals = self.js("config", "show")["values"]
        self.assertEqual(vals["notchRadius"]["value"], 40)
        self.assertFalse(vals["clockFormat"]["set"])

    def test_edit_repairs_broken_file(self):
        self.conf.parent.mkdir(parents=True)
        self.conf.write_text("[General]\nnotchRadius=banana\n")
        p = self.edit("assert t.startswith('; ERROR: ') and 'notchRadius' in t.split('\\n')[0]\n"
                      "p.write_text(t.replace('notchRadius=banana', 'notchRadius=12'))\n")
        self.assertIn("guardado", p.stdout)
        self.assertEqual(self.js("config", "get", "notchRadius")["value"], 12)

    def test_edit_without_editor(self):
        self.env["EDITOR"] = "no-such-editor-sumi"
        p = self.run_cli("config", "edit", ok=False)
        self.assertIn("no encuentro el editor", p.stderr)

    def test_show_points_to_docs_and_edit(self):
        out = self.run_cli("config", "show").stdout
        self.assertIn("sumi-sddm config edit", out)
        self.assertIn(str(ROOT / "docs" / "CONFIG.md"), out)
        p = self.js("config", "set", "clockformat=12h", ok=False)
        self.assertIn("¿quisiste decir «clockFormat»?", p["error"])

    def test_schema_json(self):
        data = self.js("config", "schema")
        self.assertIn("keys", data)
        self.assertTrue(all("label" in e for e in data["keys"]))

    @unittest.skipUnless(MAGICK, "ImageMagick no disponible")
    def test_wallpaper_set_clear(self):
        src = self.home / "pic.png"
        subprocess.run([MAGICK, "-size", "1280x720", "gradient:#123-#9ab", str(src)], check=True)
        r = self.js("wallpaper", "set", str(src))
        self.assertEqual(r["background"], "backgrounds/user.png")
        staged = self.home / "cfg" / "sumi-sddm" / "backgrounds" / "user.png"
        self.assertTrue(staged.is_file())
        self.assertEqual(self.js("wallpaper", "info")["width"], 1280)
        jpg = self.home / "pic.jpg"
        subprocess.run([MAGICK, str(src), str(jpg)], check=True)
        self.js("wallpaper", "set", str(jpg))
        self.assertFalse(staged.exists(), "la copia anterior con otra extensión se borra")
        self.js("wallpaper", "clear")
        self.assertEqual(list((self.home / "cfg" / "sumi-sddm" / "backgrounds").iterdir()), [])
        self.assertEqual(self.js("config", "get", "background")["value"], "")
        bad = self.home / "bad.jpg"
        bad.write_text("x" * 100)
        self.js("wallpaper", "set", str(bad), ok=False)

    @unittest.skipUnless(MAGICK, "ImageMagick no disponible")
    def test_preview_uses_user_config_and_wallpaper(self):
        src = self.home / "pic.jpg"
        subprocess.run([MAGICK, "-size", "1600x900", "gradient:#c84-#248", str(src)], check=True)
        self.js("wallpaper", "set", str(src))
        self.js("config", "set", "blurRadius=40", "accentColor=#ff8800")
        out = self.home / "p.png"
        r = self.js("preview", "--out", str(out), "--backend", "software", "--size", "1280x720")
        self.assertTrue(out.is_file())
        self.assertEqual(r["png"], str(out))
        staged = self.home / "cache" / "sumi-sddm" / "preview" / "sumi"
        self.assertTrue((staged / "theme.conf.user").is_file())
        self.assertTrue((staged / "backgrounds" / "user.jpg").is_file())
        # El wallpaper se ve: a media altura el degradado #c84→#248 da un rojo ~0.46 (×dim); la «tinta» da < 0.1.
        px = subprocess.run([MAGICK, str(out), "-format", "%[fx:p{5,360}.r]", "info:"], capture_output=True, text=True)
        self.assertGreater(float(px.stdout), 0.3)

    def test_try_requires_confirmation(self):
        p = self.run_cli("try", ok=False)
        self.assertEqual(p.returncode, 2)
        self.assertIn("VENTANA", p.stdout)


if __name__ == "__main__":
    unittest.main()

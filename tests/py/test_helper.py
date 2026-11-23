"""Pruebas del helper privilegiado (system/sumi-sddm-helper) SIN root: raíz falsa (SUMI_SDDM_HELPER_ROOT) y un
greeter falso (SUMI_SDDM_HELPER_PROBE); una prueba usa el greeter real si está instalado. Y `sumi-sddm system`
con un pkexec falso. Nada toca /usr, /etc ni /var de verdad.
"""
from __future__ import annotations

import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sumiconf import Schema, ini  # noqa: E402

HELPER = ROOT / "system" / "sumi-sddm-helper"
CLI = ROOT / "tools" / "sumi-sddm"
GREETER = shutil.which("sddm-greeter-qt6")
SDDM_CONF = (b"# NOTA: este archivo se lee AL FINAL\n\n[Theme]\nCurrent=orbital\n\n[General]\nInputMethod=\n")

FAKE_GREETER = r'''#!/usr/bin/env python3
# Greeter falso: lee theme.conf.user del tema como QSettings y escribe la línea `ready` del tema.
import sys
sys.path.insert(0, %(tools)r)
from pathlib import Path
from sumiconf import Schema, ini, probe
theme = Path(sys.argv[sys.argv.index("--theme") + 1])
conf = theme / "theme.conf.user"
raw = ini.parse(conf.read_text()) if conf.exists() else {}
n = probe.expected_custom(Schema.load(), raw)
print("qml: sumi-sddm: ready users=1 sessions=1 primary=true clock=24h custom=%%d" %% n, flush=True)
'''
BROKEN_GREETER = '''#!/bin/sh
echo "file:///x/sumi/components/Greeter.qml:12: TypeError: Cannot read property 'x' of null"
'''


def png(path: Path, w=640, h=400, color=(30, 60, 90)) -> bytes:
    import struct
    import zlib
    raw = b"".join(b"\x00" + bytes(color) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    path.write_bytes(data)
    return data


def package(conf: str = "", img: bytes | None = None, kind: str = "png", header: dict | None = None) -> bytes:
    c = conf.encode()
    h = header if header is not None else {"format": 1, "conf": len(c),
                                           "image": {"kind": kind, "bytes": len(img)} if img is not None else None}
    return json.dumps(h).encode() + b"\n" + c + (img or b"")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = Path(self.tmp.name)
        self.root = self.t / "root"
        themes = self.root / "usr/share/sddm/themes"
        shutil.copytree(ROOT / "theme" / "sumi", themes / "sumi")
        (themes / "orbital").mkdir(parents=True)
        (themes / "orbital" / "metadata.desktop").write_text("[SddmGreeterTheme]\nName=orbital\n")
        (self.root / "usr/lib/sddm/sddm.conf.d").mkdir(parents=True)
        (self.root / "usr/lib/sddm/sddm.conf.d/default.conf").write_text("[Theme]\nCurrent=\n")
        (self.root / "etc/sddm.conf.d").mkdir(parents=True)
        (self.root / "etc/sddm.conf.d/theme.conf").write_text("\n[Theme]\nCurrent=orbital\n")
        (self.root / "etc/sddm.conf").write_bytes(SDDM_CONF)
        self.theme = themes / "sumi"
        self.state = self.root / "var/lib/sumi-sddm"
        fake = self.t / "fake-greeter"
        fake.write_text(FAKE_GREETER % {"tools": str(ROOT / "tools")})
        fake.chmod(0o755)
        broken = self.t / "broken-greeter"
        broken.write_text(BROKEN_GREETER)
        broken.chmod(0o755)
        self.broken = str(broken)
        self.env = dict(os.environ, SUMI_SDDM_HELPER_ROOT=str(self.root), SUMI_SDDM_HELPER_PROBE=str(fake))
        self.schema = Schema.load()

    def tearDown(self):
        self.tmp.cleanup()

    def helper(self, *args, data: bytes = b"", env=None, rc=None):
        p = subprocess.run([sys.executable, "-I", "-B", str(HELPER), *args], input=data, capture_output=True,
                           env=env or self.env, timeout=120)
        if rc is not None:
            self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return json.loads(p.stdout.decode().strip().splitlines()[-1]) if p.stdout.strip() else {"stderr": p.stderr}

    def ok(self, *args, data=b"", env=None):
        d = self.helper(*args, data=data, env=env, rc=0)
        self.assertTrue(d["ok"], d)
        return d

    def err(self, code, *args, data=b"", env=None):
        d = self.helper(*args, data=data, env=env, rc=1)
        self.assertEqual((d["ok"], d["code"]), (False, code), d)
        return d

    def user_files(self):
        out = {}
        if (self.theme / "theme.conf.user").exists():
            out["theme.conf.user"] = (self.theme / "theme.conf.user").read_bytes()
        for p in sorted((self.theme / "backgrounds").glob("user.*")) if (self.theme / "backgrounds").is_dir() else []:
            out["backgrounds/" + p.name] = p.read_bytes()
        return out

    def backups(self):
        d = self.state / "backups"
        return sorted(p.name for p in d.iterdir()) if d.is_dir() else []


class StatusAndUsage(Base):
    def test_status(self):
        d = self.ok("status", "--json")
        self.assertEqual((d["installed"], d["activeTheme"], d["active"]), (True, "orbital", False))
        self.assertTrue(d["decidedBy"].endswith("/etc/sddm.conf"))
        (self.root / "etc/sddm.conf").write_text("[General]\n")
        self.assertTrue(self.ok("status")["decidedBy"].endswith("sddm.conf.d/theme.conf"))

    def test_usage_and_refusals(self):
        self.assertEqual(self.helper("bogus", rc=2)["code"], "usage")
        self.assertEqual(self.helper("apply", "extra", rc=2)["code"], "usage")
        env = {k: v for k, v in self.env.items() if not k.startswith("SUMI_SDDM_HELPER")}
        self.assertEqual(self.helper("apply", env=env, rc=1)["code"], "unsupported")

    def test_missing_theme(self):
        shutil.rmtree(self.theme)
        self.err("missing", "apply", data=package())

    def test_busy(self):
        self.state.mkdir(parents=True, mode=0o700)
        fd = os.open(self.state / "lock", os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            self.err("busy", "reset")
        finally:
            os.close(fd)


class Apply(Base):
    def test_apply_writes_only_validated_files(self):
        img = png(self.t / "w.png")
        conf = 'accentColor="#FF8800"\nbackground="backgrounds/user.png"\nclockFormat=12h\n'
        d = self.ok("apply", data=package("[General]\n" + conf, img))
        self.assertTrue(d["changed"] and d["probe"]["ok"])
        self.assertEqual(d["probe"]["expectCustom"], 3)
        files = self.user_files()
        self.assertEqual(set(files), {"theme.conf.user", "backgrounds/user.png"})
        self.assertEqual(files["backgrounds/user.png"], img)
        text = files["theme.conf.user"].decode()
        self.assertIn('accentColor="#ff8800"', text, "se escribe el valor normalizado, no el texto recibido")
        self.assertIn("aplicado por sumi-sddm-helper", text)
        self.assertEqual((self.theme / "theme.conf.user").stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(len(self.backups()), 1)
        again = self.ok("apply", data=package("[General]\n" + conf, img))
        self.assertFalse(again["changed"])
        self.assertEqual(len(self.backups()), 1, "sin cambios, sin respaldo")
        log = (self.state / "log").read_text()
        self.assertIn(" apply ok", log)
        self.assertNotIn("ff8800", log.lower(), "el registro no lleva valores")

    def test_bad_input_writes_nothing(self):
        img = png(self.t / "w.png")
        cases = [
            b"not json\n",
            json.dumps({"format": 2, "conf": 0, "image": None}).encode() + b"\n",
            json.dumps({"format": 1, "conf": 0, "image": None, "x": 1}).encode() + b"\n",
            json.dumps({"format": 1, "conf": 70000, "image": None}).encode() + b"\n",
            json.dumps({"format": 1, "conf": True, "image": None}).encode() + b"\n",
            package("[General]\nnotchRadius=banana\n"),
            package("[General]\nbackground=\"backgrounds/user.png\"\n"),               # sin imagen
            package("[General]\naccentColor=\"#ff0000\"\n", img),                        # imagen sin background
            package("[General]\nbackground=\"backgrounds/user.jpg\"\n", img, "jpg"),     # tipo que no es
            package("[General]\n") + b"extra",                                           # datos de más
            package("[General]\nclockFormat=12h\n")[:-3],                                # truncado
            package("", b"x" * 64, "png", {"format": 1, "conf": 0, "image": {"kind": "png", "bytes": 64}}),
            package("[General]\n", None, header={"format": 1, "conf": 9, "image": None})[:-1] + b"\xff",
            json.dumps({"format": 1, "conf": 0, "image": {"kind": "gif", "bytes": 100}}).encode() + b"\n",
            b"x" * 5000,
        ]
        before = self.user_files()
        for data in cases:
            with self.subTest(data=data[:60]):
                self.err("invalid", "apply", data=data)
        self.assertEqual(self.user_files(), before)
        self.assertEqual(self.backups(), [])

    def test_failed_probe_writes_nothing(self):
        env = dict(self.env, SUMI_SDDM_HELPER_PROBE=self.broken)
        d = self.err("probe", "apply", data=package("[General]\nclockFormat=12h\n"), env=env)
        self.assertTrue(any("TypeError" in p for p in d["problems"]))
        self.assertEqual(self.user_files(), {})
        self.assertEqual(self.backups(), [])

    def test_symlinks_are_refused(self):
        victim = self.t / "victim"
        victim.write_text("keep")
        (self.theme / "theme.conf.user").symlink_to(victim)
        self.err("io", "apply", data=package("[General]\nclockFormat=12h\n"))
        self.assertEqual(victim.read_text(), "keep")
        (self.theme / "theme.conf.user").unlink()
        elsewhere = self.t / "elsewhere"
        elsewhere.mkdir()
        (self.theme / "backgrounds").symlink_to(elsewhere)
        img = png(self.t / "w.png")
        self.err("io", "apply", data=package('[General]\nbackground="backgrounds/user.png"\n', img))
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_group_writable_theme_is_refused(self):
        self.theme.chmod(0o775)
        self.err("io", "apply", data=package("[General]\nclockFormat=12h\n"))

    def test_reset_and_rollback_chain(self):
        img = png(self.t / "w.png")
        a = package('[General]\nbackground="backgrounds/user.png"\nclockFormat=12h\n', img)
        self.ok("apply", data=a)
        first = self.user_files()
        self.ok("apply", data=package("[General]\nnotchRadius=30\n"))
        self.assertEqual(set(self.user_files()), {"theme.conf.user"}, "el wallpaper viejo se quita")
        second = self.user_files()
        self.ok("reset")
        self.assertEqual(self.user_files(), {})
        self.assertFalse(self.ok("reset")["changed"])
        self.ok("rollback")
        self.assertEqual(self.user_files(), second, "rollback deshace el reset")
        self.ok("rollback")
        self.assertEqual(self.user_files(), {}, "y el siguiente deshace el rollback (vuelve al reset)")

    def test_backups_rotate(self):
        for i in range(12):
            self.ok("apply", data=package(f"[General]\nnotchRadius={10 + i}\n"))
        self.assertLessEqual(len(self.backups()), 8)


class Activation(Base):
    def conf(self):
        return (self.root / "etc/sddm.conf").read_bytes()

    def test_activate_and_exact_restore(self):
        d = self.ok("activate")
        self.assertEqual((d["changed"], d["activeTheme"], d["previousTheme"]), (True, "sumi", "orbital"))
        self.assertEqual(self.conf(), SDDM_CONF.replace(b"Current=orbital", b"Current=sumi"),
                         "sólo cambia el valor de Current")
        self.assertFalse(self.ok("activate")["changed"], "idempotente")
        self.assertTrue(self.ok("status")["active"])
        d = self.ok("deactivate")
        self.assertEqual(d["activeTheme"], "orbital")
        self.assertEqual(self.conf(), SDDM_CONF, "se repone byte a byte")
        self.assertFalse(self.ok("deactivate")["changed"])

    def test_activate_without_theme_section(self):
        (self.root / "etc/sddm.conf").write_bytes(b"[General]\nNumlock=on")
        self.ok("activate")
        self.assertEqual(self.conf(), b"[General]\nNumlock=on\n\n[Theme]\nCurrent=sumi\n")
        self.ok("deactivate")
        self.assertEqual(self.conf(), b"[General]\nNumlock=on")

    def test_duplicate_current_and_crlf(self):
        original = b"[Theme]\r\nCurrent=orbital\r\n# x\r\nCurrent = maya\r\n"
        (self.root / "etc/sddm.conf").write_bytes(original)
        self.ok("activate")
        self.assertEqual(self.conf(), b"[Theme]\r\nCurrent=sumi\r\n# x\r\nCurrent = sumi\r\n")
        self.ok("deactivate")
        self.assertEqual(self.conf(), original)

    def test_deactivate_keeps_later_edits(self):
        self.ok("activate")
        edited = self.conf().replace(b"InputMethod=", b"InputMethod=qtvirtualkeyboard")
        (self.root / "etc/sddm.conf").write_bytes(edited)
        self.ok("deactivate")
        self.assertEqual(self.conf(), edited.replace(b"Current=sumi", b"Current=orbital"),
                         "edición posterior conservada; sólo vuelve Current")

    def test_deactivate_to_named_theme(self):
        self.ok("activate")
        self.err("invalid", "deactivate", "../../etc")
        self.err("invalid", "deactivate", "nonexistent")
        self.err("invalid", "deactivate", "sumi")
        self.assertEqual(self.ok("deactivate", "orbital")["activeTheme"], "orbital")

    def test_failed_probe_blocks_activation(self):
        env = dict(self.env, SUMI_SDDM_HELPER_PROBE=self.broken)
        self.err("probe", "activate", env=env)
        self.assertEqual(self.conf(), SDDM_CONF)

    def test_symlinked_sddm_conf_is_refused(self):
        real = self.t / "real.conf"
        real.write_bytes(SDDM_CONF)
        (self.root / "etc/sddm.conf").unlink()
        (self.root / "etc/sddm.conf").symlink_to(real)
        self.err("io", "activate")
        self.assertEqual(real.read_bytes(), SDDM_CONF)


@unittest.skipUnless(GREETER, "sddm-greeter-qt6 no está instalado")
class RealGreeterProbe(Base):
    def test_real_greeter_reads_the_staged_copy(self):
        env = dict(self.env, SUMI_SDDM_HELPER_PROBE=GREETER)
        img = png(self.t / "w.png", 1280, 720)
        d = self.ok("apply", data=package('[General]\nbackground="backgrounds/user.png"\nclockFormat=12h\n'
                                          'accentColor="#ff8800"\n', img), env=env)
        self.assertTrue(d["probe"]["ok"], d)
        self.assertIn("custom=3", d["probe"]["ready"])


class CliSystem(Base):
    def setUp(self):
        super().setUp()
        bindir = self.t / "bin"
        bindir.mkdir()
        (bindir / "pkexec").write_text(f'#!/bin/sh\nexec {sys.executable} -I -B "$@"\n')
        (bindir / "pkexec").chmod(0o755)
        (bindir / "pkexec-deny").write_text("#!/bin/sh\nexit 126\n")
        (bindir / "pkexec-deny").chmod(0o755)
        self.home = self.t / "home"
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "cfg"),
                        XDG_CACHE_HOME=str(self.home / "cache"), SUMI_SDDM_HELPER=str(HELPER),
                        SUMI_SDDM_PKEXEC=str(bindir / "pkexec"))
        self.deny = str(bindir / "pkexec-deny")

    def cli(self, *args, env=None, rc=0):
        p = subprocess.run([sys.executable, "-B", str(CLI), *args, "--json"], env=env or self.env,
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return json.loads(p.stdout)

    def test_apply_status_activate_through_cli(self):
        self.cli("config", "set", "clockFormat=12h", "accentColor=#ff8800")
        src = self.t / "pic.png"
        png(src, 800, 600)
        self.cli("wallpaper", "set", str(src))
        st = self.cli("system", "status")
        self.assertEqual((st["installed"], st["inSync"]), (True, False))
        d = self.cli("system", "apply")
        self.assertTrue(d["changed"])
        self.assertEqual(d["stamp"], self.cli("config", "show")["stamp"])
        st = self.cli("system", "status")
        self.assertTrue(st["inSync"], st)
        self.cli("config", "set", "clockFormat=24h")
        self.assertFalse(self.cli("system", "status")["inSync"], "un cambio posterior se nota")
        self.assertEqual(self.cli("system", "activate")["activeTheme"], "sumi")
        self.assertEqual(self.cli("system", "deactivate")["activeTheme"], "orbital")

    def test_denied_and_helper_errors(self):
        env = dict(self.env, SUMI_SDDM_PKEXEC=self.deny)
        self.assertEqual(self.cli("system", "apply", env=env, rc=1)["code"], "denied")
        shutil.rmtree(self.theme)
        self.assertEqual(self.cli("system", "apply", rc=1)["code"], "missing")
        env = dict(self.env, SUMI_SDDM_HELPER=str(self.t / "nope"))
        self.assertEqual(self.cli("system", "status", env=env, rc=1)["code"], "missing")


if __name__ == "__main__":
    unittest.main()

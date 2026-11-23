"""`sumi-sddm avatar` con un AccountsService falso (busctl falso): validación, recorte con Qt, límites y errores.
No toca la cuenta real.
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "tools" / "sumi-sddm"

FAKE_BUSCTL = r'''#!/usr/bin/env python3
# AccountsService falso: guarda IconFile en STATE y copia el icono a ICONS, como el de verdad.
import json, os, shutil, sys
state, icons = os.environ["FAKE_ACCOUNTS_STATE"], os.environ["FAKE_ACCOUNTS_ICONS"]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
st = json.load(open(state)) if os.path.exists(state) else {"IconFile": os.environ["HOME"] + "/.face"}
if os.environ.get("FAKE_ACCOUNTS_DOWN"):
    print("Failed to activate service 'org.freedesktop.Accounts': timed out", file=sys.stderr); sys.exit(1)
if args[0] == "call" and args[4] == "FindUserByName":
    print(json.dumps({"type": "o", "data": ["/org/freedesktop/Accounts/User1000"]}))
elif args[0] == "get-property":
    print(json.dumps({"type": "s", "data": st["IconFile"]}))
elif args[0] == "call" and args[4] == "SetIconFile":
    src = args[6]
    if src == "":
        st["IconFile"] = os.environ["HOME"] + "/.face"
        if os.path.exists(icons + "/me"): os.unlink(icons + "/me")
    else:
        if os.path.getsize(src) > 1048576:
            print("Call failed: file too large", file=sys.stderr); sys.exit(1)
        shutil.copyfile(src, icons + "/me"); st["IconFile"] = icons + "/me"
    json.dump(st, open(state, "w"))
else:
    sys.exit(2)
'''


def png(path: Path, w: int, h: int) -> Path:
    raw = b"".join(b"\x00" + bytes(c for x in range(w) for c in ((x * 7) % 256, (y * 5) % 256, 120))
                   for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    return path


class AvatarTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = Path(self.tmp.name)
        (self.t / "icons").mkdir()
        fake = self.t / "busctl"
        fake.write_text(FAKE_BUSCTL)
        fake.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.t), XDG_CONFIG_HOME=str(self.t / "cfg"),
                        XDG_CACHE_HOME=str(self.t / "cache"), SUMI_SDDM_BUSCTL_TEST=str(fake),
                        FAKE_ACCOUNTS_STATE=str(self.t / "accounts.json"), FAKE_ACCOUNTS_ICONS=str(self.t / "icons"))

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, *args, rc=0, env=None):
        p = subprocess.run([sys.executable, "-B", str(CLI), "avatar", *args, "--json"], env=env or self.env,
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
        return json.loads(p.stdout)

    def test_info_set_clear(self):
        d = self.cli("info")
        self.assertEqual((d["exists"], d["sddmUses"]), (False, ""))
        src = png(self.t / "photo.png", 1200, 800)
        d = self.cli("set", str(src))
        self.assertTrue(d["exists"])
        self.assertEqual(d["iconFile"], str(self.t / "icons" / "me"))
        self.assertEqual((d["source"]["width"], d["source"]["height"], d["size"]), (1200, 800, 512))
        icon = (self.t / "icons" / "me").read_bytes()
        self.assertEqual(icon[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", icon[16:24]), (512, 512), "recortado a un cuadrado de 512")
        self.assertLessEqual(len(icon), 1024 * 1024)
        d = self.cli("clear")
        self.assertFalse(Path(d["iconFile"]).exists())
        self.assertFalse(self.cli("info")["exists"])

    def test_rejections(self):
        self.assertEqual(self.cli("set", str(png(self.t / "tiny.png", 40, 40)), rc=1)["code"], "invalid")
        (self.t / "bad.jpg").write_bytes(b"not an image at all, really not" * 4)
        self.assertEqual(self.cli("set", str(self.t / "bad.jpg"), rc=1)["code"], "invalid")
        (self.t / "link.png").symlink_to(png(self.t / "ok.png", 200, 200))
        self.assertEqual(self.cli("set", str(self.t / "link.png"), rc=1)["code"], "invalid")
        self.assertFalse((self.t / "icons" / "me").exists())

    def test_accounts_service_down(self):
        env = dict(self.env, FAKE_ACCOUNTS_DOWN="1")
        self.assertEqual(self.cli("info", rc=1, env=env)["code"], "missing")


if __name__ == "__main__":
    unittest.main()

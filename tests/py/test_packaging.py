"""El PKGBUILD: versión igual a VERSION, nada calculado con herramientas externas (namcap no las tiene) y sus dos
`package_*()`: el tema con la CLI usable en /usr/lib/sumi-sddm, y el editor (se ejecutan en un directorio temporal,
sin root ni makepkg)."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


class PackagingTest(unittest.TestCase):
    def test_pkgver_matches_version(self):
        text = (ROOT / "packaging" / "arch" / "PKGBUILD").read_text()
        m = re.search(r"^pkgver=(\S+)$", text, re.M)
        self.assertIsNotNone(m, "pkgver literal")
        self.assertEqual(m.group(1), (ROOT / "VERSION").read_text().strip())

    def test_license_files_exist(self):
        text = (ROOT / "packaging" / "arch" / "PKGBUILD").read_text()
        self.assertIn('"$src/LICENSE"', text)
        self.assertIn("license=('MIT' 'OFL-1.1')", text)
        self.assertTrue((ROOT / "LICENSE").is_file())



def build(pkgdir: Path, name: str) -> None:
    """Lo que hace makepkg con un subpaquete: `package_<name>` con pkgdir y pkgname."""
    arch = ROOT / "packaging" / "arch"
    script = 'set -e; source ./PKGBUILD; startdir="$1"; pkgdir="$2"; pkgname="$3"; "package_$3"'
    subprocess.run(["bash", "-c", script, "bash", str(arch), str(pkgdir), name], cwd=arch, check=True,
                   capture_output=True, text=True, timeout=60)


class PackageContentTest(unittest.TestCase):
    """`package()` del PKGBUILD en un pkgdir temporal: lo que pacman instalaría, sin makepkg ni fakeroot."""

    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory(prefix="sumi-pkg-")
        cls.pkg = Path(cls._tmp.name) / "pkg"
        cls.editor_pkg = Path(cls._tmp.name) / "pkg-editor"
        build(cls.pkg, "sumi-sddm")
        build(cls.editor_pkg, "sumi-sddm-editor")
        cls.lib = cls.pkg / "usr" / "lib" / "sumi-sddm"
        cls.home = Path(cls._tmp.name) / "home"
        cls.home.mkdir()

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def cli(self, *args: str) -> subprocess.CompletedProcess:
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home), "LANG": "C.UTF-8",
               "XDG_CONFIG_HOME": str(self.home / ".config"), "XDG_CACHE_HOME": str(self.home / ".cache")}
        return subprocess.run([sys.executable, "-I", "-B", str(self.lib / "tools" / "sumi-sddm"), *args],
                              env=env, capture_output=True, text=True, timeout=60)

    def test_cli_files(self):
        for f in (ROOT / "tools" / "sumiconf").glob("*.py"):
            self.assertTrue((self.lib / "tools" / "sumiconf" / f.name).is_file(), f.name)
        for f in (ROOT / "tools" / "harness").glob("*.qml"):
            self.assertTrue((self.lib / "tools" / "harness" / f.name).is_file(), f.name)
        for rel in ("tools/sumi-sddm", "VERSION", "schema/config-schema.json", "docs/CONFIG.md", "sumi-sddm-helper"):
            self.assertTrue((self.lib / rel).is_file(), rel)
        self.assertTrue(os.access(self.lib / "tools" / "sumi-sddm", os.X_OK))
        self.assertEqual(list(self.pkg.rglob("__pycache__")), [])
        self.assertFalse((self.lib / "tests").exists(), "con tests/ la CLI se creería un checkout")

    def test_theme_link_points_at_installed_theme(self):
        link = self.lib / "theme" / "sumi"
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), "../../../share/sddm/themes/sumi")
        self.assertEqual(link.resolve(), (self.pkg / "usr/share/sddm/themes/sumi").resolve())
        self.assertTrue((link / "Main.qml").is_file())

    def test_launcher(self):
        bin_ = self.pkg / "usr" / "bin" / "sumi-sddm"
        self.assertTrue(bin_.is_file() and not bin_.is_symlink())
        self.assertTrue(os.access(bin_, os.X_OK))
        lines = bin_.read_text().splitlines()
        self.assertEqual(lines[0], "#!/bin/sh")
        self.assertEqual(lines[-1], 'exec /usr/bin/python3 -I -B /usr/lib/sumi-sddm/tools/sumi-sddm "$@"')

    def test_version_reports_system(self):
        p = self.cli("version", "--json")
        self.assertEqual(p.returncode, 0, p.stderr)
        doc = json.loads(p.stdout)
        self.assertEqual((doc["ok"], doc["api"], doc["kind"]), (True, 1, "system"))
        self.assertEqual(doc["version"], (ROOT / "VERSION").read_text().strip())

    def test_user_commands_work(self):
        p = self.cli("config", "schema", "--json")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue(json.loads(p.stdout)["keys"])
        p = self.cli("config", "set", "accentColor=#ff8800", "--json")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((self.home / ".config" / "sumi-sddm" / "theme.conf.user").is_file())
        self.assertFalse(any(self.lib.rglob("theme.conf.user")), "la CLI no escribe en el paquete")

    @unittest.skipUnless(Path("/usr/lib/qt6/bin/qml").exists() or shutil.which("qml"), "sin qml")
    def test_preview_ignores_applied_config(self):
        # El helper deja theme.conf.user en el tema instalado; la vista previa sólo enseña lo del usuario.
        applied = self.pkg / "usr/share/sddm/themes/sumi/theme.conf.user"
        applied.write_text("[General]\naccentColor=#00ff00\n")
        try:
            p = self.cli("preview", "--size", "640x400", "--json")
        finally:
            applied.unlink()
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        self.assertTrue(Path(json.loads(p.stdout)["png"]).is_file())
        staged = self.home / ".cache" / "sumi-sddm" / "preview" / "sumi"
        self.assertTrue((staged / "Main.qml").is_file())
        conf = staged / "theme.conf.user"     # existe sólo si otra prueba ya guardó config del usuario
        self.assertNotIn("#00ff00", conf.read_text() if conf.exists() else "")

    def test_dev_commands_refused(self):
        for cmd in ("gen", "lint", "test", "check"):
            p = self.cli(cmd)
            self.assertEqual(p.returncode, 2, cmd)
            self.assertIn("sólo está disponible en el repositorio", p.stderr + p.stdout, cmd)

    def test_split(self):
        text = (ROOT / "packaging" / "arch" / "PKGBUILD").read_text()
        self.assertIn("pkgname=('sumi-sddm' 'sumi-sddm-editor')", text)
        self.assertFalse(list(self.pkg.rglob("sumi_sddm_editor")), "el tema no lleva el editor")
        self.assertNotIn("pyside6", text.split("package_sumi-sddm()")[1].split("package_sumi-sddm-editor()")[0],
                         "el tema nunca depende de PySide6")

    def test_editor_files(self):
        lib = self.editor_pkg / "usr/lib/sumi-sddm/editor"
        src = ROOT / "editor" / "sumi_sddm_editor"
        want = sorted(f.name for f in src.iterdir() if f.suffix in (".py", ".qml") or f.name == "qmldir")
        self.assertEqual(sorted(f.name for f in (lib / "sumi_sddm_editor").iterdir()), want)
        self.assertTrue(os.access(lib / "sumi-sddm-editor", os.X_OK))
        bin_ = self.editor_pkg / "usr/bin/sumi-sddm-editor"
        self.assertEqual(bin_.read_text().splitlines()[-1],
                         'exec /usr/bin/python3 -I -B /usr/lib/sumi-sddm/editor/sumi-sddm-editor "$@"')
        self.assertTrue((self.editor_pkg / "usr/share/icons/hicolor/scalable/apps/sumi-sddm-editor.svg").is_file())
        self.assertTrue((self.editor_pkg / "usr/share/licenses/sumi-sddm-editor/LICENSE").is_file())
        self.assertEqual(list(self.editor_pkg.rglob("__pycache__")), [])
        # sólo lo del editor: nada del tema, la CLI ni el helper
        self.assertFalse((self.editor_pkg / "usr/share/sddm").exists())
        self.assertFalse((self.editor_pkg / "usr/lib/sumi-sddm/tools").exists())

    def test_editor_desktop_entry(self):
        desktop = self.editor_pkg / "usr/share/applications/sumi-sddm-editor.desktop"
        text = desktop.read_text()
        self.assertIn("Exec=sumi-sddm-editor\n", text)
        self.assertIn("Icon=sumi-sddm-editor\n", text)
        self.assertNotIn("NotShowIn", text, "D5: también se enseña con Sumi Shell")
        if shutil.which("desktop-file-validate"):
            p = subprocess.run(["desktop-file-validate", str(desktop)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    @unittest.skipUnless(subprocess.run([sys.executable, "-c", "import PySide6.QtQuick"],
                                        capture_output=True).returncode == 0, "sin PySide6")
    def test_editor_starts_from_the_package(self):
        # La ventana del paquete, sin la CLI en el PATH: debe cargar sin avisos de QML y decir «missing».
        code = r"""
import sys
sys.path.insert(0, sys.argv[1])
from PySide6.QtCore import QEventLoop, QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from sumi_sddm_editor.backend import Backend
msgs = []
qInstallMessageHandler(lambda m, c, t: msgs.append(t))
QQuickStyle.setStyle("Fusion")
app = QGuiApplication([])
b = Backend()
e = QQmlApplicationEngine()
e.setInitialProperties({"backend": b})
e.load(QUrl.fromLocalFile(sys.argv[1] + "/sumi_sddm_editor/Main.qml"))
b.load()
for _ in range(20):
    app.processEvents(QEventLoop.AllEvents, 20)
print(bool(e.rootObjects()), b.status, [m for m in msgs if "qml" in m.lower()])
del e
"""
        env = {"PATH": "/nonexistent", "HOME": str(self.home), "QT_QPA_PLATFORM": "offscreen",
               "QT_QUICK_BACKEND": "software", "LANG": "C.UTF-8"}
        p = subprocess.run([sys.executable, "-I", "-B", "-c", code, str(self.editor_pkg / "usr/lib/sumi-sddm/editor")],
                           env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(p.stdout.strip(), "True missing []", p.stderr[-2000:])

    def test_install_user_refused(self):
        p = self.cli("install", "--user", "--json")
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout)["code"], "unsupported")


if __name__ == "__main__":
    unittest.main()

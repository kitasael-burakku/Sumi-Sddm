"""El PKGBUILD: versión igual a VERSION y nada calculado con herramientas externas (namcap no las tiene)."""
from __future__ import annotations

import re
import sys
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
        self.assertIn("LICENSE-PENDING", text)
        self.assertTrue((ROOT / "LICENSE-PENDING").is_file())


if __name__ == "__main__":
    unittest.main()

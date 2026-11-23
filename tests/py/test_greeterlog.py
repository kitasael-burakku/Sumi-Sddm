"""`system log`: resumen del journal del greeter (registros sintéticos; no lee el journal real)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from sumiconf import greeterlog  # noqa: E402

THEME = "Loading file:///usr/share/sddm/themes/sumi/Main.qml..."
READY = "sumi-sddm: ready users=1 sessions=2 primary=true clock=24h custom=7"


def g(msg, pid="884", uid="960", t=100):
    return {"id": "sddm-greeter-qt6", "pid": pid, "uid": uid, "message": msg, "time": t}


def d(msg, t=100):
    return {"id": "sddm", "pid": "821", "uid": "0", "message": msg, "time": t}


class GreeterLogTest(unittest.TestCase):
    def test_clean_login(self):
        s = greeterlog.summarize([g(THEME), g(READY), d("Message received from greeter: Connect"),
                                  d("Message received from greeter: Login"),
                                  d('Session "/usr/share/wayland-sessions/hyprland.desktop" selected, command: "x"'),
                                  g("Message received from daemon: LoginSucceeded")], 7, uid="960")
        self.assertTrue(s["sumiOk"])
        self.assertEqual(s["logins"], {"succeeded": 1, "failed": 0})
        self.assertEqual(s["sessions"], ["hyprland.desktop"])

    def test_failed_then_ok_and_reboot_request(self):
        # Como lo registra SDDM 0.21 (visto en la prueba B1): LoginFailed dos veces por intento y usuario vacío.
        s = greeterlog.summarize([g(THEME), g(READY), d("Message received from greeter: Login"),
                                  d('Authentication error: SDDM::Auth::ERROR_AUTHENTICATION "Authentication failure"'),
                                  d('Authentication for user  ""  failed'),
                                  g('Information Message received from daemon:  "Authentication failure"'),
                                  g("Message received from daemon: LoginFailed"),
                                  g("Message received from daemon: LoginFailed"),
                                  d("Message received from greeter: Login"),
                                  d('Authentication for user  "someone"  successful'),
                                  g("Message received from daemon: LoginSucceeded"),
                                  d("Message received from greeter: Reboot")], 7, uid="960")
        self.assertEqual(s["logins"], {"succeeded": 1, "failed": 1})
        self.assertEqual(s["informationMessages"], 1)
        self.assertEqual(s["requests"], {"Login": 2, "Reboot": 1})

    def test_qml_warning_and_wrong_custom_are_problems(self):
        s = greeterlog.summarize([g(THEME), g(READY.replace("custom=7", "custom=3")),
                                  g("file:///usr/share/sddm/themes/sumi/components/Greeter.qml:10: TypeError: x")],
                                 7, uid="960")
        self.assertFalse(s["sumiOk"])
        probs = s["greeters"][0]["problems"]
        self.assertTrue(any("TypeError" in p for p in probs) and any("custom=7" in p for p in probs))

    def test_test_mode_windows_and_other_themes_do_not_count(self):
        s = greeterlog.summarize([g(THEME, pid="5", uid="1000"), g(READY.replace("custom=7", "custom=1"), pid="5",
                                                                     uid="1000"),
                                  g("Loading file:///usr/share/sddm/themes/orbital/Main.qml...", pid="9")],
                                 7, uid="960")
        self.assertEqual([x["sumi"] for x in s["greeters"]], [False])
        self.assertFalse(s["sumiOk"], "sin un Sumi real no hay nada que dar por bueno")

    def test_no_usernames_in_summary(self):
        s = greeterlog.summarize([g(THEME), g(READY), d('Authentication for user  "kitasa"  successful')], 7, uid="960")
        self.assertNotIn("kitasa", repr(s))


if __name__ == "__main__":
    unittest.main()

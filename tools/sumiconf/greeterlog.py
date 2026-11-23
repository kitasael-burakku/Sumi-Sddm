"""`sumi-sddm system log`: qué pasó en la pantalla de inicio de un arranque, leído del journal (sin root).

Se juzga cada greeter que cargó Sumi con la misma regla que la prueba previa del helper (`probe.judge`: el tema llega
a `sumi-sddm: ready`, con el `custom` esperado y sin avisos QML) y se resume lo que pidió el greeter al daemon
(Login, Reboot, PowerOff…) y cómo respondió (LoginSucceeded / LoginFailed). No sale ningún nombre de usuario,
contraseña ni valor de configuración: sólo recuentos, la sesión elegida y los avisos del tema.
"""
from __future__ import annotations

import json
import pwd
import re
import subprocess
from collections import Counter

from . import probe

GREETER_ID = "sddm-greeter-qt6"
DAEMON_ID = "sddm"
THEME_RE = re.compile(r"Loading (file://\S+/)Main\.qml")
FROM_GREETER_RE = re.compile(r"Message received from greeter: (\w+)")
FROM_DAEMON_RE = re.compile(r"Message received from daemon: (\w+)")
SESSION_RE = re.compile(r'Session "([^"]+)" selected')


def read_journal(boot: int) -> list[dict]:
    """Entradas del greeter y del daemon de ese arranque (0 = el actual, -1 = el anterior…)."""
    p = subprocess.run(["journalctl", "-b", str(boot), "-o", "json", "--no-pager",
                        f"SYSLOG_IDENTIFIER={GREETER_ID}", "+", f"SYSLOG_IDENTIFIER={DAEMON_ID}"],
                       capture_output=True, text=True, timeout=60)
    out = []
    for line in p.stdout.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        msg = d.get("MESSAGE", "")
        if isinstance(msg, list):
            msg = bytes(msg).decode("utf-8", "replace")
        out.append({"id": d.get("SYSLOG_IDENTIFIER", ""), "pid": str(d.get("_PID", "")), "message": str(msg),
                    "uid": str(d.get("_UID", "")), "time": int(d.get("__REALTIME_TIMESTAMP", "0")) // 1_000_000})
    return out


def greeter_uid() -> str:
    try:
        return str(pwd.getpwnam("sddm").pw_uid)
    except KeyError:
        return ""


def summarize(entries: list[dict], expect_custom: int | None, theme_name: str = "sumi",
              uid: str | None = None) -> dict:
    """Sólo cuentan los greeters del usuario `sddm` (los de verdad): las ventanas `--test-mode` corren como el
    usuario, sobre copias con otra configuración."""
    uid = greeter_uid() if uid is None else uid
    greeters: dict[str, list[str]] = {}
    times: dict[str, int] = {}
    requests: Counter = Counter()
    replies: Counter = Counter()
    sessions: list[str] = []
    for e in entries:
        m = e["message"]
        if e["id"] == GREETER_ID:
            if uid and e.get("uid") != uid:
                continue
            greeters.setdefault(e["pid"], []).append(m)
            times.setdefault(e["pid"], e["time"])
            r = FROM_DAEMON_RE.search(m)
            if r:
                replies[r.group(1)] += 1
        elif e["id"] == DAEMON_ID:
            r = FROM_GREETER_RE.search(m)
            if r:
                requests[r.group(1)] += 1
            s = SESSION_RE.search(m)
            if s:
                sessions.append(s.group(1).rsplit("/", 1)[-1])
    runs = []
    for pid, lines in greeters.items():
        theme = next((t.group(1) for l in lines for t in [THEME_RE.search(l)] if t), "")
        if not theme.rstrip("/").endswith("/" + theme_name):
            runs.append({"pid": pid, "time": times[pid], "theme": theme, "sumi": False})
            continue
        ok, problems, ready = probe.judge(lines, theme, expect_custom)
        runs.append({"pid": pid, "time": times[pid], "theme": theme, "sumi": True, "ok": ok,
                     "ready": ready.strip(), "problems": problems[:10]})
    sumi = [r for r in runs if r["sumi"]]
    return {"greeters": runs, "sumiOk": bool(sumi) and all(r["ok"] for r in sumi),
            "requests": dict(requests), "logins": {"succeeded": replies.get("LoginSucceeded", 0),
                                                   "failed": replies.get("LoginFailed", 0)},
            "informationMessages": replies.get("InformationMessage", 0), "sessions": sessions,
            "expectCustom": expect_custom}

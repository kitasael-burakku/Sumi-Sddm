#!/usr/bin/env python3
"""Banco de Settings → Login screen (Sumi SDDM) sobre una COPIA del árbol de Sumi Shell.

    review.py ÁRBOL SALIDA [--scenario real|missing|incompatible|terminal|all] [--cli RUTA]

Cada escenario: copia privada del árbol, HOME/XDG privados, sin compositor ni buses (offscreen, `qs -p`), falsos
delante de lo que tocaría el sistema (systemctl, loginctl, pkexec…). `sumi-sddm` en el PATH según el escenario:
  real / terminal   la CLI del repositorio de Sumi SDDM (--cli para otra), escribiendo SÓLO en el XDG privado.
                    El «sistema» también es falso: un tema instalado en una raíz privada, un pkexec que ejecuta el
                    helper del repositorio sobre esa raíz (SUMI_SDDM_HELPER_ROOT), un greeter falso y un
                    AccountsService falso: Apply / Use / Restore y el avatar nunca tocan el sistema real.
  incompatible      un falso que responde api 2
  missing           ninguna
No abre ventanas en la sesión, no usa el bus de sesión y no toca el vivo, dotfiles ni ~/.config/sumi-sddm.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]                  # Sumi-SDDM
SCENARIOS = ["real", "missing", "incompatible", "terminal"]
NOISE = ("qml: REVIEW ",)


def strip_inhibitor(tree: Path) -> None:
    """El inhibidor de reposo necesita una layer-shell incluso apagado: fuera sólo en esta copia (como el banco
    de la navegación de Settings)."""
    session = tree / "services/Session.qml"
    src = session.read_text()
    begin = src.index("    PanelWindow {\n        id: inhibitWin")
    end = src.index("    /**\n     * The logind inhibitor", begin)
    session.write_text(src[:begin] + src[end:])


FAKE_GREETER = r'''#!/usr/bin/env python3
import sys
sys.path.insert(0, %(tools)r)
from pathlib import Path
from sumiconf import Schema, ini, probe
theme = Path(sys.argv[sys.argv.index("--theme") + 1])
conf = theme / "theme.conf.user"
raw = ini.parse(conf.read_text()) if conf.exists() else {}
print("qml: sumi-sddm: ready users=1 sessions=1 primary=true clock=24h custom=%%d" %% probe.expected_custom(Schema.load(), raw))
'''

FAKE_BUSCTL = r'''#!/usr/bin/env python3
import json, os, shutil, sys
state, icons = os.environ["FAKE_ACCOUNTS_STATE"], os.environ["FAKE_ACCOUNTS_ICONS"]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
st = json.load(open(state)) if os.path.exists(state) else {"IconFile": os.environ["HOME"] + "/.face"}
if args[0] == "call" and args[4] == "FindUserByName":
    print(json.dumps({"type": "o", "data": ["/org/freedesktop/Accounts/User1000"]}))
elif args[0] == "get-property":
    print(json.dumps({"type": "s", "data": st["IconFile"]}))
elif args[0] == "call" and args[4] == "SetIconFile":
    if args[6] == "":
        st["IconFile"] = os.environ["HOME"] + "/.face"
        if os.path.exists(icons + "/me"): os.unlink(icons + "/me")
    else:
        shutil.copyfile(args[6], icons + "/me"); st["IconFile"] = icons + "/me"
    json.dump(st, open(state, "w"))
'''


def fake_system(private: Path) -> dict:
    """Raíz falsa con el tema «instalado» y orbital activo, pkexec/greeter/AccountsService falsos."""
    root = private / "sysroot"
    themes = root / "usr/share/sddm/themes"
    shutil.copytree(REPO / "theme" / "sumi", themes / "sumi")
    (themes / "orbital").mkdir(parents=True)
    (themes / "orbital" / "metadata.desktop").write_text("[SddmGreeterTheme]\nName=orbital\n")
    (root / "etc").mkdir()
    (root / "etc/sddm.conf").write_text("[Theme]\nCurrent=orbital\n")
    fb = private / "fakesys"
    fb.mkdir()
    (fb / "greeter").write_text(FAKE_GREETER % {"tools": str(REPO / "tools")})
    (fb / "pkexec").write_text("#!/bin/sh\nexec /usr/bin/python3 -I -B \"$@\"\n")
    (fb / "busctl").write_text(FAKE_BUSCTL)
    for f in fb.iterdir():
        f.chmod(0o755)
    (private / "icons").mkdir()
    return {"SUMI_SDDM_HELPER": str(REPO / "system" / "sumi-sddm-helper"), "SUMI_SDDM_PKEXEC": str(fb / "pkexec"),
            "SUMI_SDDM_HELPER_ROOT": str(root), "SUMI_SDDM_HELPER_PROBE": str(fb / "greeter"),
            "SUMI_SDDM_BUSCTL_TEST": str(fb / "busctl"), "FAKE_ACCOUNTS_STATE": str(private / "accounts.json"),
            "FAKE_ACCOUNTS_ICONS": str(private / "icons")}


def run(tree: Path, out: Path, scenario: str, cli: str | None, reload_from: Path | None = None,
        manifest: Path | None = None) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sddm-bench-") as tmp:
        private = Path(tmp)
        work = private / "sumi"
        shutil.copytree(reload_from or tree, work, symlinks=True)
        strip_inhibitor(work)
        overlay = private / "overlay"
        if reload_from:
            for rel in json.loads(manifest.read_text())["files"]:
                (overlay / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(tree / rel, overlay / rel)
        for name in ("review.qml", "sddm-checks.js"):
            shutil.copyfile(HERE / name, work / name)
        env = {"LANG": "C.UTF-8", "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
               "QS_NO_RELOAD_POPUP": "1", "HOME": str(private), "XDG_DATA_DIRS": "/usr/share", "NO_COLOR": "1",
               "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + tmp + "/no-session",
               "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + tmp + "/no-system",
               "SDDM_REVIEW_SCENARIO": scenario, "SDDM_REVIEW_OUT": str(out),
               "SDDM_REVIEW_OVERLAY": str(overlay) if reload_from else ""}
        for key, folder in [("XDG_CONFIG_HOME", "config"), ("XDG_STATE_HOME", "state"), ("XDG_DATA_HOME", "data"),
                            ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "run"), ("XDG_CONFIG_DIRS", "etc")]:
            (private / folder).mkdir(mode=0o700)
            env[key] = str(private / folder)
        fake = private / "fakebin"
        fake.mkdir()
        for name in ("systemctl", "loginctl", "ddcutil", "gsettings", "hyprctl", "nmcli", "wpctl", "pactl",
                     "playerctl", "pkexec", "xdg-open", "curl", "matugen", "bluetoothctl", "brightnessctl",
                     "notify-send", "awww", "sddm-greeter-qt6"):
            (fake / name).symlink_to("/usr/bin/false")
        bindir = private / "bin"
        bindir.mkdir()
        if scenario in ("real", "terminal"):
            real = cli or str(REPO / "tools" / "sumi-sddm")
            (bindir / "sumi-sddm").write_text(f"#!/bin/sh\nexec /usr/bin/python3 -B {json.dumps(str(Path(real).resolve()))}"
                                              " \"$@\"\n")
            (bindir / "sumi-sddm").chmod(0o755)
            env.update(fake_system(private))
        elif scenario == "incompatible":
            (bindir / "sumi-sddm").write_text('#!/bin/sh\necho \'{"ok": true, "api": 2, "version": "9.0.0"}\'\n')
            (bindir / "sumi-sddm").chmod(0o755)
        else:
            # missing: /usr/bin/sumi-sddm (el paquete, desde 0.5.0) está en el PATH; un falso que responde como `env`
            # cuando la orden no existe (2026-11-23)
            (bindir / "sumi-sddm").write_text("#!/bin/sh\nexit 127\n")
            (bindir / "sumi-sddm").chmod(0o755)
        env["PATH"] = f"{fake}:{bindir}:/usr/bin"
        logo = private / ".config/fastfetch/fastfetchlogo/minimaru.png"
        logo.parent.mkdir(parents=True)
        Image.new("RGB", (8, 8), (70, 80, 100)).save(logo)
        # Un wallpaper de prueba (degradado) para `wallpaper set`.
        pic = Image.new("RGB", (1600, 900))
        pic.putdata([(40 + x * 180 // 1600, 70 + y * 120 // 900, 140) for y in range(900) for x in range(1600)])
        pic.save(private / "pic.png")
        cfg = private / "config/sumi-shell"
        cfg.mkdir()
        settings = {"schemaVersion": 4,
                    "shell": {"interface": {"scale": 0.8}, "animations": {"mode": "off"},
                              "integrations": {"polkitAgent": False, "notificationServer": False}},
                    "theme": {"desktopSync": "off"}}
        if scenario == "terminal":
            settings["theme"].update({"style": {"name": "terminal"}, "typography": {"textSize": 1.15}})
        (cfg / "settings.json").write_text(json.dumps(settings))

        result = subprocess.run(["qs", "-p", str(work / "review.qml")], env=env, capture_output=True, text=True,
                                timeout=240)
        log = result.stdout + result.stderr
        (out / f"{scenario}.log").write_text(log)
        messages = [l.split("REVIEW ", 1)[1] for l in log.splitlines() if "qml: REVIEW " in l]
        if not messages:
            raise SystemExit(f"[{scenario}] sin informe del banco:\n" + log[-3000:])
        report = json.loads(messages[-1])
        report["qmlWarnings"] = [l for l in log.splitlines() if (" WARN" in l or " ERROR" in l)
                                 and (".qml:" in l or "TypeError" in l or "ReferenceError" in l or "@" in l)]
        report["loads"] = log.count("Configuration Loaded")
        if reload_from and (report["loads"] != 2 or "qml: RELOAD_BASE" not in log):
            report["error"] = report["error"] or f"la recarga en caliente no completó las dos cargas ({report['loads']})"
        shell_settings = (cfg / "settings.json").read_text()
        report["settingsJsonUntouched"] = "sddm" not in shell_settings.lower()
        conf = private / "config/sumi-sddm/theme.conf.user"
        report["sddmConf"] = conf.read_text() if conf.exists() else None
        sysconf = private / "sysroot/etc/sddm.conf"
        report["fakeSddmConf"] = sysconf.read_text() if sysconf.exists() else None
        (out / f"{scenario}.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tree", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--scenario", default="all", choices=SCENARIOS + ["all"])
    ap.add_argument("--cli")
    ap.add_argument("--reload-from", type=Path, help="árbol de ANTES: arranca con él y recarga en caliente con las "
                    "rutas de --manifest tomadas de ÁRBOL")
    ap.add_argument("--manifest", type=Path)
    args = ap.parse_args()
    home = Path.home()
    tree = args.tree.resolve()
    if tree.is_relative_to(home / ".config/quickshell") or tree.is_relative_to(home / "Projects/dotfiles"):
        raise SystemExit("review.py: usa una copia, no el vivo ni dotfiles")
    failed = False
    for sc in SCENARIOS if args.scenario == "all" else [args.scenario]:
        r = run(tree, args.output.resolve(), sc, args.cli, args.reload_from and args.reload_from.resolve(),
                args.manifest)
        ok = not r["error"] and not r["qmlWarnings"] and r["settingsJsonUntouched"]
        failed |= not ok
        print(f"[{sc}] {'OK' if ok else 'FALLO'}: {r['count']} comprobaciones, {len(r['qmlWarnings'])} avisos QML, "
              f"cargas {r['loads']}, settings.json {'intacto' if r['settingsJsonUntouched'] else 'TOCADO'}")
        if r["error"]:
            print("   error: " + r["error"].splitlines()[0])
        for wline in r["qmlWarnings"][:12]:
            print("   ! " + wline)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

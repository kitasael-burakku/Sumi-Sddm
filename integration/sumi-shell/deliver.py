#!/usr/bin/env python3
"""Entrega por rutas de Settings → Login screen (Sumi SDDM) en Sumi Shell, con guarda de hash, respaldo y vuelta atrás.

    deliver.py prepare                   construye el candidato desde las bases privadas y escribe el manifiesto
    deliver.py check                     estado de cada ruta en fuente (dotfiles) y vivo: base / candidate / changed
    deliver.py self-test                 ensayo completo sobre copias temporales (no toca fuente ni vivo)
    deliver.py apply [--apply]           sin --apply sólo comprueba; con --apply escribe fuente y vivo y verifica
                                         la recarga; si algo falla, revierte solo
    deliver.py rollback --bundle DIR [--apply]

Reglas (docs/PROCEDIMIENTOS.md de Quickshell): sólo las rutas del manifiesto; cada destino debe tener EXACTAMENTE
el hash de la base (si no, no se escribe nada); respaldo de todo antes de la primera escritura; escritura atómica;
diario; la vuelta atrás se niega si alguien editó después. `--apply` exige autorización específica de esta entrega.
Nunca hace commit en dotfiles ni reinicia la unidad; recarga en caliente con `qs ipc call sumi reload`.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

if not __debug__:
    raise SystemExit("Ejecuta sin -O para conservar las guardas")
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
HOME = Path.home()
PRIVATE = HOME / "Projects/Quickshell/.sddm-settings-20261122"
TREES = {"source": HOME / "Projects/dotfiles/quickshell/sumi", "live": HOME / ".config/quickshell/sumi"}
SETTINGS_JSON = HOME / ".config/sumi-shell/settings.json"
TAG = "sumi-sddm-settings-20261122"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
TEXT_INPUT = re.compile(r"\s*WARN qt\.qpa\.wayland\.textinput: virtual void QtWaylandClient::QWaylandTextInputv3::"
                        r"disableSurface\(wl_surface\*\) Trying to disable 0x[0-9a-fA-F]+ but 0x0 is focused")

spec = importlib.util.spec_from_file_location("sddm_edit", HERE / "edit.py")
edit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(edit)
PATHS = sorted(edit.EDITS) + list(edit.NEW_FILES)


# ── hashes, manifiesto, escritura ────────────────────────────────────────────────────────────────────────────────
def digest(p: Path) -> str | None:
    assert not p.is_symlink(), "No se sustituye un enlace: " + str(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None


def manifest() -> dict:
    return json.loads((PRIVATE / "manifest.json").read_text())


def build_candidate(base: Path, out: Path) -> None:
    """Candidato = sólo las rutas del manifiesto, desde la base, con edit.py."""
    for rel in edit.EDITS:
        (out / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / rel, out / rel)
    texts, problems = edit.plan(out)
    if problems:
        raise RuntimeError("edit.py no aplica sobre la base: " + "; ".join(problems))
    for rel, text in texts.items():
        (out / rel).write_text(text, encoding="utf-8")
    for rel in edit.NEW_FILES:
        (out / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(HERE / rel, out / rel)


def prepare() -> None:
    bases = {tag: PRIVATE / f"base-{tag}" for tag in TREES}
    for rel in edit.EDITS:
        hs = {tag: digest(b / rel) for tag, b in bases.items()}
        assert len(set(hs.values())) == 1 and None not in hs.values(), f"Las bases difieren o faltan: {rel} {hs}"
    cand = PRIVATE / "deliver-candidate"
    if cand.exists():
        assert cand.resolve().is_relative_to(PRIVATE.resolve())
        shutil.rmtree(cand)
    build_candidate(bases["live"], cand)
    files = {rel: {"base": digest(bases["live"] / rel), "candidate": digest(cand / rel)} for rel in PATHS}
    (PRIVATE / "manifest.json").write_text(json.dumps({"format": 1, "files": files}, indent=2) + "\n")
    print(f"manifiesto: {len(files)} rutas ({len(edit.NEW_FILES)} nuevas) → {PRIVATE / 'manifest.json'}")


def check(trees: dict, want: str | None = None) -> list:
    rows = []
    for tag, tree in trees.items():
        for rel, row in manifest()["files"].items():
            h = digest(tree / rel)
            rows.append((tag, rel, "base" if h == row["base"] else "candidate" if h == row["candidate"] else "changed"))
    if want is not None:
        bad = [r for r in rows if r[2] != want]
        assert not bad, f"Guarda: no están en «{want}»: {bad}; no se escribe nada"
    return rows


def atomic(source: Path, dest: Path, mode: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix="." + dest.name + ".sddm-", dir=dest.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(source.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, dest)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def apply(trees: dict, candidate: Path, bundle: Path) -> None:
    check(trees, "base")
    m = manifest()
    for rel, row in m["files"].items():
        assert digest(candidate / rel) == row["candidate"], "Candidato alterado: " + rel
    bundle.mkdir(parents=True, exist_ok=False)
    (bundle / "manifest.json").write_text(json.dumps(m, indent=2))
    (bundle / "trees.json").write_text(json.dumps({k: str(v) for k, v in trees.items()}, indent=2))
    for tag, tree in trees.items():  # respaldo de TODO antes de escribir nada
        for rel, row in m["files"].items():
            if row["base"] is not None:
                dst = bundle / tag / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(tree / rel, dst)
    check(trees, "base")
    journal = []
    try:
        for tag, tree in trees.items():
            for rel, row in m["files"].items():
                dest = tree / rel
                assert digest(dest) == row["base"], "Edición concurrente: " + str(dest)
                atomic(candidate / rel, dest, dest.stat().st_mode & 0o777 if dest.exists() else 0o644)
                journal.append({"tree": tag, "path": rel})
                (bundle / "journal.json").write_text(json.dumps(journal, indent=2))
        check(trees, "candidate")
    except Exception:
        for item in reversed(journal):  # reponer sólo lo nuestro; jamás pisar otra edición
            dest, row = trees[item["tree"]] / item["path"], m["files"][item["path"]]
            if digest(dest) != row["candidate"]:
                continue
            if row["base"] is None:
                dest.unlink()
            else:
                old = bundle / item["tree"] / item["path"]
                atomic(old, dest, old.stat().st_mode & 0o777)
        raise


def rollback(bundle: Path, write: bool = False) -> dict:
    m = json.loads((bundle / "manifest.json").read_text())
    trees = {k: Path(v) for k, v in json.loads((bundle / "trees.json").read_text()).items()}
    for tag, tree in trees.items():
        for rel, row in m["files"].items():
            assert digest(tree / rel) == row["candidate"], "Guarda de reversión (editado después): " + str(tree / rel)
            if row["base"] is not None:
                assert digest(bundle / tag / rel) == row["base"], "Respaldo alterado: " + rel
    if write:
        for tag, tree in trees.items():
            for rel, row in m["files"].items():
                dest = tree / rel
                assert digest(dest) == row["candidate"], "Edición concurrente: " + str(dest)
                if row["base"] is None:
                    dest.unlink()
                else:
                    old = bundle / tag / rel
                    atomic(old, dest, old.stat().st_mode & 0o777)
        for tree in trees.values():
            for rel, row in m["files"].items():
                assert digest(tree / rel) == row["base"]
        (bundle / "rolled-back").write_text("Reversión verificada por SHA-256\n")
    return trees


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="sddm-delivery-") as tmp:
        temp = Path(tmp)
        trees = {k: temp / k for k in TREES}
        m = manifest()
        for tag, tree in trees.items():
            for rel, row in m["files"].items():
                if row["base"] is not None:
                    (tree / rel).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(PRIVATE / f"base-{tag}" / rel, tree / rel)
        cand = PRIVATE / "deliver-candidate"
        apply(trees, cand, temp / "backup")
        check(trees, "candidate")
        rel = next(r for r, row in m["files"].items() if row["base"] is not None)
        dest = trees["source"] / rel
        good = dest.read_bytes()
        dest.write_text("later edit")
        try:
            rollback(temp / "backup")
        except AssertionError:
            pass
        else:
            raise AssertionError("La vuelta atrás no rechazó una edición posterior")
        assert dest.read_text() == "later edit"
        dest.write_bytes(good)
        rollback(temp / "backup")
        rollback(temp / "backup", True)
        check(trees, "base")
        for rel2, row in m["files"].items():
            if row["base"] is None:
                assert not (trees["live"] / rel2).exists(), "un archivo nuevo sobrevivió a la vuelta atrás"
        dest.write_text("concurrent edit")
        try:
            apply(trees, cand, temp / "refused")
        except AssertionError:
            pass
        else:
            raise AssertionError("La guarda no rechazó una edición ajena")
        assert dest.read_text() == "concurrent edit"
        for tree in trees.values():
            for rel2, row in m["files"].items():
                if row["base"] is None:
                    assert not (tree / rel2).exists(), "una entrega rechazada dejó un archivo nuevo"
        print("self-test: entrega, vuelta atrás en seco y real, rechazo de ediciones posteriores y concurrentes: OK")


# ── sesión: comprobar antes y verificar la recarga después ───────────────────────────────────────────────────────
def command(argv, timeout=20):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    return {"code": p.returncode, "stdout": p.stdout.strip(), "stderr": p.stderr.strip()}


def ipc(verb):
    r = command(["qs", "-c", "sumi", "ipc", "call", "sumi", verb])
    try:
        return json.loads(r["stdout"])
    except ValueError:
        return None


def service():
    r = command(["systemctl", "--user", "show", "sumi-shell", "-p", "MainPID", "-p", "NRestarts", "-p", "ActiveState"])
    assert r["code"] == 0, r
    return dict(s.split("=", 1) for s in r["stdout"].splitlines() if "=" in s)


def journal(cursor=None, limit=1):
    argv = ["journalctl", "--user", "-u", "sumi-shell", "--no-pager", "-o", "json"]
    argv += ["--after-cursor", cursor] if cursor else ["-n", str(limit)]
    r = command(argv)
    assert r["code"] == 0, r
    rows = []
    for line in r["stdout"].splitlines():
        if line.strip():
            j = json.loads(line)
            msg = j.get("MESSAGE", "")
            if isinstance(msg, list):
                msg = bytes(msg).decode(errors="replace")
            rows.append({"cursor": j["__CURSOR"], "message": ANSI.sub("", str(msg)), "pid": j.get("_PID")})
    return rows


def ready(timeout=25):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        s = ipc("status")
        store = ((s or {}).get("settings") or {}).get("store") if isinstance(s, dict) else None
        if isinstance(store, dict) and store.get("status") == "ready" and s.get("pid"):
            return s
        time.sleep(0.2)
    raise RuntimeError("No llegó un status estructurado con ConfigStore listo")


def preflight():
    status, svc = ready(), service()
    lock = ipc("lockStatus") or {}
    if lock.get("phase") != "unlocked":
        raise RuntimeError("La sesión está bloqueada o en transición: no se entrega")
    if svc["ActiveState"] != "active" or int(svc["MainPID"]) != int(status["pid"]):
        raise RuntimeError("La unidad y el IPC no identifican la misma sesión")
    known_text_input = any(TEXT_INPUT.fullmatch(r["message"]) for r in journal(limit=150))
    return svc, digest(SETTINGS_JSON), known_text_input


def reload_verified():
    deadline = time.monotonic() + 25
    while True:
        status = ready()
        cursor = journal()[-1]["cursor"]
        reply = command(["qs", "-c", "sumi", "ipc", "call", "sumi", "reload"])
        if reply["code"] != 0 or reply["stdout"].lower() == "false":
            raise RuntimeError(f"No se pudo pedir la recarga: {reply}")
        if reply["stdout"] != "Not ready to accept queries yet.":
            break
        if time.monotonic() > deadline:
            raise RuntimeError("El IPC siguió ocupado")
        time.sleep(0.2)
    pid = str(status["pid"])
    end = time.monotonic() + 25
    while time.monotonic() < end:
        logs = [r for r in journal(cursor) if r["pid"] == pid]
        if any("Configuration Loaded" in r["message"] for r in logs):
            break
        time.sleep(0.2)
    else:
        raise RuntimeError("No apareció «Configuration Loaded»")
    ready()
    time.sleep(1)
    logs = [r for r in journal(cursor) if r["pid"] == pid]
    warnings = [r["message"] for r in logs if re.search(
        r"WARN|ERROR|FATAL|Failed to load|Binding loop|TypeError|ReferenceError|Unable to assign", r["message"])]
    return status, logs, warnings


def reload_checked(baseline, bundle: Path, phase: str) -> dict:
    svc, settings_hash, known_text_input = baseline
    time.sleep(3)  # dejar pasar la recarga automática del vigilante tras la ráfaga de escrituras
    for attempt in range(1, 4):
        state, logs, warnings = reload_verified()
        if service() != svc or int(state["pid"]) != int(svc["MainPID"]) or digest(SETTINGS_JSON) != settings_hash:
            raise RuntimeError("Cambió la unidad, el PID o settings.json durante la entrega")
        (bundle / f"{phase}-reload-{attempt}.log").write_text("".join(r["message"] + "\n" for r in logs))
        loads = sum("Configuration Loaded" in r["message"] for r in logs)
        unexpected = [w for w in warnings if not (known_text_input and TEXT_INPUT.fullmatch(w))]
        if loads == 1 and not unexpected:
            return {"pid": int(state["pid"]), "restarts": int(svc["NRestarts"]), "attempts": attempt,
                    "settingsHash": settings_hash, "qmlWarnings": []}
        if any(re.search(r"\b(ERROR|FATAL)\b|Failed to load", w) for w in unexpected):
            break
    raise RuntimeError(f"Recarga sin validar: {unexpected}. Registros en {bundle}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["prepare", "check", "self-test", "apply", "rollback"])
    ap.add_argument("--apply", action="store_true", help="escribir de verdad (autorización de esta entrega)")
    ap.add_argument("--bundle", type=Path)
    a = ap.parse_args()
    if a.action == "prepare":
        prepare()
        return 0
    if a.action == "self-test":
        self_test()
        return 0
    if a.action == "rollback":
        if not a.bundle:
            ap.error("Falta --bundle")
        bundle = a.bundle.resolve()
        rollback(bundle)
        if a.apply:
            baseline = preflight()
            rollback(bundle, True)
            r = reload_checked(baseline, bundle, "rollback")
            (bundle / "rollback-result.json").write_text(json.dumps(r, indent=2) + "\n")
        print("Vuelta atrás " + ("aplicada y verificada" if a.apply else "comprobada en seco (no escribe)"))
        return 0
    rows = check(TREES)
    for row in rows:
        print("%-7s %-34s %s" % row)
    if a.action == "check":
        return 0
    check(TREES, "base")
    if not a.apply:
        print("Sólo lectura: todas las rutas están en la base. --apply exige autorización de esta entrega.")
        return 0
    baseline = preflight()
    parent = HOME / ".local/state"
    parent.mkdir(parents=True, exist_ok=True)
    bundle = Path(tempfile.mkdtemp(prefix=TAG + "-", dir=parent)) / "backup"
    print("Respaldo: " + str(bundle), flush=True)
    apply(TREES, PRIVATE / "deliver-candidate", bundle)
    try:
        result = reload_checked(baseline, bundle, "apply")
    except Exception:
        rollback(bundle, True)
        r = reload_checked(baseline, bundle, "rollback")
        (bundle / "rollback-result.json").write_text(json.dumps(r, indent=2) + "\n")
        raise
    (bundle / "apply-result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Entregado: PID {result['pid']}, reinicios {result['restarts']}, settings.json intacto, sin avisos QML. "
          f"Vuelta atrás: deliver.py rollback --bundle {bundle} --apply")
    return 0


if __name__ == "__main__":
    sys.exit(main())

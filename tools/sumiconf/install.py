"""Instalación de usuario, sin privilegios: `sumi-sddm install --user` / `uninstall --user`.

Copia (nunca enlaza) lo que la CLI necesita a `$XDG_DATA_HOME/sumi-sddm/releases/<versión>-<marca>/` y deja
en `~/.local/bin/sumi-sddm` un lanzador de tres líneas que ejecuta esa copia. Así Sumi Shell (u otro cliente)
encuentra `sumi-sddm` en el PATH sin depender del checkout de desarrollo ni de enlaces entre repositorios.

- El cambio de versión es atómico: la copia nueva se prepara y prueba aparte, y lo último es reemplazar el
  lanzador con un rename. Se conservan la versión en uso y la anterior; las más viejas se borran.
- Nunca pisa un `~/.local/bin/sumi-sddm` que no sea nuestro lanzador, ni escribe a través de enlaces.
- No toca la configuración (`~/.config/sumi-sddm`), el tema instalado en el sistema ni nada fuera de $HOME.
"""
from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from . import paths, state
from .ini import write_atomic
from .schema import ConfigError

MARK = "# sumi-sddm user launcher v1"
COPY = ["VERSION", "schema/config-schema.json", "theme/sumi", "tools/sumi-sddm", "tools/sumiconf", "tools/harness"]
IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", "theme.conf.user", "backgrounds")
KEEP = 2


def data_dir() -> Path:
    return paths._xdg("XDG_DATA_HOME", ".local/share") / "sumi-sddm"


def releases_dir() -> Path:
    return data_dir() / "releases"


def launcher_path() -> Path:
    return Path.home() / ".local" / "bin" / "sumi-sddm"


def python() -> str:
    return "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else sys.executable


def _ours(launcher: Path) -> bool:
    """True si `launcher` es un lanzador escrito por nosotros (archivo regular con la marca)."""
    if launcher.is_symlink() or not launcher.is_file():
        return False
    with open(launcher, "rb") as f:
        return MARK.encode() in f.read(4096)


def _current_release(launcher: Path) -> Path | None:
    if not _ours(launcher):
        return None
    for line in launcher.read_text(encoding="utf-8").splitlines():
        if line.startswith("exec "):
            parts = shlex.split(line)
            if len(parts) >= 5:
                return Path(parts[4]).parents[1]
    return None


def _no_symlinks(*dirs: Path) -> None:
    for d in dirs:
        if d.is_symlink():
            raise ConfigError(f"{d}: es un enlace simbólico; no se instala a través de él", code="io")


def install(root: Path) -> dict:
    if state.kind() != "checkout":
        raise ConfigError("install --user se ejecuta desde el repositorio de Sumi SDDM", code="unsupported")
    launcher = launcher_path()
    if launcher.exists() or launcher.is_symlink():
        if not _ours(launcher):
            raise ConfigError(f"{launcher} ya existe y no es el lanzador de sumi-sddm; no lo piso", code="conflict")
    base, rel = data_dir(), releases_dir()
    _no_symlinks(base, rel, launcher.parent)
    rel.mkdir(parents=True, exist_ok=True, mode=0o755)

    version = state.version()
    tmp = Path(tempfile.mkdtemp(dir=rel, prefix=".new-"))
    try:
        for item in COPY:
            src, dst = root / item, tmp / item
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir():
                shutil.copytree(src, dst, symlinks=False, ignore=IGNORE)
            else:
                shutil.copy2(src, dst)
        for d, _dirs, files in os.walk(tmp):
            os.chmod(d, 0o755)
            for f in files:
                p = Path(d) / f
                os.chmod(p, 0o755 if p.name == "sumi-sddm" else 0o644)
        # La copia debe funcionar ANTES de apuntar el lanzador a ella.
        probe = subprocess.run([python(), "-I", "-B", str(tmp / "tools" / "sumi-sddm"), "version", "--json"],
                               capture_output=True, text=True, timeout=60)
        doc = json.loads(probe.stdout or "{}") if probe.returncode == 0 else {}
        if doc.get("api") != state.API or doc.get("kind") != "user":
            raise ConfigError("la copia preparada no responde como se esperaba: "
                              + (probe.stderr.strip() or probe.stdout.strip())[:300], code="io")
        final = rel / f"{version}-{time.strftime('%Y%m%d%H%M%S')}-{os.getpid()}"
        os.rename(tmp, final)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise

    previous = _current_release(launcher)
    text = (f"#!/bin/sh\n{MARK} — generado por `sumi-sddm install --user`; se quita con "
            f"`sumi-sddm uninstall --user`\nexec {shlex.quote(python())} -I -B "
            f"{shlex.quote(str(final / 'tools' / 'sumi-sddm'))} \"$@\"\n")
    write_atomic(launcher, text, mode=0o755)

    keep = {final.name} | ({previous.name} if previous else set())
    removed = []
    for old in sorted(rel.iterdir()):
        if old.name not in keep and old.is_dir() and not old.is_symlink():
            shutil.rmtree(old)
            removed.append(old.name)
    return {"version": version, "release": str(final), "launcher": str(launcher),
            "previous": str(previous) if previous else "", "removed": removed}


def uninstall() -> dict:
    launcher = launcher_path()
    removed = []
    if launcher.exists() or launcher.is_symlink():
        if not _ours(launcher):
            raise ConfigError(f"{launcher} no es el lanzador de sumi-sddm; no lo borro", code="conflict")
        launcher.unlink()
        removed.append(str(launcher))
    rel = releases_dir()
    if rel.is_symlink():
        raise ConfigError(f"{rel}: es un enlace simbólico; no lo borro", code="io")
    if rel.is_dir():
        shutil.rmtree(rel)
        removed.append(str(rel))
    return {"removed": removed, "kept": str(paths.config_dir())}


def status() -> dict:
    launcher = launcher_path()
    cur = _current_release(launcher)
    return {"launcher": str(launcher), "installed": cur is not None and cur.is_dir(),
            "release": str(cur) if cur else "", "foreign": (launcher.exists() or launcher.is_symlink())
            and not _ours(launcher)}

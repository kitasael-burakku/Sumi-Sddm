"""Estado compartido de la configuración del usuario: versión del contrato, huella, bloqueo y fuentes.

- `API`: versión del contrato JSON de la CLI (docs/CLI-JSON.md). Sube sólo con cambios incompatibles.
- `stamp()`: huella de lo preparado (theme.conf.user + las copias del wallpaper). Quien enseña unos valores y
  luego escribe pasa `--expect <huella>`: si otro (la terminal, otra ventana) cambió algo entre medias, la
  escritura se rechaza con `code: "conflict"` en vez de pisarlo.
- `locked()`: `flock` sobre `~/.config/sumi-sddm/.lock`; serializa escrituras y deja leer una foto coherente.
- `fonts()`: familias instaladas según fontconfig, marcando cuáles verá el greeter (no las de tu $HOME).
"""
from __future__ import annotations

import errno
import fcntl
import hashlib
import os
import shutil
import stat
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path

from . import paths
from .schema import ConfigError

API = 1


def version() -> str:
    try:
        return (paths.ROOT / "VERSION").read_text(encoding="utf-8").strip() or "0"
    except OSError:
        return "0"


def kind() -> str:
    """«checkout» (repositorio), «system» (paquete, /usr/lib/sumi-sddm) o «user» (copia de `install --user`).

    El paquete instala el helper junto a la CLI (`<raíz>/sumi-sddm-helper`); ni el repositorio (lo tiene en
    `system/`) ni la copia de usuario lo llevan ahí. Los clientes deben tolerar valores nuevos.
    """
    if (paths.ROOT / "tests").is_dir():
        return "checkout"
    return "system" if (paths.ROOT / "sumi-sddm-helper").is_file() else "user"


# ── Huella ──────────────────────────────────────────────────────────────────────────────
def _lstat_line(p: Path) -> bytes:
    st = os.lstat(p)
    kindc = "f" if stat.S_ISREG(st.st_mode) else "l" if stat.S_ISLNK(st.st_mode) else "o"
    return f"{p.name}\0{kindc}\0{st.st_size}\0{st.st_mtime_ns}\n".encode()


def stamp() -> str:
    """Huella de la configuración preparada. Cambia con cualquier escritura de la CLI (o a mano)."""
    h = hashlib.sha256(b"sumi-sddm-stamp-1\n")
    conf = paths.user_conf()
    try:
        fd = os.open(conf, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except FileNotFoundError:
        h.update(b"conf:absent\n")
    except OSError as exc:
        # Un enlace simbólico u otra cosa rara: que cuente como estado propio (la validación ya lo rechaza).
        h.update(f"conf:error:{exc.errno}\n".encode())
    else:
        try:
            with os.fdopen(fd, "rb", closefd=False) as f:
                h.update(b"conf:" + f.read(1 << 20))
        finally:
            os.close(fd)
    staged = paths.staged_backgrounds()
    if staged.is_dir():
        for p in sorted(staged.glob(paths.WALLPAPER_STEM + ".*")):
            h.update(b"bg:" + _lstat_line(p))
    return h.hexdigest()[:32]


# ── Bloqueo ─────────────────────────────────────────────────────────────────────────────
@contextmanager
def locked_file(lock: Path, exclusive: bool = True, timeout: float = 5.0):
    """`flock` sobre `lock` (se crea 0600; nunca a través de un enlace). ConfigError(code=busy) si no llega."""
    lock.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    try:
        fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            raise ConfigError(f"{lock}: es un enlace simbólico", en=f"{lock} is a symbolic link", code="io") from exc
        raise
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ConfigError(f"{lock}: no es un archivo regular", en=f"{lock} is not a regular file", code="io")
        op = (fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH) | fcntl.LOCK_NB
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, op)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ConfigError("otra operación de sumi-sddm está en curso; inténtalo de nuevo", en="Another sumi-sddm operation is running; try again",
                                      code="busy") from None
                time.sleep(0.05)
        yield
    finally:
        os.close(fd)  # libera el flock


@contextmanager
def locked(exclusive: bool = True, timeout: float = 5.0):
    """Bloqueo de la configuración del usuario. Una lectura sin directorio aún no crea nada."""
    if not exclusive and not paths.config_dir().is_dir():
        yield
        return
    with locked_file(paths.config_dir() / ".lock", exclusive, timeout):
        yield


def check_expect(expect: str | None) -> None:
    """Con --expect: la configuración debe seguir siendo la que se leyó (llamar con el bloqueo tomado)."""
    if expect is None:
        return
    current = stamp()
    if expect != current:
        raise ConfigError("la configuración cambió desde que se leyó; vuelve a cargarla", en="The settings changed since they were read; reload them", code="conflict",
                          stamp=current)


# ── Fuentes ─────────────────────────────────────────────────────────────────────────────
def fonts(pattern, max_len: int = 64) -> list[dict]:
    """[{family, system}] ordenado. `system`: fuera de tu $HOME, así que también la verá el usuario sddm."""
    fc = shutil.which("fc-list")
    if not fc:
        raise ConfigError("fc-list (fontconfig) no está disponible", en="fc-list (fontconfig) isn't available", code="missing")
    p = subprocess.run([fc, "--format", "%{family}\t%{file}\n"], capture_output=True, text=True, timeout=30)
    if p.returncode != 0:
        raise ConfigError("fc-list falló", en="fc-list failed", code="io")
    home = str(Path.home()).rstrip("/") + "/"
    fams: dict[str, bool] = {}
    for line in p.stdout.splitlines():
        fam, _, file = line.partition("\t")
        system = not file.startswith(home)
        for name in fam.split(","):
            name = name.strip()
            if not name or len(name) > max_len or not pattern.match(name):
                continue
            fams[name] = fams.get(name, False) or system
    return [{"family": n, "system": fams[n]} for n in sorted(fams, key=lambda s: (s.casefold(), s))]

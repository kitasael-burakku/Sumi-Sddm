"""Avatar del usuario para la pantalla de inicio, por AccountsService (sin root).

SDDM busca el avatar en `~/.face.icon` → `/var/lib/AccountsService/icons/<usuario>` → `FacesDir`. El primero no
sirve cuando el `$HOME` no deja pasar a otros (el usuario `sddm` no puede ni comprobar que existe); el segundo es
el sitio estándar: AccountsService (`org.freedesktop.Accounts.User.SetIconFile`) deja a cada usuario cambiar SU
avatar (polkit `change-own-user-data`, sin contraseña) y guarda una copia que `sddm` puede leer. AccountsService
rechaza archivos grandes, así que la CLI manda un PNG cuadrado ya recortado.
"""
from __future__ import annotations

import json
import os
import pwd
import shutil
import stat
import subprocess
from pathlib import Path

from .schema import ConfigError

BUS = "org.freedesktop.Accounts"
ICONS = Path("/var/lib/AccountsService/icons")
MAX_ICON_BYTES = 1024 * 1024          # el límite de AccountsService para un usuario sin privilegios


def busctl() -> str:
    found = os.environ.get("SUMI_SDDM_BUSCTL_TEST") or shutil.which("busctl")
    if not found:
        raise ConfigError("busctl (systemd) no está disponible", code="missing")
    return found


def _call(*args: str, timeout: int = 30):
    p = subprocess.run([busctl(), "--system", "--json=short", *args], capture_output=True, text=True,
                       timeout=timeout)
    if p.returncode != 0:
        msg = (p.stderr.strip() or p.stdout.strip() or "error de D-Bus").splitlines()[-1]
        if "org.freedesktop.Accounts" in msg and ("not" in msg.lower() or "activat" in msg.lower()):
            raise ConfigError("AccountsService no está disponible: " + msg, code="missing")
        raise ConfigError("AccountsService: " + msg, code="io")
    try:
        return json.loads(p.stdout) if p.stdout.strip() else None
    except ValueError:
        raise ConfigError("respuesta de AccountsService no esperada", code="io") from None


def user_object(user: str | None = None) -> str:
    user = user or pwd.getpwuid(os.getuid()).pw_name
    doc = _call("call", BUS, "/org/freedesktop/Accounts", BUS, "FindUserByName", "s", user)
    try:
        return str(doc["data"][0])
    except (TypeError, KeyError, IndexError):
        raise ConfigError("AccountsService no conoce a este usuario", code="io") from None


def icon_file(obj: str) -> str:
    doc = _call("get-property", BUS, obj, BUS + ".User", "IconFile")
    return str((doc or {}).get("data", ""))


def set_icon(obj: str, path: str) -> None:
    _call("call", BUS, obj, BUS + ".User", "SetIconFile", "s", path)


def sddm_can_read(path: Path) -> bool:
    """¿Podría leerlo un usuario cualquiera (sddm)? Archivo regular con «r» para otros y directorios con «x»."""
    try:
        st = os.stat(path)
    except OSError:
        return False
    if not stat.S_ISREG(st.st_mode) or not st.st_mode & stat.S_IROTH:
        return False
    for d in path.parents:
        try:
            if not os.stat(d).st_mode & stat.S_IXOTH:
                return False
        except OSError:
            return False
    return True


def status(home: Path | None = None) -> dict:
    obj = user_object()
    icon = icon_file(obj)
    p = Path(icon) if icon else None
    home = home or Path.home()
    face = home / ".face.icon"
    home_open = bool(os.stat(home).st_mode & stat.S_IXOTH)
    out = {"iconFile": icon, "exists": bool(p and p.is_file()),
           "readableBySddm": bool(p and sddm_can_read(p)),
           "faceIcon": face.exists(), "homeOpenToOthers": home_open}
    # Qué usará SDDM: ~/.face.icon sólo si `sddm` puede llegar a él; si no, AccountsService; si no, el genérico.
    if out["faceIcon"] and home_open and sddm_can_read(face):
        out["sddmUses"] = str(face)
    elif out["readableBySddm"]:
        out["sddmUses"] = icon
    else:
        out["sddmUses"] = ""
    return out

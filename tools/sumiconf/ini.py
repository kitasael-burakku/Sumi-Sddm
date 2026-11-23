"""Lectura y escritura del subconjunto de INI de QSettings que usa el tema.

Sólo se admite lo que se puede leer sin ambigüedad tal como lo leerá QSettings en el greeter:
- comentarios de línea completa con «;» o «#», líneas en blanco
- una sección [General] (la que SDDM expone sin prefijo); cualquier otra es un error
- `clave=valor`; valores sin comillas sin «,» (QSettings haría una lista), «;» (comentario), «"» ni «\\»
- valores entre comillas con los escapes \\" y \\\\ únicamente
- nada que empiece por «@» (QSettings lo interpreta como @Variant/@ByteArray)
"""
from __future__ import annotations

import os
import re
import stat
import tempfile
from pathlib import Path

from .schema import ConfigError, Schema, strict, to_ini

KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]*$")
MAX_BYTES = 64 * 1024


def _unquote(raw: str, lineno: int) -> str:
    out = []
    i = 1
    while i < len(raw):
        c = raw[i]
        if c == "\\":
            if i + 1 >= len(raw) or raw[i + 1] not in '"\\':
                raise ConfigError(f"línea {lineno}: escape no permitido")
            out.append(raw[i + 1])
            i += 2
            continue
        if c == '"':
            rest = raw[i + 1:].strip()
            if rest and not rest.startswith(";"):
                raise ConfigError(f"línea {lineno}: texto tras las comillas")
            return "".join(out)
        out.append(c)
        i += 1
    raise ConfigError(f"línea {lineno}: comillas sin cerrar")


def parse(text: str) -> dict[str, str]:
    """INI → {clave: cadena tal como la verá QSettings}. Lanza ConfigError ante cualquier ambigüedad."""
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise ConfigError("archivo demasiado grande")
    values: dict[str, str] = {}
    section = None
    for lineno, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s[0] in ";#":
            continue
        if s.startswith("["):
            if not s.endswith("]"):
                raise ConfigError(f"línea {lineno}: sección mal formada")
            section = s[1:-1].strip()
            if section != "General":
                raise ConfigError(f"línea {lineno}: sólo se admite la sección [General]")
            continue
        if "=" not in s:
            raise ConfigError(f"línea {lineno}: se esperaba clave=valor")
        if section != "General":
            raise ConfigError(f"línea {lineno}: clave fuera de [General]")
        key, raw = s.split("=", 1)
        key, raw = key.strip(), raw.strip()
        if not KEY_RE.match(key):
            raise ConfigError(f"línea {lineno}: nombre de clave inválido")
        if key in values:
            raise ConfigError(f"línea {lineno}: clave repetida «{key}»")
        if raw.startswith('"'):
            value = _unquote(raw, lineno)
        else:
            if any(c in raw for c in ',;"\\'):
                raise ConfigError(f"línea {lineno}: «{key}» necesita comillas (contiene , ; \" o \\)")
            value = raw
        if value.startswith("@"):
            raise ConfigError(f"línea {lineno}: un valor no puede empezar por «@»")
        values[key] = value
    return values


def validate(schema: Schema, values: dict[str, str]) -> dict:
    """Valida estrictamente un conjunto leído; devuelve {clave: valor normalizado}."""
    out = {}
    errors = []
    for key, raw in values.items():
        try:
            out[key] = strict(schema.entry(key), raw)
        except ConfigError as exc:
            errors.append(str(exc))
    if errors:
        raise ConfigError("; ".join(errors))
    return out


def render(schema: Schema, values: dict, header: str = "") -> str:
    """Valores normalizados → texto INI, en el orden del esquema."""
    lines = []
    if header:
        lines += ["; " + l if l else ";" for l in header.splitlines()]
    lines.append(f"[{schema.section}]")
    for key in schema.order:
        if key in values:
            lines.append(f"{key}={to_ini(schema.keys[key], values[key])}")
    return "\n".join(lines) + "\n"


def read_file(path: Path) -> str:
    """Lee sin seguir enlaces simbólicos (el archivo debe ser regular)."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise ConfigError(f"{path}: no es un archivo regular")
        if st.st_size > MAX_BYTES:
            raise ConfigError(f"{path}: demasiado grande")
        with os.fdopen(fd, "rb", closefd=False) as f:
            data = f.read(MAX_BYTES + 1)
    finally:
        os.close(fd)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigError(f"{path}: no es UTF-8") from exc


def write_atomic(path: Path, text: str, mode: int = 0o644) -> None:
    """Escribe en un temporal del mismo directorio y lo renombra. No sigue un enlace en el destino."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    if path.is_symlink():
        raise ConfigError(f"{path}: es un enlace simbólico; no se escribe a través de él")
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise
    dfd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)

"""Validación de wallpapers sin decodificarlos: tipo real por la cabecera, dimensiones y tamaño.

Se lee siempre desde un descriptor abierto con O_NOFOLLOW y se comprueba con fstat (no hay ventana entre
comprobar y copiar). El mismo código servirá al helper de la Fase 5.
"""
from __future__ import annotations

import os
import shutil
import stat
import struct
from dataclasses import dataclass
from pathlib import Path

from .schema import ConfigError

MAX_BYTES = 40 * 1024 * 1024
MIN_SIDE = 320
AVATAR_MIN_SIDE = 64
MAX_SIDE = 16384
MAX_PIXELS = 120_000_000
QT_PLUGINS = Path("/usr/lib/qt6/plugins/imageformats")


@dataclass(frozen=True)
class ImageInfo:
    kind: str          # jpg | png | webp
    width: int
    height: int
    size: int


def _png(head: bytes):
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return "png", w, h


def _webp(head: bytes):
    if head[:4] != b"RIFF" or head[8:12] != b"WEBP":
        return None
    chunk = head[12:16]
    if chunk == b"VP8 " and head[23:26] == b"\x9d\x01\x2a":
        w, h = struct.unpack("<HH", head[26:30])
        return "webp", w & 0x3FFF, h & 0x3FFF
    if chunk == b"VP8L" and head[20] == 0x2F:
        b = head[21:25]
        bits = int.from_bytes(b, "little")
        return "webp", (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if chunk == b"VP8X":
        w = int.from_bytes(head[24:27], "little") + 1
        h = int.from_bytes(head[27:30], "little") + 1
        return "webp", w, h
    raise ConfigError("WebP con una cabecera que no se reconoce", en="This WebP file has a header that isn't recognised")


SOF = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def _jpeg(f) -> tuple | None:
    f.seek(0)
    if f.read(2) != b"\xff\xd8":
        return None
    for _ in range(4096):
        b = f.read(1)
        while b == b"\xff":           # relleno
            b = f.read(1)
        if not b:
            break
        marker = b[0]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            continue
        if marker == 0xD9:            # EOI antes de SOF
            break
        ln = f.read(2)
        if len(ln) < 2:
            break
        (length,) = struct.unpack(">H", ln)
        if length < 2:
            break
        if marker in SOF:
            data = f.read(5)
            if len(data) < 5:
                break
            h, w = struct.unpack(">HH", data[1:5])
            return "jpg", w, h
        f.seek(length - 2, os.SEEK_CUR)
        # el siguiente byte debería ser 0xFF
        nxt = f.read(1)
        if nxt != b"\xff":
            break
        f.seek(-1, os.SEEK_CUR)
    raise ConfigError("JPEG sin cabecera de dimensiones legible", en="This JPEG has no readable size header")


def webp_supported() -> bool:
    return (QT_PLUGINS / "libqwebp.so").exists()


def open_regular(path: Path) -> int:
    """Descriptor de un archivo regular, sin seguir enlaces en el último componente."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except OSError as exc:
        if exc.errno == 40:  # ELOOP
            raise ConfigError(f"{path}: es un enlace simbólico; indica el archivo real", en=f"{path} is a symbolic link; choose the real file") from exc
        raise ConfigError(f"{path}: no se puede abrir ({exc.strerror})", en=f"{path} can't be opened ({exc.strerror})") from exc
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        os.close(fd)
        raise ConfigError(f"{path}: no es un archivo regular", en=f"{path} is not a regular file")
    return fd


def inspect_fd(fd: int, min_side: int = MIN_SIDE) -> ImageInfo:
    st = os.fstat(fd)
    if st.st_size > MAX_BYTES:
        raise ConfigError(f"imagen demasiado grande ({st.st_size // (1024 * 1024)} MiB; máximo {MAX_BYTES // (1024 * 1024)})", en=f"The image is too big ({st.st_size // (1024 * 1024)} MiB; at most {MAX_BYTES // (1024 * 1024)} MiB)")
    if st.st_size < 32:
        raise ConfigError("archivo demasiado pequeño para ser una imagen", en="The file is too small to be an image")
    with os.fdopen(os.dup(fd), "rb") as f:
        head = f.read(64)
        got = _png(head) or _webp(head) or _jpeg(f)
    if not got:
        raise ConfigError("formato no admitido (se aceptan JPEG, PNG y WebP)", en="Format not supported (use JPEG, PNG or WebP)")
    kind, w, h = got
    if kind == "webp" and not webp_supported():
        raise ConfigError("WebP necesita qt6-imageformats, que no está instalado", en="WebP needs qt6-imageformats, which isn't installed")
    if min(w, h) < min_side or max(w, h) > MAX_SIDE or w * h > MAX_PIXELS:
        raise ConfigError(f"dimensiones no admitidas ({w}×{h}; lado mínimo {min_side}, máximo {MAX_SIDE})", en=f"Size not supported ({w}×{h}; each side between {min_side} and {MAX_SIDE} pixels)")
    return ImageInfo(kind, w, h, st.st_size)


def inspect(path: Path, min_side: int = MIN_SIDE) -> ImageInfo:
    fd = open_regular(Path(path))
    try:
        return inspect_fd(fd, min_side)
    finally:
        os.close(fd)


def copy_validated(src: Path, dest_dir: Path, stem: str) -> tuple[Path, ImageInfo]:
    """Valida `src` y lo copia a dest_dir/<stem>.<ext> de forma atómica (0644). Devuelve destino e info."""
    fd = open_regular(Path(src))
    try:
        info = inspect_fd(fd)
        dest_dir.mkdir(parents=True, exist_ok=True, mode=0o755)
        dest = dest_dir / f"{stem}.{info.kind}"
        if dest.is_symlink():
            raise ConfigError(f"{dest}: es un enlace simbólico", en=f"{dest} is a symbolic link")
        tmp = dest_dir / f".{stem}.{os.getpid()}.tmp"
        with os.fdopen(os.dup(fd), "rb") as fin, open(tmp, "xb") as fout:
            fin.seek(0)
            shutil.copyfileobj(fin, fout, 1024 * 1024)
            fout.flush()
            os.fsync(fout.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, dest)
        return dest, info
    finally:
        os.close(fd)

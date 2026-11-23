"""Esquema de configuración y sus dos validaciones.

- `lenient(entry, raw)`: lo que hace el tema en QML (`components/config.js`). Nunca falla: un valor que no
  se entiende vuelve al defecto y un número fuera de rango se acota. Las dos implementaciones se comparan
  con los mismos casos (tests/fixtures/config-vectors.js).
- `strict(entry, raw)`: lo que exige la CLI (y exigirá el helper). Rechaza en vez de corregir.

`raw` es la cadena tal como la entrega QSettings (sin comillas), o None si la clave no está.
"""
from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

NUM_RE = re.compile(r"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$")
INT_RE = re.compile(r"^[+-]?\d+$")
COLOR_RE = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")
# Espacios que recorta String.prototype.trim() de JavaScript (Python recorta además \x1c–\x1f).
JS_WS = " \t\n\r\x0b\x0c\u00a0\ufeff\u1680\u2028\u2029\u202f\u205f\u3000" + "".join(
    chr(c) for c in range(0x2000, 0x200B))
TRUE = {"true", "1", "yes", "on"}
FALSE = {"false", "0", "no", "off"}
# Rutas que la CLI acepta: recursos dentro del tema, o imágenes del sistema (legibles por «sddm»).
THEME_ASSET_RE = re.compile(r"^backgrounds/[a-z0-9][a-z0-9_-]{0,63}\.([a-z]+)$")
SYSTEM_PATH_RE = re.compile(r"^/usr/share/[A-Za-z0-9._/-]+\.([A-Za-z]+)$")

DEFAULT_SCHEMA = Path(__file__).resolve().parents[2] / "schema" / "config-schema.json"


class ConfigError(ValueError):
    """Error para el usuario. `code` clasifica la causa en las respuestas --json (docs/CLI-JSON.md)."""

    def __init__(self, message: str, code: str = "invalid", **extra):
        super().__init__(message)
        self.code = code
        self.extra = extra


@dataclass
class Schema:
    version: int
    section: str
    groups: list[dict]
    keys: dict[str, dict] = field(default_factory=dict)
    order: list[str] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path | str = DEFAULT_SCHEMA) -> "Schema":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        s = cls(version=data["version"], section=data["section"], groups=data["groups"])
        for e in data["keys"]:
            check_entry(e, {g["id"] for g in s.groups})
            if e["key"] in s.keys:
                raise ConfigError(f"clave duplicada en el esquema: {e['key']}")
            s.keys[e["key"]] = e
            s.order.append(e["key"])
        return s

    def entry(self, key: str) -> dict:
        if key not in self.keys:
            raise ConfigError(f"clave desconocida: {key}")
        return self.keys[key]

    def defaults(self) -> dict:
        return {k: self.keys[k]["default"] for k in self.order}


def check_entry(e: dict, groups: set[str]) -> None:
    """Coherencia interna de una entrada del esquema (la prueba también la ejecuta)."""
    k = e.get("key", "?")
    t = e.get("type")
    if t not in {"number", "integer", "bool", "enum", "color", "string", "path"}:
        raise ConfigError(f"{k}: tipo desconocido {t!r}")
    if e.get("group") not in groups:
        raise ConfigError(f"{k}: grupo desconocido")
    if not re.match(r"^[a-z][A-Za-z0-9]*$", k):
        raise ConfigError(f"{k}: nombre de clave inválido")
    for req in ("default", "label", "doc"):
        if req not in e:
            raise ConfigError(f"{k}: falta {req}")
    if t in ("number", "integer"):
        if not (e["min"] <= e["default"] <= e["max"]) and not (e.get("allowZero") and e["default"] == 0):
            raise ConfigError(f"{k}: default fuera de rango")
    if t == "enum" and e["default"] not in e["values"]:
        raise ConfigError(f"{k}: default no está en values")
    if t == "color" and not COLOR_RE.match(e["default"]):
        raise ConfigError(f"{k}: default no es un color")
    if t == "string" and e["default"] and not re.match(e["pattern"], e["default"]):
        raise ConfigError(f"{k}: default no cumple pattern")


# ── Tolerante (paridad con QML) ──────────────────────────────────────────────────────────
def _round_half_up(x: float) -> int:
    # Math.round de JavaScript (·5 hacia +∞), no el redondeo bancario de Python.
    return int(math.floor(x + 0.5))


def _parse_number(raw: str) -> float | None:
    if not NUM_RE.match(raw):
        return None
    v = float(raw)
    return v if math.isfinite(v) else None


def lenient(e: dict, raw: str | None):
    d = e["default"]
    if raw is None:
        return d
    v = raw.strip(JS_WS)
    t = e["type"]
    if t == "path":
        return _lenient_path(e, v)
    if v == "":
        return d
    if t in ("number", "integer"):
        n = _parse_number(v)
        if n is None:
            return d
        if t == "integer":
            n = _round_half_up(n)
            if e.get("allowZero") and n <= 0:
                return 0
        return min(e["max"], max(e["min"], n))
    if t == "bool":
        lv = v.lower()
        return True if lv in TRUE else False if lv in FALSE else d
    if t == "enum":
        lv = v.lower()
        return lv if lv in e["values"] else d
    if t == "color":
        return v if COLOR_RE.match(v) else d
    if t == "string":
        ok = len(v) <= e.get("maxLength", 256) and not CONTROL_RE.search(v) and re.match(e["pattern"], v)
        return v if ok else d
    raise AssertionError(t)


def _lenient_path(e: dict, v: str) -> str:
    if v == "" or ".." in v or CONTROL_RE.search(v):
        return e["default"]
    if not v.startswith("file:///") and ":" in v:
        return e["default"]
    ext = v.rsplit(".", 1)[-1].lower() if "." in v.rsplit("/", 1)[-1] else ""
    if ext not in e.get("extensions", []):
        return e["default"]
    return v


# ── Estricta (CLI y helper) ──────────────────────────────────────────────────────────────
def strict(e: dict, raw: str):
    """Valida y normaliza; lanza ConfigError con un mensaje para el usuario."""
    k, t = e["key"], e["type"]
    if raw is None:
        raise ConfigError(f"{k}: falta el valor")
    v = raw.strip(JS_WS)
    if CONTROL_RE.search(v):
        raise ConfigError(f"{k}: caracteres de control no permitidos")
    if v.startswith("@"):
        raise ConfigError(f"{k}: un valor no puede empezar por «@» (QSettings lo interpreta)")
    if t == "number":
        n = _parse_number(v)
        if n is None:
            raise ConfigError(f"{k}: se esperaba un número")
        if not e["min"] <= n <= e["max"]:
            raise ConfigError(f"{k}: fuera de rango ({e['min']}–{e['max']})")
        return float(n)
    if t == "integer":
        if not INT_RE.match(v):
            raise ConfigError(f"{k}: se esperaba un entero")
        n = int(v)
        if e.get("allowZero") and n == 0:
            return 0
        if not e["min"] <= n <= e["max"]:
            extra = " o 0" if e.get("allowZero") else ""
            raise ConfigError(f"{k}: fuera de rango ({e['min']}–{e['max']}{extra})")
        return n
    if t == "bool":
        lv = v.lower()
        if lv in TRUE:
            return True
        if lv in FALSE:
            return False
        raise ConfigError(f"{k}: se esperaba true o false")
    if t == "enum":
        lv = v.lower()
        if lv not in e["values"]:
            raise ConfigError(f"{k}: valores permitidos: {', '.join(e['values'])}")
        return lv
    if t == "color":
        if not COLOR_RE.match(v):
            raise ConfigError(f"{k}: se esperaba un color #RRGGBB o #AARRGGBB")
        return v.lower()
    if t == "string":
        if v == "":
            return ""
        if len(v) > e.get("maxLength", 256):
            raise ConfigError(f"{k}: demasiado largo (máximo {e.get('maxLength', 256)})")
        if not re.match(e["pattern"], v):
            raise ConfigError(f"{k}: contiene caracteres no permitidos")
        return v
    if t == "path":
        return strict_path(e, v)
    raise AssertionError(t)


def strict_path(e: dict, v: str) -> str:
    k = e["key"]
    if v == "":
        return ""
    if ".." in v or "//" in v or "\\" in v:
        raise ConfigError(f"{k}: ruta no permitida")
    m = THEME_ASSET_RE.match(v) or SYSTEM_PATH_RE.match(v)
    if not m:
        raise ConfigError(f"{k}: sólo se aceptan backgrounds/<nombre>.<ext> (gestionado por «wallpaper set») "
                          "o una imagen bajo /usr/share")
    if m.group(1).lower() not in e.get("extensions", []):
        raise ConfigError(f"{k}: extensión no permitida ({', '.join(e.get('extensions', []))})")
    return v


# ── Formato para el INI ──────────────────────────────────────────────────────────────────
def to_ini(e: dict, value) -> str:
    """Texto del valor normalizado para escribirlo en el INI (cadenas siempre entre comillas)."""
    t = e["type"]
    if t == "bool":
        return "true" if value else "false"
    if t == "integer":
        return str(int(value))
    if t == "number":
        s = f"{float(value):.6g}"
        return s
    if t == "enum":
        return str(value)
    s = str(value)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

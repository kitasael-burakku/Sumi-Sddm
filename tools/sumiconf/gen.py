"""Genera los artefactos derivados del esquema: schema.js (QML), theme.conf y docs/CONFIG.md."""
from __future__ import annotations

import json
from pathlib import Path

from .paths import ROOT, THEME
from .schema import Schema, to_ini

BANNER = "Generado por tools/sumi-sddm gen desde schema/config-schema.json. No editar a mano."


def schema_js(s: Schema) -> str:
    keys = {k: s.keys[k] for k in s.order}
    # Sólo lo que necesita el tema; las etiquetas de UI no viajan al greeter.
    slim = {k: {f: v for f, v in e.items() if f in ("key", "type", "default", "min", "max", "values",
                                                      "pattern", "maxLength", "allowZero", "extensions")}
            for k, e in keys.items()}
    body = json.dumps(slim, indent=1, ensure_ascii=False, sort_keys=False)
    return (".pragma library\n"
            f"// {BANNER}\n"
            f"var VERSION = {s.version};\n"
            f"var KEYS = {body};\n")


def _range(e: dict) -> str:
    t = e["type"]
    if t in ("number", "integer"):
        r = f"{e['min']}–{e['max']}"
        return ("0 o " + r) if e.get("allowZero") else r
    if t == "enum":
        return " | ".join(e["values"])
    if t == "color":
        return "#RRGGBB | #AARRGGBB"
    if t == "bool":
        return "true | false"
    if t == "path":
        return "ruta (" + ", ".join(e.get("extensions", [])) + ")"
    return f"texto (máx. {e.get('maxLength', 256)})"


def theme_conf(s: Schema) -> str:
    out = [
        f"; Sumi SDDM — valores por defecto. {BANNER}",
        ";",
        "; SDDM carga este archivo y después «theme.conf.user» (mismo directorio), que lo sobrescribe:",
        "; las personalizaciones van ahí (o con `sumi-sddm config set`), nunca aquí. Todas las claves son",
        "; opcionales: el tema tiene los mismos valores compilados, descarta los inválidos y acota los",
        "; números fuera de rango.",
        ";",
        "; Formato: INI de QSettings, sólo [General]. Los textos van entre comillas: QSettings convierte",
        "; «a, b» en una lista y «;» empieza un comentario.",
        "",
        f"[{s.section}]",
    ]
    for g in s.groups:
        keys = [k for k in s.order if s.keys[k]["group"] == g["id"]]
        if not keys:
            continue
        out += ["", f"; ── {g['doc']} " + "─" * max(4, 84 - len(g["doc"]))]
        for k in keys:
            e = s.keys[k]
            out.append(f"; {e['doc']} [{_range(e)}]")
            out.append(f"{k}={to_ini(e, e['default'])}")
    return "\n".join(out) + "\n"


def config_md(s: Schema) -> str:
    out = [
        "# Configuración de Sumi SDDM",
        "",
        f"> {BANNER}",
        "",
        "El tema lee `theme.conf` (valores por defecto, dentro del tema) y después `theme.conf.user`, que lo",
        "sobrescribe. Formato: INI de QSettings, sección `[General]`.",
        "",
        "- **En el greeter** (QML) la lectura es tolerante: un valor que no se entiende vuelve al defecto y un número",
        "  fuera de rango se acota. Una configuración rota nunca deja la pantalla inutilizable.",
        "- **En `sumi-sddm config`** la validación es estricta: se rechaza en vez de corregir, y el archivo se escribe",
        "  de forma atómica en `~/.config/sumi-sddm/theme.conf.user`.",
        "- Las dos lecturas se comparan con los mismos casos (`tests/fixtures/config-vectors.js`).",
        "",
        "Reglas de formato: los textos, colores y rutas se escriben entre comillas; sin comillas no se admiten `,`",
        "`;` `\"` ni `\\`; ningún valor puede empezar por `@`; sólo existe la sección `[General]`.",
        "",
    ]
    for g in s.groups:
        keys = [k for k in s.order if s.keys[k]["group"] == g["id"]]
        if not keys:
            continue
        out += [f"## {g['doc']}", "", "| Clave | Tipo | Valores | Defecto | Descripción |", "|---|---|---|---|---|"]
        for k in keys:
            e = s.keys[k]
            d = to_ini(e, e["default"])
            out.append(f"| `{k}` | {e['type']} | {_range(e)} | `{d}` | {e['doc']} |")
        out.append("")
    return "\n".join(out)


TARGETS = {
    THEME / "components" / "schema.js": schema_js,
    THEME / "theme.conf": theme_conf,
    ROOT / "docs" / "CONFIG.md": config_md,
}


def generate(check: bool = False) -> list[Path]:
    """Escribe los artefactos; con check=True sólo devuelve los que están desactualizados."""
    s = Schema.load()
    stale = []
    for path, fn in TARGETS.items():
        text = fn(s)
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current != text:
            stale.append(path)
            if not check:
                path.write_text(text, encoding="utf-8")
    return stale

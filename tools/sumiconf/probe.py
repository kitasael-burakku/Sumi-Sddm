"""Prueba del tema con el greeter real (`sddm-greeter-qt6 --test-mode`, offscreen): qué se espera y cómo se juzga.

La usan `sumi-sddm smoke` (desarrollo) y el helper de la Fase 5, que la ejecuta como el usuario `sddm` sobre una
copia preparada ANTES de tocar lo que verá la pantalla de inicio de sesión. El tema registra al arrancar
`sumi-sddm: ready … custom=N` (N = claves distintas de su defecto, sin valores); comparar N con lo que predice la
lectura tolerante de Python demuestra que el QSettings real lee exactamente lo que se escribió.
"""
from __future__ import annotations

import re

from .schema import Schema, lenient

READY = "sumi-sddm: ready"
# Los de `smoke` desde la Fase 2, más el import que falta («module "X" is not installed»).
PROBLEMS = ("TypeError", "ReferenceError", "is not defined", "Cannot assign", "failed to load",
            "Fallback to embedded theme", "Unable to", "Cannot open", "is not installed")
IGNORE_PREFIXES = ("Loading file://", "Loading theme configuration")
CUSTOM_RE = re.compile(r"\bcustom=(\d+)\b")


def expected_custom(schema: Schema, raw: dict[str, str]) -> int:
    """Claves que el tema verá distintas de su defecto, con valores tal como los entrega QSettings."""
    return sum(1 for k in schema.order if lenient(schema.keys[k], raw.get(k)) != schema.keys[k]["default"])


def judge(lines: list[str], theme_uri: str, expect_custom: int | None) -> tuple[bool, list[str], str]:
    """(correcto, problemas, línea ready). Un problema es un aviso QML del tema o un error conocido del greeter."""
    problems = [l for l in lines
                if (theme_uri in l or any(k in l for k in PROBLEMS)) and not l.startswith(IGNORE_PREFIXES)
                and READY not in l]
    ready = next((l for l in lines if READY in l), "")
    if not ready:
        problems.append("el tema no llegó a «sumi-sddm: ready»")
    elif expect_custom is not None:
        m = CUSTOM_RE.search(ready)
        if not m or int(m.group(1)) != expect_custom:
            problems.append(f"se esperaba custom={expect_custom}: {ready.strip()}")
    return not problems, problems, ready

"""Una `sumi-sddm` falsa para probar clientes del contrato JSON (el backend del editor) sin tocar nada real.

Se copia como `<dir>/sumi-sddm` (con el intérprete actual en el shebang) y lee/escribe `<dir>/state.json`. Cada
invocación añade su argv a `<dir>/log.jsonl`, así las pruebas comprueban orden, agrupado y que los argumentos llegan
intactos. Lo que se puede forzar desde `state.json`:

  api, version          lo que responde `version`
  garbage               `version` escribe basura y sale con 1
  delay                 {verbo: segundos} antes de responder ("show", "preview", "apply", "version"…)
  busy_next             nº de escrituras siguientes que fallan con code "busy"
  deny                  `system apply|activate|deactivate` → code "denied" (polkit cancelado)
  values                {clave: texto} lo guardado (lo que cambia una «terminal» desde la prueba)
  applied               huella de lo aplicado al sistema (para inSync)
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import struct
import sys
import time
import zlib
from pathlib import Path

D = Path(__file__).resolve().parent

SCHEMA = {
    "version": 1, "section": "General",
    "groups": [{"id": "colors", "label": "Colors"}, {"id": "clock", "label": "Clock"},
               {"id": "users", "label": "Users"}],
    "keys": [
        {"key": "accentColor", "group": "colors", "type": "color", "default": "#a9bdff", "label": "Accent",
         "help": "Focus rings"},
        {"key": "dim", "group": "colors", "type": "number", "default": 0.4, "min": 0, "max": 1, "step": 0.05,
         "label": "Dim"},
        {"key": "blur", "group": "colors", "type": "integer", "default": 0, "min": 8, "max": 64, "step": 4,
         "allowZero": True, "label": "Blur"},
        {"key": "clockFormat", "group": "clock", "type": "enum", "default": "24h", "values": ["12h", "24h"],
         "label": "Clock format"},
        {"key": "showClock", "group": "clock", "type": "bool", "default": True, "label": "Show clock"},
        {"key": "clockPosition", "group": "clock", "type": "enum", "default": "center",
         "values": ["center", "top-left", "top-right", "bottom-left", "bottom-right"], "label": "Position"},
        {"key": "dateFormat", "group": "clock", "type": "string", "default": "dddd, d MMMM", "maxLength": 48,
         "pattern": "^[A-Za-z0-9 ,.:/'\\-]*$", "label": "Date format"},
        {"key": "fontFamily", "group": "clock", "type": "string", "default": "", "label": "Font"},
        {"key": "background", "group": "users", "type": "path", "default": "", "label": "Wallpaper"},
    ],
}
DEFAULTS = {k["key"]: k["default"] for k in SCHEMA["keys"]}


def png(path: Path, w: int, h: int, rgb: tuple[int, int, int]) -> None:
    """Un PNG válido de un color (sin dependencias): las Image de QML no deben quejarse."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\0" + bytes(rgb) * w for _ in range(h))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def stamp(values: dict) -> str:
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()[:32]


def typed(key: str, raw: str):
    t = next(k["type"] for k in SCHEMA["keys"] if k["key"] == key)
    if t == "bool":
        return raw == "true"
    if t == "integer":
        return int(raw)
    if t == "number":
        return float(raw)
    return raw


def main() -> int:
    argv = sys.argv[1:]
    with open(D / "log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(argv) + "\n")
    j = "--json" in argv
    args = [a for a in argv if a != "--json"]
    expect = None
    if "--expect" in args:
        i = args.index("--expect")
        expect = args[i + 1]
        del args[i:i + 2]
    verb = args[1] if args[:1] in (["config"], ["system"], ["wallpaper"], ["avatar"]) and len(args) > 1 else args[0]

    with open(D / "state.lock", "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_SH)
        st = json.loads((D / "state.json").read_text())
    time.sleep(st.get("delay", {}).get(verb, 0))

    def reply(doc: dict, ok: bool = True) -> int:
        if not j:
            print("(texto)")
            return 0 if ok else 1
        print(json.dumps({"ok": ok, "api": st.get("api", 1), **doc}))
        return 0 if ok else 1

    def fail(code: str, error: str, **extra) -> int:
        return reply({"code": code, "error": error, **extra}, ok=False)

    def save(mutate) -> dict:
        with open(D / "state.lock", "a") as lk2:
            fcntl.flock(lk2, fcntl.LOCK_EX)
            cur = json.loads((D / "state.json").read_text())
            mutate(cur)
            (D / "state.json").write_text(json.dumps(cur))
            return cur

    vals = st.get("values", {})
    cur_stamp = stamp(vals)

    if args[0] == "version":
        if st.get("garbage"):
            print("Traceback (most recent call last): boom")
            print("something broke", file=sys.stderr)
            return 1
        return reply({"version": st.get("version", "9.9.9"), "schema": 1, "kind": "system"})
    if args[:2] == ["config", "schema"]:
        return reply(SCHEMA)
    if args[:2] == ["config", "show"]:
        out = {k: {"value": vals.get(k, d), "default": d, "set": k in vals} for k, d in DEFAULTS.items()}
        return reply({"version": 1, "path": str(D / "theme.conf.user"), "stamp": cur_stamp, "values": out,
                      "warnings": st.get("warnings", [])})
    if args[:2] == ["config", "fonts"]:
        return reply({"families": [{"family": "Inter", "system": True}, {"family": "Mine", "system": False}]})

    writes = {("config", "set"), ("config", "reset"), ("config", "restore"), ("wallpaper", "set"),
              ("wallpaper", "clear")}
    if tuple(args[:2]) in writes:
        if st.get("busy_next", 0) > 0:
            save(lambda s: s.update(busy_next=s["busy_next"] - 1))
            return fail("busy", "another sumi-sddm operation is running")
        if expect is not None and expect != cur_stamp:
            return fail("conflict", "changed since read", stamp=cur_stamp)

        def mutate(s):
            v = s.setdefault("values", {})
            if args[:2] == ["config", "set"]:
                for pair in args[2:]:
                    k, _, raw = pair.partition("=")
                    if raw == "":
                        v.pop(k, None)
                    else:
                        v[k] = typed(k, raw)
            elif args[:2] == ["config", "reset"]:
                s["prev"], s["values"] = dict(v), {}
            elif args[:2] == ["config", "restore"]:
                s["values"] = dict(s.get("prev", {}))
            elif args[:2] == ["wallpaper", "set"]:
                v["background"] = "backgrounds/user.png"
                s["wallpaper_source"] = args[2]
            else:
                v.pop("background", None)
        new = save(mutate)
        return reply({"stamp": stamp(new.get("values", {}))})

    if args[:2] == ["avatar", "info"]:
        a = st.get("avatar")
        return reply({"iconFile": a, "exists": bool(a), "sddmUses": bool(a)} if a else {"exists": False})
    if args[:2] == ["avatar", "set"]:
        icon = D / "icons" / "me"
        icon.parent.mkdir(exist_ok=True)
        png(icon, 8, 8, (200, 120, 40))
        save(lambda s: s.update(avatar=str(icon)))
        return reply({"iconFile": str(icon), "exists": True, "sddmUses": True})
    if args[:2] == ["avatar", "clear"]:
        save(lambda s: s.update(avatar=None))
        return reply({"exists": False})

    if args[0] == "preview":
        out = D / "preview.png"
        size = args[args.index("--size") + 1] if "--size" in args else "1280x720"
        w, h = (int(n) for n in size.split("x"))
        png(out, max(1, w // 40), max(1, h // 40), (int(cur_stamp[:2], 16), 80, 160))
        sc = args[args.index("--scenario") + 1] if "--scenario" in args else "expanded"
        return reply({"png": str(out), "scenario": sc, "stamp": cur_stamp, "size": size})

    if args[:2] == ["system", "status"]:
        return reply({"installed": True, "active": st.get("active", False), "activeTheme": "sumi" if
                      st.get("active") else "orbital", "inSync": st.get("applied") == cur_stamp, "version": "9.9.9"})
    if args[0] == "system" and verb in ("apply", "activate", "deactivate"):
        if st.get("deny"):
            return fail("denied", "authentication cancelled")
        if verb == "apply":
            changed = st.get("applied") != cur_stamp
            save(lambda s: s.update(applied=cur_stamp))
            return reply({"changed": changed})
        save(lambda s: s.update(active=verb == "activate"))
        return reply({"activeTheme": "sumi" if verb == "activate" else "orbital"})

    if args[0] == "try":
        return 0
    return fail("usage", "unknown")


if __name__ == "__main__":
    sys.exit(main())

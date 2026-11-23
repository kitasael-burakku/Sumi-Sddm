#!/usr/bin/env python3
"""Aplica la integración de Sumi SDDM (Settings → Desktop tools → Login screen) a una COPIA del árbol de Sumi Shell.

    edit.py ÁRBOL            modifica ÁRBOL en el sitio (una copia: nunca el vivo ni dotfiles)
    edit.py ÁRBOL --check    sólo comprueba que todas las anclas están, sin escribir

Cada cambio es «texto ancla → texto nuevo» y el ancla debe aparecer exactamente una vez; si falta alguna, no se
escribe nada. Los archivos nuevos no deben existir antes. Lo que se añade lleva el comentario «Sumi SDDM» para
encontrarlo. La entrega en la sesión es otro paso, con guarda de hash, respaldo y vuelta atrás, y su propia
autorización.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent

NEW_FILES = ["services/SddmTheme.qml", "components/SddmField.qml", "components/SddmPreview.qml"]

GROUP_TITLES = [("background", "Background"), ("colors", "Colors"), ("typography", "Typography"), ("notch", "Notch"),
                ("clock", "Clock"), ("users", "Users"), ("power", "Power"), ("motion", "Motion"),
                ("behaviour", "Behaviour")]

PAGE = '''            // Sumi SDDM (2026-11-22): la pantalla de inicio de sesión. Los valores son de Sumi SDDM (services/SddmTheme,
            // orden `sumi-sddm`), no de settings.json: esta página enseña y pide; nada de aquí toca el sistema.
            { id: "sddm", title: "Login screen", sections: [
                { title: "Login screen", key: "", rows: [
                    { id: "sddmStatus", prop: "", kind: "info", name: "Sumi SDDM" },
                    { id: "sddmApplied", prop: "", kind: "info", name: "On the login screen" }
                ] },
                { title: "Preview", key: "", dynamic: "sddm:preview", rows: [] },
''' + "".join(f'                {{ title: "{t}", key: "", dynamic: "sddm:{g}", rows: [] }},\n' for g, t in GROUP_TITLES) + '''                { title: "Changes", key: "", rows: [
                    { id: "sddmReset", prop: "", kind: "action", name: "Reset everything", label: "Reset" },
                    { id: "sddmRestore", prop: "", kind: "action", name: "Undo the last reset", label: "Restore" }
                ] }
            ] },
'''

SETTINGS_FUNCS = '''
    // ---- Sumi SDDM: Desktop tools → Login screen (2026-11-22) ------------------------------------------

    /** Con la página a la vista, SddmTheme carga y mantiene la vista previa; si no, no corre nada. */
    readonly property bool sddmPageShown: root.open && root.pageKey === "shell/sddm"
    onSddmPageShownChanged: SddmTheme.claim("settings", root.sddmPageShown)
    QtObject { Component.onDestruction: SddmTheme.claim("settings", false) }
    /** Filas de un grupo del esquema (dependen del esquema y los avisos, no de los valores: un deslizador no se
     *  rehace mientras se arrastra). */
    function sddmRows(group) {
        if (!SddmTheme.ready) {
            // como las listas vacías de Settings: una fila que dice por qué no hay nada (id …Empty: sin guion)
            const checking = SddmTheme.status === "" || SddmTheme.status === "checking";
            return [{ id: "sddm" + group + "Empty", prop: "", kind: "info", name: checking ? "Reading…" : "Not available",
                      caption: checking ? "" : "Needs a working Sumi SDDM · see Overview" }];
        }
        if (group === "preview")
            return [{ id: "sddmPreview", prop: "", kind: "sddmPreview", name: "Preview" },
                    { id: "sddmTry", prop: "", kind: "action", name: "Test window", label: "Open" }];
        return SddmTheme.rows(group);
    }
    function sddmInfo(id) {
        if (id === "sddmStatus") {
            switch (SddmTheme.status) {
            case "ready": return "Version " + SddmTheme.version;
            case "missing": return "Not installed";
            case "incompatible": return "Incompatible version";
            case "broken": return "Not working";
            default: return "Checking…";
            }
        }
        if (id === "sddmApplied") return SddmTheme.ready ? "Not installed yet" : "";
        return "";
    }
    function sddmCaption(r) {
        switch (r.id) {
        case "sddmStatus":
            if (SddmTheme.status === "missing") return "Install it from the Sumi SDDM folder with: tools/sumi-sddm install --user";
            if (SddmTheme.status === "incompatible" || SddmTheme.status === "broken") return SddmTheme.statusDetail;
            if (SddmTheme.error.length > 0) return SddmTheme.error;
            if (SddmTheme.notice.length > 0) return SddmTheme.notice;
            return SddmTheme.busy ? "Saving…" : "Changes are saved for Sumi SDDM as you make them";
        case "sddmApplied": return "Your choices are kept in ~/.config/sumi-sddm; installing the theme on the system is a separate step";
        case "sddmTry": return SddmTheme.tryArmed ? "Press again to open · it takes the keyboard until you close it"
                                                  : "The real login screen in a window, without logging in";
        case "sddmReset": return SddmTheme.resetArmed ? "Press again to reset " + SddmTheme.customCount + " settings"
                                                      : "Back to the theme's defaults · a copy is kept";
        case "sddmRestore": return "Brings back the settings from before the last reset";
        }
        return r.caption !== undefined ? r.caption : SddmTheme.captionFor(r.key || "");
    }
    function sddmReason(r) {
        if (r.id === "sddmStatus" || r.id === "sddmApplied" || /Empty$/.test(r.id)) return "";
        if (!SddmTheme.ready) return SddmTheme.status === "checking" || SddmTheme.status === "" ? "Checking…" : "Sumi SDDM is not available";
        if (r.id === "sddmReset" && SddmTheme.customCount === 0) return "Everything is at its default";
        return "";
    }
    function sddmAction(id) {
        if (id === "sddmTry") SddmTheme.openTestWindow();
        if (id === "sddmReset") SddmTheme.resetAll();
        if (id === "sddmRestore") SddmTheme.restorePrevious();
    }
'''

SDDM_COMPONENTS = '''                                Component {
                                    id: sddmC                                     // Sumi SDDM (2026-11-22)
                                    SddmField {
                                        id: sddmField
                                        s: root.s
                                        key: rowItem.modelData.key
                                        focused: rowItem.focused
                                        availableWidth: rowItem.controlMaxWidth
                                        onFinished: root.forceActiveFocus()
                                        Component.onCompleted: root.register("pathFields", rowItem.modelData.id, sddmField, true)
                                        Component.onDestruction: root.register("pathFields", rowItem.modelData.id, sddmField, false)
                                    }
                                }
                                Component {
                                    id: sddmPreviewC                              // Sumi SDDM (2026-11-22)
                                    SddmPreview {
                                        s: root.s
                                        availableWidth: rowItem.controlMaxWidth
                                    }
                                }
'''

EDITS: dict[str, list[tuple[str, str]]] = {
    "lib/settings-nav.js": [
        ('"shell/dashboard", "shell/notifications", "shell/osd", "shell/calendar", "shell/recording", "shell/lock"\n',
         '"shell/dashboard", "shell/notifications", "shell/osd", "shell/calendar", "shell/recording", "shell/lock",\n'
         '        "shell/sddm"\n'),
        ('    "shell/lock": "Lock screen, how lock requests arrive and the authentication stack",\n',
         '    "shell/lock": "Lock screen, how lock requests arrive and the authentication stack",\n'
         '    "shell/sddm": "The Sumi SDDM login screen: wallpaper, colours, notch, clock and users, with a preview",\n'),
    ],
    "lib/settings-sections.js": [
        ('    "shell/dashboard": {"Maintenance tasks":"Tasks", "Backups":"Tasks"},\n',
         '    "shell/dashboard": {"Maintenance tasks":"Tasks", "Backups":"Tasks"},\n'
         '    "shell/sddm": {"Login screen":"Overview", "Preview":"Overview", "Changes":"Overview", "Background":"Look",'
         ' "Colors":"Look", "Typography":"Look", "Notch":"Notch and clock", "Clock":"Notch and clock",'
         ' "Users":"Users and power", "Power":"Users and power", "Motion":"Behaviour", "Behaviour":"Behaviour"},\n'),
    ],
    "surfaces/Settings.qml": [
        # la página, tras Lock screen
        ('''            // 12E (futureSettingssurface §12): portabilidad. Export nunca incluye secretos,
''', PAGE + '''            // 12E (futureSettingssurface §12): portabilidad. Export nunca incluye secretos,
'''),
        # funciones propias, delante de runAction
        ('''    function runAction(id) {
        if (id === "family") { fontEditor.begin(); return; }
''', SETTINGS_FUNCS.lstrip("\n") + '''
    function runAction(id) {
        if (String(id).indexOf("sddm") === 0) { root.sddmAction(id); return; }       // Sumi SDDM
        if (id === "family") { fontEditor.begin(); return; }
'''),
        ('''    function dynRows(which) {
        if (String(which).indexOf("env:") === 0) return root.envRows(String(which).slice(4));
''', '''    function dynRows(which) {
        if (String(which).indexOf("sddm:") === 0) return root.sddmRows(String(which).slice(5));   // Sumi SDDM
        if (String(which).indexOf("env:") === 0) return root.envRows(String(which).slice(4));
'''),
        ('''    function rowReason(r) {
''', '''    function rowReason(r) {
        if (String(r.id).indexOf("sddm") === 0) { const sw = root.sddmReason(r); if (sw.length > 0) return sw; }   // Sumi SDDM
'''),
        ('''    function captionOf(r) {
        if (r.caption !== undefined) return r.caption;
''', '''    function captionOf(r) {
        if (String(r.id).indexOf("sddm") === 0) return root.sddmCaption(r);                       // Sumi SDDM
        if (r.caption !== undefined) return r.caption;
'''),
        ('''    function infoValue(r) { return r.value !== undefined ? r.value : root.infoOf(r.id); }
''', '''    function infoValue(r) {
        if (String(r.id).indexOf("sddm") === 0) return root.sddmInfo(r.id);                       // Sumi SDDM
        return r.value !== undefined ? r.value : root.infoOf(r.id);
    }
'''),
        # teclado: Enter / ←/→ sobre una clave de Sumi SDDM
        ('''        if (r.kind === "toggle") {
            Settings[r.prop] = dir === 0 ? !Settings[r.prop] : dir > 0;
        } else if (r.kind === "taskEvery") {''', '''        if (r.kind === "toggle") {
            Settings[r.prop] = dir === 0 ? !Settings[r.prop] : dir > 0;
        } else if (r.kind === "sddm") {                                    // Sumi SDDM (2026-11-22)
            const sf = root.pathFields[r.id];
            if (sf) sf.activate(dir); else SddmTheme.step(r.key, dir);
        } else if (r.kind === "taskEvery") {'''),
        # la fila: vista previa apilada, marca de personalizado y restablecer
        ('''                                vertical: rowItem.modelData.kind === "choice" && rowItem.modelData.stretch !== true
''', '''                                vertical: rowItem.modelData.kind === "choice" && rowItem.modelData.stretch !== true
                                    || rowItem.modelData.kind === "sddmPreview"
'''),
        ('''                                    || (["barEdge", "barLength"].indexOf(rowItem.modelData.kind) >= 0
                                        && root.barPrefCustom(rowItem.modelData.kind))
''', '''                                    || (["barEdge", "barLength"].indexOf(rowItem.modelData.kind) >= 0
                                        && root.barPrefCustom(rowItem.modelData.kind))
                                    || (rowItem.modelData.kind === "sddm" && SddmTheme.isSet(rowItem.modelData.key))
'''),
        ('''                                onResetRequested: rowItem.modelData.kind === "taskEvery"
''', '''                                onResetRequested: rowItem.modelData.kind === "sddm" ? SddmTheme.unset(rowItem.modelData.key)
                                    : rowItem.modelData.kind === "taskEvery"
'''),
        ('''                                        : rowItem.modelData.kind === "info" ? infoC
''', '''                                        : rowItem.modelData.kind === "info" ? infoC
                                        : rowItem.modelData.kind === "sddm" ? sddmC
                                        : rowItem.modelData.kind === "sddmPreview" ? sddmPreviewC
'''),
        ('''                                Component {
                                    id: actionC
''', SDDM_COMPONENTS + '''                                Component {
                                    id: actionC
'''),
    ],
    "scripts/capabilities.py": [
        ('''def c_ddc(q):
''', '''def c_sddm_theme(q):
    """Sumi SDDM (2026-11-22): Settings → Login screen habla con la orden `sumi-sddm` del PATH (contrato JSON api 1).
    Es otro proyecto, opcional: sin ella la página lo explica y nada más cambia."""
    if not which("sumi-sddm"):
        return cap("unavailable", "Sumi SDDM", "Sumi SDDM is not installed", installed=False)
    rc, out, err = run(["sumi-sddm", "version", "--json"])
    if rc is None:
        return cap("unknown", "Sumi SDDM", err or "sumi-sddm did not answer", installed=True)
    try:
        doc = json.loads(out)
    except ValueError:
        doc = {}
    if rc != 0 or doc.get("ok") is not True:
        return cap("unavailable", "Sumi SDDM", "sumi-sddm is installed but does not work", installed=True)
    if doc.get("api") != 1:
        return cap("unavailable", "Sumi SDDM", "This version of Sumi SDDM is not compatible", installed=True,
                   api=doc.get("api"))
    return cap("available", "Sumi SDDM", installed=True, version=str(doc.get("version", "")))


def c_ddc(q):
'''),
        ('''    ("network.speedtest", "devices", c_speedtest),
''', '''    ("network.speedtest", "devices", c_speedtest),
    ("login.sddmTheme", "desktop", c_sddm_theme),
'''),
    ],
    "services/Capabilities.qml": [
        ('''        "network.speedtest": "Speed test", "bluetooth": "Bluetooth",
''', '''        "network.speedtest": "Speed test", "bluetooth": "Bluetooth",
        "login.sddmTheme": "Login screen theme",
'''),
    ],
    "services/qmldir": [
        ("singleton SpeedTest SpeedTest.qml\n", "singleton SpeedTest SpeedTest.qml\nsingleton SddmTheme SddmTheme.qml\n"),
    ],
    "components/qmldir": [
        ("SettingsNavRow SettingsNavRow.qml\n", "SettingsNavRow SettingsNavRow.qml\nSddmField SddmField.qml\nSddmPreview SddmPreview.qml\n"),
    ],
}


def plan(tree: Path) -> tuple[dict[str, str], list[str]]:
    out, problems = {}, []
    for rel, edits in EDITS.items():
        p = tree / rel
        if not p.is_file():
            problems.append(f"falta {rel}")
            continue
        text = p.read_text(encoding="utf-8")
        for old, new in edits:
            n = text.count(old)
            if n != 1:
                problems.append(f"{rel}: el ancla aparece {n} veces: {old.strip().splitlines()[0][:80]!r}")
                continue
            text = text.replace(old, new)
        out[rel] = text
    for rel in NEW_FILES:
        if (tree / rel).exists():
            problems.append(f"{rel} ya existe")
    return out, problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tree", type=Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    tree = args.tree.resolve()
    home = Path.home()
    forbidden = [home / ".config/quickshell", home / "Projects/dotfiles"]
    if any(tree == f or tree.is_relative_to(f) for f in forbidden):
        print(f"edit.py: {tree} es el vivo o dotfiles; sólo se edita una copia", file=sys.stderr)
        return 2
    texts, problems = plan(tree)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    if args.check:
        print(f"edit.py: {sum(len(e) for e in EDITS.values())} cambios en {len(EDITS)} archivos y "
              f"{len(NEW_FILES)} archivos nuevos: aplicables")
        return 0
    for rel, text in texts.items():
        (tree / rel).write_text(text, encoding="utf-8")
    for rel in NEW_FILES:
        shutil.copyfile(HERE / rel, tree / rel)
    print(f"edit.py: aplicado a {tree}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

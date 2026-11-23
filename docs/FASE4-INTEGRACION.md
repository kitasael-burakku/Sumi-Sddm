# Sumi SDDM — Fase 4: integración con Settings (informe)

Plan aprobado: [FASE4-PLAN.md](FASE4-PLAN.md). Este informe crece por partes.

## Parte A — contrato e instalación de usuario (2026-11-22)

Sólo en este repositorio. No se ha escrito en `~/.config/sumi-sddm`, `~/.local`, Quickshell, dotfiles ni el
sistema: todas las pruebas usan un HOME temporal. Lo único real fue una vista previa en `~/.cache/sumi-sddm/`
para medir el tiempo (~1,4 s).

| # | Hecho | Dónde |
|---|---|---|
| A1 | Contrato JSON versionado (`api: 1`): toda respuesta lleva `ok` y `api`; los errores llevan `code` estable (`invalid`, `conflict`, `busy`, `missing`, `io`, `render`, `unsupported`, `usage`) y `error` en texto. `version --json` da versión, esquema y tipo de instalación. `config schema --json` ya no incluye el `$comment` interno. Los errores de E/S inesperados salen como `code: "io"`, no como traza. | `tools/sumi-sddm`, `docs/CLI-JSON.md` |
| A2 | Huella `stamp` de lo preparado (`theme.conf.user` + copias del wallpaper). `--expect` en todas las escrituras. `flock` en `~/.config/sumi-sddm/.lock` (0600, nunca a través de un enlace): exclusivo al escribir y compartido al leer. Además, una vista previa a la vez y una sola ventana `try`. Una escritura que no cambia nada ya no reescribe el archivo. | `tools/sumiconf/state.py`, `tools/sumi-sddm` |
| A3 | `config fonts`: familias de fontconfig; marca las que están sólo en tu `$HOME`, que el greeter no verá. `config show` avisa (`warnings`) si `fontFamily` no está instalada para todo el sistema. | `state.py`, `tools/sumi-sddm` |
| A4 | `install --user` / `uninstall --user` / `install --status` | `tools/sumiconf/install.py` |
| A5 | `VERSION` (0.4.0) como única fuente | `VERSION` |

Cómo funciona `install --user` (A4):
- **Copia, nunca enlaza.** Copia la CLI, `sumiconf`, el tema, el arnés y el esquema a
  `releases/<versión>-<marca>/`, sin `__pycache__`, `theme.conf.user` ni fondos.
- **Prueba antes de activar.** Ejecuta `version --json` sobre la copia antes de activarla.
- **Cambio atómico.** El cambio de versión es reemplazar el lanzador `~/.local/bin/sumi-sddm` (un script
  `python3 -I -B`) con un rename.
- **Versiones conservadas.** Guarda la actual y la anterior.
- **Respeta lo ajeno.** Nunca pisa ni borra un `sumi-sddm` que no sea nuestro (ni un enlace).
- **Desinstalar.** Conserva la configuración.
- **Copia instalada.** Desde ella, las órdenes de desarrollo responden `unsupported`.

### Pruebas

| Prueba | Resultado |
|---|---|
| `tests/py/test_contract.py` (17 casos: formato de las respuestas, cada `code` documentado, huella, `--expect` en las 6 escrituras, bloqueo 0600/enlace/`busy`, fuentes con un `fc-list` falso, instalación/actualización/retención/desinstalación, lanzador ajeno o enlace intacto) | 17/17 |
| `tools/sumi-sddm check` completo: gen, lint (21), Python 47, QML 51 software + 51 OpenGL, 4 humos con el greeter real (`custom=0/0/4/3`) | OK |
| Prueba manual en un HOME temporal: instalar, usar por el lanzador (`config set`, `preview`), reinstalar dos veces, desinstalar, lanzador ajeno | lo esperado |

### Límites

- **`install --user` no se ha ejecutado en tu HOME.** Hacerlo escribe en `~/.local/share/sumi-sddm` y
  `~/.local/bin`; espera tu autorización.
- **«Sistema» en `config fonts`** significa «fuera de tu `$HOME`». No se comprueba con el fontconfig del
  usuario `sddm`.
- **Bloqueos `busy`.** Una operación que no consigue el bloqueo espera 5 s antes de responder `busy`.

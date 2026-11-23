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

## Parte A, posterior: `install --user` real y vista previa sin GPU (2026-11-22)

- **`install --user` en tu HOME**, con tu autorización: `~/.local/bin/sumi-sddm` (lanzador) y
  `~/.local/share/sumi-sddm/releases/`. Desde entonces se ha reinstalado dos veces para recoger las correcciones de
  abajo, y conserva la versión anterior. `~/.config/sumi-sddm` sigue sin existir: leer no lo crea.
- **Vista previa sin GPU.** El banco de la parte B descubrió que `preview` fallaba sin contexto gráfico, porque
  OpenGL offscreen no tiene contexto sin variables de sesión. Ahora `--backend auto` es el defecto: prueba OpenGL y,
  si no hay contexto, usa el renderizador software, sin blur ni sombras. La respuesta dice el `backend` usado. En tu
  sesión sigue saliendo OpenGL. Hay una prueba nueva (48 en Python).
- **Esquema:** la etiqueta de `backgroundFill` pasa de «Fit», que era también una de sus opciones, a «Scaling».

## Parte B — Settings → Desktop tools → Login screen (2026-11-22), entregada

Fuentes en [`integration/sumi-shell/`](../integration/sumi-shell/README.md). El trabajo privado está en
`~/Projects/Quickshell/.sddm-settings-20261122/`, ignorado por su propio `.gitignore`, así que el `.gitignore` del
repo no se tocó. El árbol vivo, dotfiles y el repo de Quickshell siguen sin cambios (`git status` limpio).

Bases tomadas del vivo y de la fuente justo antes de preparar la entrega: son idénticas en las 7 rutas modificadas.
Incluyen el trabajo sin commitear de la navegación de Settings, y la entrega va encima de él.

**La página.** Cinco pestañas:

| Pestaña | Contenido |
|---|---|
| Overview | estado de Sumi SDDM, si está instalado en el sistema, vista previa con escena (Compact, Password, Sessions, Error) y «Test window» con doble pulsación; Reset con doble pulsación y Restore |
| Look | fondo, colores, tipografía |
| Notch and clock | notch y reloj |
| Users and power | usuarios y energía |
| Behaviour | movimiento y comportamiento |

- **Filas.** Una fila por cada una de las 41 claves, con el control según su tipo, marca de personalizado y botón de
  restablecer. Teclado: ←/→ y Enter.
- **Sin CLI.** Si falta o es incompatible, cada sección dice por qué y las acciones quedan desactivadas.

**Detalles que importan.**
- **Las filas no se rehacen al arrastrar.** Las filas de claves dependen del esquema y de los avisos, no de los
  valores, así que un deslizador no se rehace mientras se arrastra (probado).
- **El `--expect` se toma al lanzar.** La huella se toma al lanzar cada escritura, no al encolarla. Así una
  escritura propia anterior nunca provoca un conflicto falso.
- **Sin cuelgues si falta la CLI.** Se lanza `/usr/bin/env sumi-sddm`: si falta, `exited` llega con 127. Con un
  binario inexistente, `Process` no emitiría `exited` (PROCEDIMIENTOS §5).

### Pruebas

| Prueba | Resultado |
|---|---|
| Banco `real` (CLI de verdad sobre XDG privado). Comprueba: carga, pestañas, clic en un interruptor, persistencia en disco, arrastre (12 movimientos = 1 escritura y la fila sobrevive), teclado, restablecer una clave, conflicto con un cambio externo (no se pisa y se recarga), valor rechazado (se dice y se revierte), wallpaper, Reset/Restore, Test window solo armada y soltar al salir | 48/48, 0 avisos QML |
| Banco `missing` / `incompatible` | 12/12 cada uno, 0 avisos |
| Banco `terminal` (estilo Terminal, texto 1,15) | 13/13, 0 avisos; capturas revisadas |
| Recarga en caliente: árbol de antes → rutas de la entrega → `Quickshell.reload` | 2 cargas, 48/48, 0 avisos |
| `settings.json` de la shell tras cada escenario | intacto (sin rastro de sddm) |
| `deliver.py check` / `self-test` / `apply` en seco | las 20 rutas (10 × 2 árboles) en base; entrega, vuelta atrás en seco y real, rechazo de ediciones posteriores y concurrentes: OK |
| Candidato de la entrega frente al probado en el banco | idéntico byte a byte en las 10 rutas |
| Sonda `login.sddmTheme` con la CLI real, sin CLI y con api 2 | available / unavailable con su motivo |
| `qmllint --bare` | sin errores (los avisos de importación son de `--bare`, igual que en la base) |

### Límites y pendientes

- **No se ha entregado.** Escribir en el vivo y en dotfiles necesita tu autorización específica, la tercera.
  `deliver.py apply --apply`:
  1. comprueba que la sesión esté desbloqueada;
  2. respalda en `~/.local/state/sumi-sddm-settings-20261122-*/`;
  3. escribe y recarga;
  4. exige una «Configuration Loaded» limpia, el mismo PID, `NRestarts` igual y `settings.json` intacto;
  5. si algo falla, revierte solo.
- **Banco de la navegación.** `tools/settings-navigation/checks.js` de Quickshell espera 31 páginas. Con esta
  serían 32: si se vuelve a ejecutar, hay que actualizar esa cifra. No lo he tocado.
- **«Test window»** sólo se probó armada: abrirla toma el teclado.
- **Vista previa del banco.** Usa el renderizador software, sin GPU. En tu sesión saldrá OpenGL, con blur.
- **Commit en dotfiles.** Tras la entrega, el commit en dotfiles es tuyo (`dotbackup`), como siempre.

### Entrega en la sesión (2026-11-22, autorizada)

`deliver.py apply --apply`, con la sesión desbloqueada:
- **Rutas.** Las 10 rutas, en fuente (dotfiles) y en vivo, partiendo de la base en las 20.
- **Respaldo y vuelta atrás.** El respaldo está en
  `~/.local/state/sumi-sddm-settings-20261122-hw3nt6qi/backup`. Para deshacer:

  ```sh
  python3 integration/sumi-shell/deliver.py rollback --bundle ~/.local/state/sumi-sddm-settings-20261122-hw3nt6qi/backup --apply
  ```

  Ya está comprobada en seco.

| Comprobación | Resultado |
|---|---|
| Recarga en caliente (la del vigilante y la forzada) | 2 «Configuration Loaded», validada al primer intento, 0 avisos QML |
| Unidad | mismo PID (1416), `NRestarts=0` |
| `settings.json` | mismo SHA-256 antes y después |
| Capacidad `login.sddmTheme` | `available`, versión 0.4.0 |
| `deliver.py check` | las 20 rutas en `candidate` |
| `~/.config/sumi-sddm` | sigue sin existir hasta el primer cambio desde Settings |

Pendiente del autor:
- **Mirar la página en la sesión.** No se abrió Settings.
- **Commit en dotfiles** con `dotbackup`. Incluirá también tu trabajo de la navegación, que ya estaba sin commitear.

### Ventana propia en Sumi Shell (2026-11-23)

La página de Settings descrita arriba se sustituyó por una **ventana flotante Login screen** en Sumi Shell (ADR-41 e
informe `docs/SUMI-LOGIN-UI-2026-11-23.md` del repo de Sumi Shell). Settings queda como resumen (estado, «Open Login
screen», Apply/Use/Restore). La ventana añade vista previa al tamaño del monitor con las 16 escenas de la CLI, errores
por clave con `message`/`fields` (0.6.1) y el último arranque del greeter (`system log`). Las copias de
`integration/sumi-shell/services/SddmTheme.qml` y `components/SddmField.qml` se actualizaron en la misma entrega.
`bench/` se rehízo para la página resumen; `edit.py` queda como registro. `system log` marca un falso positivo tras aplicar con la sesión abierta:
[PROBLEMA-LOG-CUSTOM-2026-11-23.md](PROBLEMA-LOG-CUSTOM-2026-11-23.md).

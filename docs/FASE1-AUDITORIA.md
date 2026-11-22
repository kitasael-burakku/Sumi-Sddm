# Sumi SDDM — Fase 1: auditoría del entorno y arquitectura

Fecha: 2026-11-22. Todo lo de este documento se obtuvo con órdenes de **sólo lectura**; no se tocó
`/etc`, `/usr`, la configuración de SDDM ni el repositorio Quickshell.

Leyenda de evidencia: **[bin]** confirmado en los binarios instalados (`strings`, también UTF‑16),
**[ref]** visto en un tema de referencia instalado por el paquete `sddm`, **[run]** ejecutado,
**[conf]** leído de un archivo de configuración. Lo que no tiene marca es propuesta.

## 1. Entorno verificado

| Elemento | Valor | Evidencia |
|---|---|---|
| SDDM | 0.21.0‑8 | pacman |
| Greeter usado | `sddm-greeter-qt6` (el tema declara `QtVersion=6`) | journal del arranque |
| Qt | 6.12.0 (base, declarative, svg, 5compat, wayland, virtualkeyboard) | pacman |
| Servidor del greeter | **X11** (`DisplayServer=x11`, valor por defecto) | [conf] `/usr/lib/sddm/sddm.conf.d/default.conf` |
| HiDPI | `EnableHiDPI=true` en `[X11]`; el journal dice «High-DPI autoscaling Enabled» | [conf] + journal |
| Tema activo | `orbital` (de terceros, en `/usr/share/sddm/themes/orbital`) | [conf] |
| Temas instalados | elarun, maldives, maya (del paquete), orbital | ls |
| Sesiones | `hyprland.desktop`, `hyprland-uwsm.desktop` (sin sesiones X11) | `/usr/share/wayland-sessions` |
| Usuarios listables (UID 1000–60513) | 1: `kitasa-elburakku` | getent |
| Monitores | 1: HDMI‑A‑1 1920×1080, escala 1 | xrandr |
| Módulos QML útiles | `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`, `QtQuick.Effects` (MultiEffect), `QtQuick.Shapes`, `Qt5Compat.GraphicalEffects`, `SddmComponents 2.0` | ls `/usr/lib/qt6/qml` |
| Herramientas | `qmllint`, `qmlformat`, `qml6`, `qmltestrunner`, `shellcheck`, `python3` 3.14, `jq`, `magick`, `pkexec` (polkit 128) | which |
| No instalado | Xephyr, Xvfb, weston, bats | which / pacman |
| Fuente | Inter / Inter Display (paquete `inter-font`, sistema) | fc-list |

`sddm --version` aborta con core dump al ejecutarse como usuario (el daemon espera root); no
afecta al greeter. `sddm-greeter-qt6 --help` funciona.

## 2. Orden de configuración de SDDM (importante para activar el tema)

SDDM 0.21 lee, en este orden: `/usr/lib/sddm/sddm.conf.d/*` → `/etc/sddm.conf.d/*` → **`/etc/sddm.conf`**
(el último gana) [bin: las tres rutas están en el binario] [conf: el propio `/etc/sddm.conf` del sistema lo
anota]. En esta máquina `Current=orbital` está **dos veces**: en `/etc/sddm.conf.d/theme.conf` y en
`/etc/sddm.conf`. Consecuencia: un drop‑in `zz-sumi.conf` en `sddm.conf.d` **no** activaría el tema; la
activación tendría que editar la clave `[Theme] Current` de `/etc/sddm.conf`. Esa operación queda fuera de
todas las fases salvo orden explícita, y siempre con respaldo y vuelta atrás.

## 3. API real del greeter (SDDM 0.21, Qt 6)

### Propiedades de contexto [bin]
`sddm`, `userModel`, `sessionModel`, `screenModel`, `keyboard`, `config`, `primaryScreen`, `__sddm_errors`.

### `sddm` (GreeterProxy)
- Propiedades [bin]: `hostName`, `canPowerOff`, `canReboot`, `canSuspend`, `canHibernate`, `canHybridSleep`
  (cada una con su señal `…Changed`).
- Métodos: `login(user, password, sessionIndex)` [ref maya], `powerOff()`, `reboot()` [ref maya];
  `suspend()`, `hibernate()`, `hybridSleep()` [bin: nombres presentes].
- Señales: `loginSucceeded()`, `loginFailed()`, `informationMessage(message)` [ref maya + bin].

### Modelos (roles) [bin]
- `userModel`: `name`, `realName`, `homeDir`, `icon`, `needsPassword`; propiedades `lastUser`, `lastIndex`,
  `count`, `containsAllUsers`, `disableAvatarsThreshold`.
- `sessionModel`: `name`, `file`, `type`, `exec`, `comment`; propiedad `lastIndex`.
- `screenModel`: `name`, `geometry`, `primary`.
- `keyboard`: `numLock`, `capsLock`, `layouts`, `currentLayout`, `enabled`.

### `config` (ThemeConfig, un `QQmlPropertyMap`) [bin]
- Carga `<tema>/<ConfigFile>` y después **`<ConfigFile>.user`**, que sobrescribe («Loading theme
  configuration from …»). Métodos `stringValue`, `boolValue`, `intValue`, `realValue`.
- Los valores llegan como cadenas: el tema debe convertir, validar y acotar cada clave, con su valor por
  defecto compilado en QML. Se usará sólo la sección `[General]` (claves planas).

### Avatares [bin]
Búsqueda: `<homeDir>/.face.icon` → `/var/lib/AccountsService/icons/<user>` → `<FacesDir>/<user>.face.icon`
→ `<FacesDir>/.face.icon` (genérico). En esta máquina **`$HOME` es `drwx--x---`**: el usuario `sddm`
(uid 960, sin ese grupo) no puede leer `~/.face.icon` ni ningún wallpaper del home. Hoy no hay avatar en
AccountsService ni en FacesDir, así que llega el genérico; el tema lo tratará como «sin avatar»
(iniciales).

### Modo de prueba [run]
`QT_QPA_PLATFORM=offscreen sddm-greeter-qt6 --test-mode --theme <dir>` arranca sin daemon, lee las sesiones
reales, carga `theme.conf`, registra en el journal (`sddm-greeter-qt6[pid]`), incluidos los avisos QML, y
termina con SIGTERM. Sin daemon no hay autenticación real: `login()` no produce `loginFailed`, y los
`can*` pueden no reflejar el sistema. Sirve para validar carga y maquetación, no la autenticación.

## 4. Quickshell / Sumi Shell (sólo consulta)

- `~/Projects/Quickshell` contiene docs, bancos y evidencia, **no** el código de la shell.
- **`~/Projects/Quickshell/sumi` es un enlace a `~/.config/quickshell/sumi`, el árbol VIVO** que ejecuta
  `sumi-shell.service`. Por tanto `~/Projects/Quickshell/sumi/SDDM/` es en realidad
  `~/.config/quickshell/sumi/SDDM/` (vacío, creado hoy). Escribir ahí es escribir en la shell en marcha.
  La fuente versionada está en `~/Projects/dotfiles/quickshell/sumi`, con WIP del usuario sin commitear
  (12 archivos, entre ellos `surfaces/Settings.qml` y `lib/settings-*.js`).
- Settings es **declarativo**: `lib/settings-nav.js` (grupos y páginas: `shell/lock` en «Desktop tools»),
  `lib/settings-schema.js` (catálogo único de ids, tipos, defaults, rangos; `settings.json` v4),
  `lib/settings-sections.js` (pestañas), y `surfaces/Settings.qml` (6136 líneas) que pinta filas por `kind`.
  Los procesos externos van en `scripts/` (Python, `sys.dont_write_bytecode`).
- Sumi Shell es su **propio agente polkit** (`services/Polkit.qml`, `surfaces/Auth.qml`) y tiene un
  coordinador de operaciones globales (`services/Operations.qml`). Un `pkexec` lanzado desde Settings
  mostrará el diálogo de la shell; sin la shell, `pkexec` en terminal usa su agente textual.
- Reglas del proyecto (CLAUDE.md §6) que la Fase 4 debe respetar: entregas por rutas con guarda de hash,
  respaldo en `~/.local/state/<tema>-<fecha>/`, rollback probado, no abrir UI en la sesión sin avisar, no
  pisar el WIP del usuario, UI en inglés y comentarios en español.
- Nada del QML de Quickshell (`Quickshell.*`, singletons de `services/`) existe en el greeter: el tema no
  importará nada de Sumi.

## 5. Riesgos

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | Tema roto en el greeter real (error QML, foco perdido) | **No poder iniciar sesión** | Nunca activar sin orden; validar antes en `--test-mode` offscreen con el journal limpio; mantener `orbital`; documentar TTY (Ctrl+Alt+F2) y `restore`; QML defensivo (todo `config.*` con default, `typeof` en contexto) |
| R2 | El directorio de integración está dentro del árbol vivo de la shell | Recargas/avisos en la sesión, `dotbackup` lo versiona | No escribir ahí en ninguna fase sin plan aprobado; propuesta en §8 |
| R3 | Wallpaper/avatar en `$HOME` ilegibles para `sddm` | Fondo/avatar vacío en el login real (en `--test-mode` sí se ven: engaña) | Copiar el wallpaper dentro del tema instalado vía helper; fallback procedural; prueba con un usuario sin permisos sobre el home |
| R4 | `/etc/sddm.conf` gana a `sddm.conf.d` | Una activación «limpia» por drop‑in no funciona | Activación = editar sólo `Current` en `/etc/sddm.conf`, con respaldo; operación separada |
| R5 | Helper como root leyendo archivos del usuario | Escalada (symlink, TOCTOU, imagen maliciosa) | Sin rutas en argumentos; `O_NOFOLLOW`, dueño = `PKEXEC_UID`, tamaño máximo, firma de imagen, escritura temporal + `rename` en el destino |
| R6 | `--test-mode` no autentica | No se puede probar «contraseña incorrecta» con el greeter real sin el daemon | Arnés propio con `sddm` simulado (emite `loginFailed`, `informationMessage`); prueba real sólo con autorización |
| R7 | Un solo monitor físico | Multimonitor sin verificación física | Plataforma offscreen con varias pantallas simuladas; declararlo como limitación |
| R8 | MultiEffect limita el radio de blur (`blurMax` ≤ 64) | Blur fuerte pobre o caro | Desenfocar una copia reducida (`layer.textureSize`) |
| R9 | Fuente del sistema distinta en otras máquinas | Maquetación diferente | Incluir Inter (OFL) dentro del tema con `FontLoader`; fallback a la fuente del sistema |

## 6. Arquitectura propuesta

Tres piezas separadas que se comunican sólo por archivos y una CLI:

```
                    (sin privilegios)                          (root, vía pkexec)
Sumi Settings ──► sumi-sddm CLI ──► ~/.config/sumi-sddm/ ──► sumi-sddm-helper ──► /usr/share/sddm/themes/sumi/
 (opcional)       valida, previsualiza   theme.conf.user          valida otra vez,       theme.conf.user
                  y lanza --test-mode    wallpaper.<ext>          respalda, escribe      backgrounds/user.<ext>
                                                                  atómico, rollback
```

- **Tema** (`theme/sumi/`): lo único que ve SDDM. Autónomo: recursos propios, defaults compilados, sin
  dependencias de Sumi. `Main.qml` es un adaptador fino que traduce el contexto de SDDM a propiedades de
  `components/Greeter.qml`; así el mismo `Greeter.qml` se carga en el arnés de pruebas con modelos
  simulados.
- **Herramientas** (`tools/`): `sumi-sddm` (Python, sin privilegios) — `check`, `validate`, `preview`
  (PNG offscreen), `test` (ventana `--test-mode`), `config get/set`, `install`/`update`/`restore`/
  `uninstall` (que delegan en el helper).
- **Helper privilegiado** (`helper/`, Fase 5): Python con `-I`, operaciones cerradas
  (`install`, `apply-config`, `restore <id>`, `list-backups`, `uninstall`; `activate`/`deactivate` sólo si se
  autoriza su existencia), sin rutas ni órdenes recibidas del llamante; acción polkit propia con
  `auth_admin`.
- **Integración Sumi Shell** (`integration/sumi-shell/`, Fase 4): página `Settings → SDDM` que llama a la
  CLI; nunca escribe el INI ni toca `/usr` directamente.

### Formato de configuración
INI de QSettings, sección `[General]`, claves planas con prefijo por área (`notchWidth`, `clockFormat`,
`blurRadius`…). `theme.conf` (en el tema, documentado clave por clave) trae los defaults;
`theme.conf.user` sólo las diferencias. Un esquema único (`schema/config-schema.json`: tipo, rango, enum,
default) lo usan la CLI, el helper y las pruebas; el QML replica los defaults y acota en tiempo de
ejecución (el greeter no puede leer JSON externo sin `XMLHttpRequest` local, que se evita).

### Estructura de archivos

```
Sumi-SDDM/
├── README.md, LICENSE, .gitignore
├── docs/                      FASE1-AUDITORIA.md, CONFIG.md, SEGURIDAD.md, PRUEBAS.md
├── schema/config-schema.json  claves, tipos, rangos, defaults (fuente única)
├── theme/sumi/                → /usr/share/sddm/themes/sumi
│   ├── metadata.desktop       QtVersion=6, Theme-API=2.0, ConfigFile=theme.conf
│   ├── theme.conf             defaults comentados
│   ├── Main.qml               adaptador del contexto SDDM
│   ├── components/            Greeter, Style (config tipada), Background, Notch, PasswordField,
│   │                          SessionPicker, PowerActions, Clock, UserStrip, UserAvatar, ManualUser
│   └── assets/                fonts/ (Inter, OFL), icons/*.svg (propios), backgrounds/ (fallback)
├── tools/sumi-sddm            CLI sin privilegios
├── helper/                    sumi-sddm-helper + org.sumi.sddm.policy (Fase 5)
├── tests/
│   ├── harness/               Mock*.qml + preview.qml (render offscreen a PNG)
│   ├── qml/                   tst_*.qml (qmltestrunner)
│   └── py/                    validación de config, CLI y helper (en raíz falsa)
└── integration/sumi-shell/    propuesta y parches para Settings → SDDM (Fase 4)
```

Enlaces simbólicos: sólo como opción de desarrollo local explícita (`tools/sumi-sddm dev-link`, que no se
usa por defecto); la vista previa copia el tema a `~/.cache/sumi-sddm/preview/` en vez de enlazarlo. La
instalación definitiva copia archivos con manifiesto y hashes.

## 7. Estrategia de pruebas

1. `qmllint` sobre todo el tema (sintaxis/imports).
2. Arnés offscreen (`qml6` + `QT_QPA_PLATFORM=offscreen`): `Greeter.qml` con modelos simulados → capturas a
   varias resoluciones (1366×768, 1920×1080, 2560×1440, 3840×2160, escala 2) y estados (compacto,
   expandido, autenticando, error, 0/1/N usuarios, sin avatar, imagen rota, sin config).
3. `qmltestrunner`: foco, Tab/Enter/Esc, limpieza de contraseña al cambiar de usuario y tras fallo.
4. Greeter real en `--test-mode` offscreen sobre una copia en `~/.cache`: el journal no debe tener avisos
   de `file:///…/sumi/`.
5. Ventana `--test-mode` en la sesión: **sólo avisando antes** (roba el teclado).
6. Prueba con el daemon real (Xephyr o el login real): sólo con autorización, fuera de estas fases.

## 8. Decisiones abiertas para el usuario

1. **Directorio de integración**: `~/Projects/Quickshell/sumi/SDDM/` cae en el árbol vivo de la shell.
   Propuesta: no usarlo; preparar la integración en `Sumi-SDDM/integration/sumi-shell/` y, en la Fase 4,
   entregarla a la fuente (`~/Projects/dotfiles/quickshell/sumi`) y al vivo con el procedimiento habitual
   del proyecto (por rutas, hash, respaldo), previo plan aprobado.
2. **Fuente**: incluir Inter (OFL) en el tema (recomendado) o depender de la del sistema.
3. **Wallpaper por defecto**: fondo procedural en QML (degradado «tinta», sin binarios; recomendado) o
   una imagen original generada.
4. **Suspender/hibernar**: el requisito pide apagar y reiniciar; la API también expone suspender.
   Propuesta: sólo apagar/reiniciar por defecto, suspender como opción de configuración apagada.

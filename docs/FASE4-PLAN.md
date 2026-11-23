# Sumi SDDM — Fase 4: plan de integración con Settings de Sumi Shell

Fecha: 2026-11-22. **Aprobado** por el autor el 2026-11-22 con las tres recomendaciones de §5 (Desktop tools →
«Login screen»; CLI por copia de usuario en `~/.local`; cambios al momento, agrupados). Estado: parte A hecha
([informe](FASE4-INTEGRACION.md)); parte B sin empezar. Ejecutar `install --user` de verdad y tocar Quickshell
siguen necesitando autorización.

## 0. Lo que se encontró (sólo lectura)

- Settings es `surfaces/Settings.qml` (6136 líneas): un árbol declarativo grupo → página → sección → filas
  (`{ id, prop, kind, name }`). Cada `kind` se pinta con un `Component` elegido en una cadena de un `Loader`.
  Las filas de tipo `choice`/`toggle` escriben en `Settings[prop]` (`settings.json`). Las secciones con
  `dynamic: "<x>"` piden sus filas a `dynRows(x)`. El índice lateral está en `lib/settings-nav.js`.
- Los datos que no son de la shell van por un servicio que lanza un helper en su propio proceso. Ejemplo:
  `services/Appearance.qml` + `scripts/appearance.py`, con JSON, un token para no pisar cambios ajenos y
  `claim()` (no corre nada hasta que la página está abierta).
- Las integraciones opcionales van detrás de una capacidad (`scripts/capabilities.py` →
  `services/Capabilities.qml`); sin ella, la UI explica por qué falta.
- dotfiles `main` tiene **trabajo sin commitear** justo en `Settings.qml`, `settings-nav.js`,
  `settings-schema.js` y otros nueve archivos: la navegación por grupos de hoy. El vivo es idéntico a ese
  trabajo. Cualquier cambio irá encima, con guarda de hash, sin tocar ni commitear lo suyo.
- El servicio `sumi-shell` tiene `~/.local/bin` en su `PATH` (comprobado con `systemctl --user show-environment`).
- `preview --json` tarda unos 1,4 s.

## 1. Principios

1. **Independencia.** La shell no importa ningún archivo de Sumi-SDDM. Sólo ejecuta la orden `sumi-sddm`
   del `PATH`, con argumentos fijos. Sin ella, la página dice cómo instalarla y el resto de la shell sigue
   igual. Sumi-SDDM no sabe nada de la shell. Sin enlaces simbólicos entre repositorios.
2. **Un dueño por dato.** La configuración del tema es de Sumi-SDDM (`~/.config/sumi-sddm/`). No entra en
   `settings.json`, en `settings-schema.js`, en presets ni en Export/Import.
3. **Sin privilegios en esta fase.** Settings sólo cambia la configuración personal preparada. Llevarla a la
   pantalla de inicio de sesión real es la Fase 5 (helper con `pkexec`); la página lo dice claramente.
4. **Ningún texto de QML llega a un shell.** `Process` con `argv` fijo (`config set CLAVE=VALOR`); la CLI
   vuelve a validar con la lectura estricta. Nada de `sh -c`.

## 2. Parte A — en Sumi-SDDM (este repositorio)

| # | Cambio | Archivos |
|---|---|---|
| A1 | Contrato JSON versionado: `sumi-sddm version --json` → `{ok, api: 1, schema: 1, version}`; todas las respuestas `--json` llevan `api`; documento del contrato y pruebas que fijan los campos | `tools/sumi-sddm`, `docs/CLI-JSON.md`, `tests/py/test_contract.py` |
| A2 | Concurrencia: `flock` en `~/.config/sumi-sddm/.lock` para toda escritura, y `config set --expect <huella>` (sha256 del archivo leído) para que Settings no pise un cambio hecho desde la terminal | `tools/sumi-sddm`, `tools/sumiconf/ini.py`, pruebas |
| A3 | `config fonts --json`: familias de `fc-list` para ofrecer `fontFamily` como lista y avisar si la elegida no está instalada (sólo lectura) | `tools/sumi-sddm`, pruebas |
| A4 | Instalación de usuario, sin privilegios: `install --user` **copia** CLI + `sumiconf` + tema + arnés a `~/.local/share/sumi-sddm/` y escribe el lanzador `~/.local/bin/sumi-sddm` (un script, no un enlace); `uninstall --user` lo quita | `tools/sumi-sddm`, pruebas con HOME temporal |
| A5 | Versión del proyecto en un solo sitio (`VERSION`) | `VERSION`, `tools/sumi-sddm` |

A1–A3 y A5 sólo tocan este repositorio. **Ejecutar A4 de verdad** escribe en tu `~/.local`: lo haré sólo
cuando lo autorices (las pruebas usan un HOME temporal).

## 3. Parte B — en Sumi Shell (requiere tu autorización)

Se prepara en una copia privada (`~/Projects/Quickshell/.sddm-settings-20261122/`, ignorada por git, como
las demás entregas). Se prueba en el banco y se entrega en una segunda autorización, siguiendo
`docs/PROCEDIMIENTOS.md`: por rutas, con guarda de hash, respaldo en `~/.local/state/sddm-settings-20261122/`
y vuelta atrás probada.

### Archivos nuevos (sin conflicto con tu trabajo sin commitear)

- **`services/SddmTheme.qml`** (singleton). Lanza `sumi-sddm` sólo con verbos fijos: `version`,
  `config schema|show|set|unset|reset|restore`, `wallpaper set|clear|info`, `preview`, `try --yes`.
  - Interpreta el JSON y expone `schema`, `values`, `custom`, `error`, `busy` y `previewPng`.
  - Las escrituras se agrupan: un deslizador escribe al soltarlo o tras 300 ms quieto. Llevan
    `--expect <huella>`; si otra parte cambió el archivo, se recarga y se avisa.
  - Tras cada escritura, la vista previa se rehace con 600 ms de espera y sólo una a la vez.
  - `claim()` como Appearance: con la página cerrada no corre nada.
- **`components/SddmField.qml`**: una fila por clave del esquema; el control sale del tipo y la etiqueta y
  la ayuda salen del esquema (en inglés).

  | Tipo | Control |
  |---|---|
  | `bool` | `Toggle` |
  | `enum` | `Choice` |
  | `number` / `integer` | `Slider`, con mínimo, máximo y paso del esquema |
  | `color` | campo hex con muestra |
  | `string` | `FormField`; `fontFamily` como lista de `config fonts` |
  | `path` | elegir imagen → `wallpaper set`, y quitarla |

  Junto a cada valor personalizado hay un botón para restablecerlo (`config unset`).
- **`components/SddmPreview.qml`**: la imagen de `preview`, con selector de escena (compacta, expandida,
  sesiones, error) y el botón «Open test window». Este botón avisa de que toma el teclado antes de lanzar
  `try --yes`.

### Archivos existentes que se modifican (cambios pequeños, encima del vivo actual)

| Archivo | Cambio |
|---|---|
| `lib/settings-nav.js` | una página en el grupo elegido + su descripción |
| `surfaces/Settings.qml` | la página en el árbol (Estado · Vista previa · una sección dinámica `sddm:<grupo>` por cada uno de los 9 grupos · Cambios: Reset/Restore); una rama en `dynRows`, un `kind` en el `Loader` con su `Component`, las acciones y las palabras de búsqueda. Unas 60–80 líneas. |
| `scripts/capabilities.py` | capacidad `sddm.theme`: `sumi-sddm` en el `PATH` y `version --json` con `api == 1` |
| `components/qmldir`, `services/qmldir` | registrar los tipos nuevos |

### Lo que no se toca

`settings-schema.js`, `settings.json`, el contrato IPC público (no hay verbos nuevos), Lock, PAM,
`sddm.conf`, `/etc` y `/usr`.

## 4. Verificación

- **Sumi-SDDM:** `tools/sumi-sddm check` más las pruebas nuevas de contrato, bloqueo, `--expect`,
  fuentes e instalación de usuario.
- **Banco de la shell** (HOME/XDG privados, buses privados, un banco a la vez):
  - `qmllint` de los archivos nuevos y cambiados, y `settings-nav.check()`.
  - La página con un `sumi-sddm` falso (respuestas fijas y fallos: no instalado, `api` distinto, JSON roto,
    salida con error) y con el real sobre un XDG temporal.
  - Capturas en los tamaños de texto y en los dos estilos (soft/terminal).
  - Arranque en frío.
- **Entrega en la sesión** (autorización aparte): «Configuration Loaded» sin avisos nuevos, mismo PID,
  `NRestarts=0`, `settings.json` intacto y vuelta atrás probada. No abro Settings en tu sesión sin avisar.

## 5. Decisiones que te tocan

1. **Dónde va la página:**
   - **Desktop tools → «Login screen»**, junto a «Lock screen» (recomendado), o
   - Appearance → «Login screen», o
   - una entrada propia «SDDM».
2. **Cómo encuentra la shell la CLI:**
   - **copia de usuario en `~/.local` (A4)** (recomendado: no depende del checkout de desarrollo), o
   - un ajuste en Settings con la ruta al checkout.
3. **Cuándo se escriben los cambios:**
   - **al momento, agrupados** (recomendado: sólo cambian la configuración preparada, y la Fase 5 tendrá su
     botón explícito para aplicarlos al sistema), o
   - borrador con botón «Save», como Icons & cursor.

# Plan: editor gráfico independiente (sin Sumi Shell)

> Estado: **decisiones tomadas; fase 0 cerrada** (paquete 0.5.0-1 instalado y probado por el autor el 2026-11-23:
> `/usr/bin/sumi-sddm` responde `kind: "system"`, el tema sigue activo y en sincronía; la copia de usuario se
> quitó con `uninstall --user`). **Fase 1 hecha** (backend sin ventana, 33 pruebas). **Fase 2 hecha** (formulario). **Fase 3 hecha** (vista
> previa, fuentes, avatar; 28 pruebas de ventana en total). Fases 4–5 sin empezar. Escrito el 2026-11-23, después de añadir `sumi-sddm config edit` y las
> sugerencias de clave.

## Por qué

Hoy hay dos formas de configurar el tema:

- la CLI (`config set`, `config edit`, `wallpaper`, `avatar`, `preview`, `system …`);
- Settings de Sumi Shell (Desktop tools → Login screen).

Quien instale el tema sin Sumi Shell sólo tiene la terminal. El editor gráfico cubre ese hueco **sin crear una
tercera fuente de verdad**: es un cliente más del contrato JSON (`docs/CLI-JSON.md`), igual que Settings.

## Principios (no negociables)

1. **La CLI decide.** El editor no valida por su cuenta ni escribe archivos: lanza `sumi-sddm … --json` con `argv`
   y verbos fijos. La validación estricta, el bloqueo, la huella y el helper siguen en un solo sitio.
2. **El formulario sale del esquema** (`config schema --json`). Si mañana hay una clave nueva, aparece sin tocar
   el editor. No hay listas de claves escritas a mano.
3. **El tema no depende del editor.** El paquete del tema sigue sin pedir PySide6. El editor es opcional.
4. **Nada privilegiado sin pkexec.** «Aplicar», «Usar como pantalla de inicio» y «Restaurar» pasan por
   `sumi-sddm system …` → helper → polkit, como en Settings. El editor nunca corre como root.
5. **Comportamiento igual al de Settings**, para que las dos superficies no se contradigan:
   - escritura agrupada (300 ms quieto) con `--expect`;
   - vista previa 600 ms después del último cambio, una a la vez;
   - ante un `conflict`, recarga y avisa;
   - las acciones con riesgo piden dos pulsaciones.

## Decisiones

Elegidas por el autor el 2026-11-23: **todas las recomendadas** (D1 PySide6 + QML, D2 paquete dividido, D3 inglés,
D4 `sumi-sddm-editor` + `.desktop`, D5 mostrarlo siempre, también con Sumi Shell). La tabla queda como registro.

| # | Decisión | Elegida | Alternativas descartadas |
|---|---|---|---|
| D1 | Tecnología | **PySide6 + QML**: el proyecto ya es Python, no hay compilación y el paquete sigue `arch=any` | C++/Qt (sin dependencia Python pesada, pero con compilación y `arch=x86_64`); QML puro con un plugin C++ propio para lanzar procesos |
| D2 | Empaquetado | **Paquete dividido** (`pkgbase=sumi-sddm`): `sumi-sddm` (tema + helper + CLI) y `sumi-sddm-editor` (depende de `pyside6`) | Un solo paquete con `pyside6` en `optdepends` |
| D3 | Idioma de la interfaz | **Inglés**, como las `label`/`help` del esquema y Settings; traducible más tarde con `qsTr` | Español (habría que añadir etiquetas en español al esquema; hoy `doc` está en español, pero es texto largo de documentación) |
| D4 | Nombre y lanzador | `sumi-sddm-editor` + `.desktop` «Login Screen (Sumi)» | Subcomando `sumi-sddm gui` |
| D5 | ¿Apagado en Sumi Shell? | Si existe Settings, el `.desktop` puede llevar `NotShowIn=` o un aviso «también en Settings»; **sugiero no ocultarlo** | Ocultarlo cuando la capacidad `login.sddmTheme` esté presente |

## Requisito previo: la CLI en el paquete (fase 0) — hecha en 0.5.0

Hasta la 0.4.2 el paquete instalaba el tema, el helper y una parte de `sumiconf`. **La CLI no**: se copiaba a
mano con `install --user`. Un editor publicado no puede depender de eso.

Cómo quedó: la raíz de la CLI es `/usr/lib/sumi-sddm/` (la misma del helper); `theme/sumi` es un enlace relativo
al tema instalado (`../../../share/sddm/themes/sumi`), así que no se duplica; `state.kind()` responde `"system"`
cuando el helper está junto a la CLI. `preview`/`try` copian el tema **sin** `theme.conf.user` ni
`backgrounds/` (los que deja el helper al aplicar), así la vista previa enseña sólo lo guardado por el usuario.
`test_packaging.py` ejecuta el `package()` del PKGBUILD en un directorio temporal y prueba la CLI resultante
(también corre en el `check()` del paquete). Settings no mira `kind`: el valor nuevo no le afecta.

- Instalar `tools/sumi-sddm`, `tools/sumiconf/` completo, `tools/harness/` (para `preview`), el esquema y
  `docs/CONFIG.md` bajo `/usr/lib/sumi-sddm/`.
- Añadir un lanzador `/usr/bin/sumi-sddm` (script, no enlace, igual que el de `install --user`).
- `state.kind()` debe distinguir un tercer caso: `"system"`. `version --json` ya lo expone y los clientes deben
  tolerar valores nuevos. Hay que confirmar que esto no rompe el contrato `api 1`: añadir un valor a `kind` es
  compatible si los clientes no hacen `switch` cerrado (Settings no lo hace).
- Prioridad en el PATH: `~/.local/bin` (copia de usuario, si existe) gana a `/usr/bin`. Es lo deseable para
  desarrollo. Documentarlo.
- `install --user` sigue existiendo para quien no use el paquete.
- Pruebas: `test_packaging.py` comprueba que el paquete construido contiene la CLI y que
  `/usr/bin/sumi-sddm version --json` responde con `kind: "system"` (en un `fakeroot`/directorio extraído).

Esto es útil por sí solo (la CLI pasa a estar disponible para todos) y puede hacerse antes que el editor.

## Arquitectura

```
editor/
  sumi_sddm_editor/
    __main__.py        arranque: QGuiApplication, QQmlApplicationEngine, registra Backend
    backend.py         QObject: cola de QProcess `sumi-sddm … --json`, mismas reglas que SddmTheme.qml
    Main.qml           ventana: barra lateral de grupos + formulario + vista previa
    Field.qml          una clave del esquema → un control según su tipo
    Preview.qml        PNG de `preview` + selector de escena
    SystemPanel.qml    estado del sistema, Aplicar / Usar / Restaurar, prueba en ventana
    AvatarRow.qml      avatar (AccountsService)
  sumi-sddm-editor.desktop
  icon.svg
```

### Backend (Python)

Es una traducción de `integration/sumi-shell/services/SddmTheme.qml`, cambiando `Quickshell.Io.Process` por
`QProcess`. Es la parte con más lógica, así que se escribe primero y con pruebas.

- `QProcess` con `program` + `arguments`, sin shell. La orden se busca con `shutil.which("sumi-sddm")`. Si no
  está, o `version --json` no responde con `api == 1`, el estado es `missing` / `incompatible` y la ventana lo
  explica (con el enlace a la instalación).
- Un proceso a la vez y en cola. `show`, `preview`, `system` y `avatar` no se duplican en la cola. Las órdenes
  `system` corren en su propio proceso, porque esperar a polkit no debe bloquear la cola.
- Propiedades expuestas a QML: `status`, `groups`, `keys`, `order`, `values`, `stamp`, `warnings`, `fonts`,
  `error`, `notice`, `system`, `systemBusy`, `avatar`, `previewUrl`, `busy`.
- Métodos: `set(key, value)`, `unset(key)`, `setWallpaper(path)`, `clearWallpaper()`, `setAvatar(path)`,
  `clearAvatar()`, `resetAll()`, `restorePrevious()`, `systemApply()`, `activateSystem()`,
  `deactivateSystem()`, `openTestWindow()`, `reload()`.
- Al volver el foco a la ventana: `config show` y comparar `stamp`. Si alguien cambió algo desde la terminal o
  desde Settings, se recarga con un aviso discreto. No hace falta vigilar el archivo.

**Cómo quedó (fase 1).** `editor/sumi_sddm_editor/backend.py`, sólo QtCore. Además de lo de Settings:

- cada orden de la cola tiene tiempo límite (60 s; la vista previa 120 s) y, si vence, se mata y se informa
  `sumi-sddm did not answer in time`; las de `system` no tienen, porque esperan a una persona;
- `recheck()` (para el foco) avisa «Changed outside the editor · reloaded» sólo si la huella cambió por algo ajeno;
- `previewEnabled` y `previewSize` (escribibles), y `scenarios`, `captionFor`, `enumLabel`, `step` para el formulario;
- las rutas de `FileDialog` (`file:///…`) y `~/…` se convierten a ruta local antes de llamar a la CLI.

Pruebas: `tests/py/test_editor_backend.py` con `tests/py/fake_sumi_sddm.py` (una CLI falsa que registra cada
argv y se gobierna con un `state.json`). Se comprobó que detectan fallos rompiendo el backend a propósito (sin
deduplicar, varios procesos a la vez, sin `--expect`, conflicto sin descartar lo pendiente, vista previa antes
de guardar, recarga que pisa lo pendiente, apply sin esperar, Try sin dos pulsaciones). Sin PySide6 se saltan.

### Formulario (QML)

| Tipo del esquema | Control |
|---|---|
| `bool` | interruptor |
| `enum` | segmentado si hay ≤ 4 valores; si no, desplegable |
| `integer` / `number` | deslizador + campo numérico (`min`, `max`, `step`; `allowZero` como opción «Off») |
| `color` | muestra + campo hex + `ColorDialog` (con alfa para `#AARRGGBB`) |
| `string` (`fontFamily`) | desplegable con búsqueda desde `config fonts`; las familias que sólo están en `$HOME` se marcan y avisan (el greeter no las ve) |
| `string` (otros) | campo de texto |
| `path` (`background`) | botón «Choose image…» → `FileDialog` → `wallpaper set`; «Remove» → `wallpaper clear` |

- Cada campo muestra `label`, `help` como texto secundario, el punto «personalizado» y «Reset» (→ `unset`).
- `warnings` de `config show` aparecen junto a su clave (p. ej. la fuente).
- Barra lateral con los grupos del esquema y búsqueda por nombre o etiqueta.
- Pie: «Reset all» (copia `.prev`) / «Restore previous», con dos pulsaciones.

**Cómo quedó (fase 2).** `Main.qml` + `Field.qml` (Qt Quick Controls, estilo Fusion salvo que
`QT_QUICK_CONTROLS_STYLE` diga otro), `__main__.py` y el lanzador de desarrollo `editor/sumi-sddm-editor`.

- Adelantado de la fase 3: el fondo ya se elige con `FileDialog` → `wallpaper set` y se quita con «Remove».
  Sigue para la fase 3: el selector de fuentes (hoy `fontFamily` es un campo de texto), el avatar y la vista previa.
- Antes de enviar se comprueba lo evidente (rango, hex, `pattern` del esquema) para dar el aviso en inglés junto
  al campo. Si aun así la CLI rechaza algo, su mensaje (en español) se enseña en el pie, como en Settings.
  Pendiente: que la CLI dé esos errores también en inglés, como ya hace con `warnings`.
- Al cerrar con una escritura pendiente (los 300 ms de agrupado), se escribe antes de salir (`flushNow`).
- Pruebas: `tests/py/test_editor_ui.py`, offscreen y con eventos reales (clic, teclas, Enter con el foco). Cada
  prueba exige cero avisos de QML. El criterio de salida se prueba con la CLI del repositorio y un
  `XDG_CONFIG_HOME` temporal: lo editado llega a `theme.conf.user`; un `config set` desde la terminal produce el
  aviso (al recuperar el foco o por `--expect`) y no se pierde. Comprobadas con roturas a propósito; dos de ellas
  (re-enlazar Switch y ComboBox tras editar) mostraron que ese código sobraba en Qt 6 y se quitó.

### Vista previa

- `preview --scenario S --size AxH --json`, 600 ms después del último cambio guardado. Así se previsualiza
  siempre lo guardado, que es lo que verá el greeter. Mientras se genera, la imagen anterior se queda atenuada;
  si falla, se muestra `error`.
- Escenas: las de `SCENARIOS` (compacta, expandida, fallo, sesiones…). Tamaño: el de la pantalla principal, con
  un selector.
- «Try in a window» → `try --yes` tras un aviso claro: toma el teclado y se cierra con Esc / cerrando la
  ventana.

**Cómo quedó (fase 3).** `Preview.qml` (columna derecha, se puede ocultar y entonces no se genera ninguna),
`AvatarRow.qml` (primera fila de Users; también aparece al buscar «avatar»/«picture») y el selector de fuentes en
`Field.qml`.

- Tamaño por defecto: el de la pantalla en píxeles físicos (`Screen.width × devicePixelRatio`), marcado
  «(this screen)»; escenas, las cuatro de Settings. Cada vista previa tarda ~1,4 s (OpenGL).
- Fuentes: lista con búsqueda de `config fonts`, cada familia en su letra (las de métricas enormes se encogen
  para caber); las que sólo están en `$HOME` llevan «Only in your home folder · the login screen can't use it»
  y, si se eligen, `config show` añade su aviso junto al campo. Sin lista (sin fc-list), campo de texto.
- Fondo y avatar: además del diálogo, se puede soltar una imagen sobre la fila (los dos van a `choose(url)`).
- Fallo encontrado por las pruebas: otra foto de avatar se guarda con el mismo nombre y la respuesta de la CLI es
  idéntica, así que la ventana seguía enseñando la anterior. El backend ahora emite el cambio siempre tras
  `avatar set` (Settings no lo tenía: en QML cada objeto nuevo cuenta como cambio).
- La salida de la aplicación (`aboutToQuit`) llama a `backend.shutdown()`: para temporizadores, vacía la cola y
  termina los procesos de la cola (no los de `system`).
- Criterio de salida probado con la CLI del repositorio: al cambiar «Base colour» a rojo y luego a verde, la
  esquina del PNG de la vista previa pasa a ser roja y luego verde.
- Ruido conocido: al abrir la lista de fuentes, Qt escribe en la terminal «Failed to compute left/right minimum
  bearings» por algunas fuentes de mapa de bits (.pcf). No afecta a nada.

### Panel del sistema

- `system status`: instalado, activo (y qué archivo lo decide), «lo aplicado coincide con lo guardado».
- «Apply to login screen» (`system apply`) se habilita cuando `inSync` es falso. Espera a que no queden
  escrituras pendientes, como hace Settings.
- «Use as login screen» / «Restore previous theme»: dos pulsaciones y el texto de qué pasará y cuándo
  («la próxima vez que se muestre la pantalla de inicio»).
- Enlace a `RECUPERACION.md` (instalado en `/usr/share/doc/sumi-sddm/`).
- `system log`: «Last login screen: OK / problems», con los problemas desplegables.

## Fases

| Fase | Contenido | Criterio de salida |
|---|---|---|
| **0** | CLI en el paquete (sección anterior) | paquete construido con `/usr/bin/sumi-sddm`; `check` y `test_packaging` en verde; instalado y probado por el autor |
| **1** | `backend.py` + pruebas con una CLI falsa (script que responde JSON fijo, conflictos, `busy`, `missing`, api distinto) | todas las transiciones de estado cubiertas; sin ventana |
| **2** | Formulario generado desde el esquema, sin vista previa ni sistema | todas las claves editables; las escrituras llegan a `theme.conf.user`; un `config set` desde la terminal con la ventana abierta produce un aviso y no se pierde |
| **3** | Vista previa, wallpaper, fuentes, avatar | la vista previa refleja cada cambio; las fuentes sólo de `$HOME` avisan |
| **4** | Panel del sistema (pkexec) | Apply / Use / Restore probados **por el autor** en real; cancelar polkit = `denied` y nada cambia |
| **5** | Paquete dividido, `.desktop`, icono, accesibilidad (teclado completo, `Accessible.name` desde `label`), tema claro/oscuro del sistema | `namcap` limpio; se abre desde el lanzador de aplicaciones en una sesión que no es Hyprland (p. ej. KDE o GNOME en una VM) |

## Pruebas

- **Python** (`tests/py/test_editor_backend.py`): el backend con un `sumi-sddm` falso en un `PATH` temporal.
  Comprueba orden y agrupado de escrituras, `--expect`, recarga tras un `conflict`, `missing` / `incompatible` y
  que nunca pasa por un shell (los argumentos con espacios y comillas llegan intactos).
- **QML** (`tests/qml/tst_editor_field.qml` con `qmltestrunner`): `Field.qml` con cada tipo del esquema y un
  backend doble. Cada control produce el valor en el formato que espera `config set`.
- **Humo**: el editor en `QT_QPA_PLATFORM=offscreen` con HOME/XDG temporales, captura de pantalla y salida sin
  avisos de QML. Se añade a `tools/sumi-sddm check` sólo si `pyside6` está instalado (si no, se salta con un
  aviso, como las pruebas que necesitan ImageMagick).
- **Paridad con Settings**: un mismo guion de cambios aplicado desde el editor y desde el banco de Settings
  (`integration/sumi-shell/bench`) deja el mismo `theme.conf.user`.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Dos UIs (Settings y editor) que divergen | las dos son clientes finos del mismo contrato; la prueba de paridad; los dos generan el formulario desde el esquema |
| `pyside6` es una dependencia grande | paquete separado; el tema no la necesita |
| Abrir pkexec desde una app sin agente de polkit (sesiones mínimas) | `denied` / error claro con la orden equivalente en la terminal |
| La vista previa necesita `qml` y OpenGL | ya está resuelto en `preview` (`--backend auto` cae a software) |
| Cambiar `kind` en `version --json` | valor nuevo, no campo cambiado; revisar Settings antes de publicar la fase 0 |

## Fuera de alcance

- Editar la configuración del sistema directamente (siempre: guardar como usuario → `system apply`).
- Configurar SDDM en sí (autologin, sesión por defecto, usuarios ocultos): es de SDDM y del sistema, no del tema.
- Sustituir Settings de Sumi Shell: el editor es para quien no la tiene.

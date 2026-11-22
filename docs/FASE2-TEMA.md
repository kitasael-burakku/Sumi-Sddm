# Sumi SDDM — Fase 2: tema independiente

Fecha: 2026-11-22. Todo el trabajo está en `~/Projects/Sumi-SDDM/`. No se modificó Quickshell, dotfiles,
`/etc`, `/usr` ni el tema Orbital; no se usaron privilegios ni se abrió ninguna ventana (todas las
ejecuciones fueron `QT_QPA_PLATFORM=offscreen`).

## 1. Componentes

| Archivo | Papel |
|---|---|
| `Main.qml` | Adaptador: `userModel`, `sessionModel`, `sddm`, `keyboard`, `config`, `primaryScreen` → propiedades de `Greeter`. Comprueba cada una con `typeof`. |
| `Greeter.qml` | Estado y lógica: usuario/sesión iniciales (`lastUser`, `lastIndex`), modos de la notch (`compact`/`expanded`/`sessions`/`confirm`), estados de autenticación (`idle`/`authenticating`/`failed`/`succeeded`), mensajes, teclado, tiempo de espera de autenticación, inactividad, energía con confirmación, multimonitor. |
| `Style.qml` | Única lectura de la configuración: tipos, rangos, enumeraciones, colores `#RRGGBB[AA]`, rutas (rechaza `..` y esquemas remotos), listas de QSettings. Escala por resolución sensible a la orientación. |
| `Notch.qml` + `NotchShape.qml` | Silueta pegada al borde con hombros cóncavos y esquinas inferiores redondeadas; tamaño animado; sombra sacada de una copia oculta (si MultiEffect falla, sólo se pierde la sombra). |
| `Background.qml` | Color base + «tinta» procedural (aguadas radiales) + wallpaper opcional con blur opcional + oscurecimiento + sombra superior. |
| `Clock.qml` | Hora (12/24 h, segundos opcionales) y fecha con formato de Qt; 5 posiciones; escala propia. |
| `UserStrip.qml` + `Avatar.qml` | Selector inferior; avatar circular o iniciales (sin imagen, cara genérica de SDDM o imagen rota); «Other…» para entrada manual. |
| `InputField`, `IconButton`, `PillButton`, `Spinner`, `Icon` | Controles con anillo de foco, `Accessible.*` y activación con Intro/Espacio. Iconos propios dibujados con Shapes. |
| `assets/fonts/` | Inter 4 sin modificar (hash idéntico al del paquete) + `OFL.txt`. |

### Decisiones de seguridad y acceso
- La contraseña sólo vive en el `TextInput` y en la llamada a `login`. Se borra con `text = ""` (comprobado:
  `clear()` deja el historial de deshacer disponible; `text = ""` lo vacía) al fallar, al acertar, al cambiar de
  usuario, con Esc y al recogerse por inactividad. Sin copiar, sin selección con ratón, pistas de dato sensible.
- El registro sólo escribe recuentos: `sumi-sddm: ready users=N sessions=N primary=… clock=…`.
- Nunca se bloquea el acceso por configuración: sin usuarios listados la entrada manual es obligatoria aunque
  `manualUser=never`; con `multiMonitor=all` (por defecto) todas las pantallas permiten iniciar sesión.
- Energía: el botón sólo aparece si SDDM la declara posible; siempre pide confirmación con **Cancel**
  enfocado (Intro por accidente cancela); se cancela sola a los 30 s. Suspender desactivado por defecto.
- Si el servicio no responde en `authTimeout` (30 s), el formulario se reactiva con un aviso.
- Doble envío imposible; controles de sesión/energía deshabilitados mientras autentica.

## 2. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `qmllint --max-warnings 0` (20 archivos; `Main.qml` sin el aviso de acceso no calificado, que es el contexto de SDDM) | 0 avisos |
| `qmltestrunner`, 42 casos, renderizador **software** | 42/42 |
| `qmltestrunner`, 42 casos, renderizador **OpenGL** (RHI) | 42/42; 30 ejecuciones seguidas sin fallos tras corregir la prueba intermitente (§3) |
| Greeter real `sddm-greeter-qt6 --test-mode` offscreen, copia en `~/.cache/sumi-sddm/smoke`, software y OpenGL | Carga sin ningún aviso QML; lee el `userModel` (1) y el `sessionModel` (2) reales |
| Greeter real con `theme.conf.user` válido (`tests/fixtures/valid.conf.user`) | Se aplica (`clock=12h`) |
| Greeter real con `theme.conf.user` basura (`tests/fixtures/garbage.conf.user`) | Carga sin avisos, valores por defecto |
| Capturas: 16 escenarios × 5 resoluciones (1366×768, 1920×1080, 2560×1440, 3840×2160, 1080×1920), OpenGL | 80/80 sin avisos, revisadas visualmente por muestreo |
| Wallpaper + blur 60, OpenGL y software | Blur con OpenGL; nítido (reserva prevista) con software |

Casos cubiertos por `tst_greeter.qml`: estado inicial y preselección, inicio expandido, primer carácter en
compacta no se pierde, Intro/Esc, recorrido con Tab, envío único con la sesión elegida, contraseña vacía,
fallo (borrado, sin deshacer, error visible, foco, reintento), éxito, mensajes de PAM saneados, tiempo de
espera, backend ausente, sin sesiones, cambio de usuario (borrado), teclado y clic en el selector, usuario
sin contraseña, entrada manual (con y sin usuarios, `never` no bloquea), «Other…», avatares rotos/vacíos,
selector oculto con un usuario en `auto`, lista de sesiones por teclado (Esc no cambia), energía
(confirmación obligatoria, Cancel por defecto, teclado, ratón, Esc, acciones no disponibles, suspender
opcional), Bloq Mayús, recogida por inactividad con borrado, pantalla secundaria en modo `primary`,
configuración inválida, listas de QSettings, rutas remotas/inexistentes, animaciones apagadas, escala.

## 3. Problemas encontrados

Resueltos durante la fase:
- `qmltestrunner`: el `TestCase` es invisible por defecto; sus hijos heredaban `visible=false` (fallo de la
  prueba, no del tema).
- Las pruebas leían el estado antes de `init()` (diferido): se añadió `Greeter.ready`.
- `Clock` declaraba `left`/`right`, propiedades FINAL de `Item`: el Greeter no cargaba. Renombradas.
- Bucle potencial `sourceSize` ↔ estado de carga en `Background`.
- `activeFocusOnTab` ligado a `enabled` provocaba avisos al deshabilitar un control enfocado.
- Escala diminuta en pantallas verticales.
- Prueba intermitente con OpenGL (4 de 30): `test_other_tile_when_manual_always` hacía clic antes de que el
  `Row` se colocara (polish pendiente en el bucle de render de OpenGL) y el clic caía en otro mosaico. Los clics
  de las pruebas esperan ahora a que no quede polish pendiente; 30/30 después. Era un defecto de la prueba.
- El modo offscreen usa por defecto el renderizador **software** (sin MultiEffect): las pruebas y capturas se
  ejecutan ahora con ambos.

Abiertos:
- `--test-mode` no tiene daemon: **no se ha probado la autenticación real, ni apagar/reiniciar reales**, ni
  los valores reales de `canPowerOff/canReboot/canSuspend`. Requiere el greeter real o Xephyr + `sddm --test-mode`
  (Xephyr no está instalado).
- **Multimonitor** sólo simulado (`primary=false`); un único monitor físico.
- **Avatar real**: la cuenta no tiene avatar en AccountsService/FacesDir y `$HOME` no es legible por `sddm`;
  sólo se han visto iniciales.
- Accesibilidad: roles y nombres declarados, pero no verificados con un lector de pantalla.
- Licencia del proyecto sin decidir.

## 4. Pendiente para la Fase 3

1. Esquema único de configuración (`schema/config-schema.json`) del que salgan la validación de la CLI, la
   documentación y una prueba que compare con los defaults de `Style.qml` y `theme.conf`.
2. `sumi-sddm config get|set|validate|reset` sobre `~/.config/sumi-sddm/theme.conf.user` (escritura atómica,
   comillas correctas para QSettings).
3. Wallpaper del usuario: validación (tipo real, tamaño, dimensiones) y copia a la zona de preparación,
   pensando en que el helper de la Fase 5 la copiará dentro del tema (el usuario `sddm` no lee `$HOME`).
4. Vista previa sin privilegios: `sumi-sddm preview` → PNG con la configuración del usuario (lo que usará
   Settings) y `sumi-sddm try` → ventana `--test-mode` (con aviso de que toma el teclado).
5. Claves que faltan del requisito: tamaños tipográficos por elemento, opacidad/colores del selector de
   usuarios, desplazamiento fino del reloj, duración base de animaciones.

# Configuración de Sumi SDDM

> Generado por tools/sumi-sddm gen desde schema/config-schema.json. No editar a mano.

El tema lee `theme.conf` (valores por defecto, dentro del tema) y después `theme.conf.user`, que lo
sobrescribe. Formato: INI de QSettings, sección `[General]`.

- **En el greeter** (QML) la lectura es tolerante: un valor que no se entiende vuelve al defecto y un número
  fuera de rango se acota. Una configuración rota nunca deja la pantalla inutilizable.
- **En `sumi-sddm config`** la validación es estricta: se rechaza en vez de corregir, y el archivo se escribe
  de forma atómica en `~/.config/sumi-sddm/theme.conf.user`. Para editarlo a mano con la misma validación:
  `sumi-sddm config edit` (abre `$EDITOR` con todas las claves comentadas y no guarda nada inválido).
- Las dos lecturas se comparan con los mismos casos (`tests/fixtures/config-vectors.js`).

Reglas de formato: los textos, colores y rutas se escriben entre comillas; sin comillas no se admiten `,`
`;` `"` ni `\`; ningún valor puede empezar por `@`; sólo existe la sección `[General]`.

## Fondo

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `background` | path | ruta (jpg, jpeg, png, webp) | `""` | Imagen de fondo. Vacío = fondo «tinta» generado en QML. Ruta relativa al tema (backgrounds/…) o absoluta bajo /usr/share; debe ser legible por el usuario «sddm». Con `sumi-sddm wallpaper set` se gestiona sola. |
| `backgroundFill` | enum | crop | fit | stretch | `crop` | Encaje de la imagen: crop (llenar recortando), fit (completa, con bandas), stretch. |
| `blurRadius` | number | 0–100 | `0` | Desenfoque del wallpaper, 0–100 (0 = nada). No se aplica al fondo generado ni con el renderizador software. |
| `dimOpacity` | number | 0–0.85 | `0.2` | Oscurecimiento sobre el fondo, 0–0.85. |
| `backgroundColor` | color | #RRGGBB | #AARRGGBB | `"#0c0d10"` | Color base, visible mientras carga la imagen o si falla. |

## Colores

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `accentColor` | color | #RRGGBB | #AARRGGBB | `"#a9bdff"` | Acento: anillos de foco, botón de enviar. |
| `textColor` | color | #RRGGBB | #AARRGGBB | `"#f3f3f5"` | Texto principal (los secundarios son este color con transparencia). |
| `errorColor` | color | #RRGGBB | #AARRGGBB | `"#ff8f87"` | Mensajes de error y botón de confirmación de energía. |
| `notchColor` | color | #RRGGBB | #AARRGGBB | `"#000000"` | Relleno de Login Edge. |
| `fieldColor` | color | #RRGGBB | #AARRGGBB | `"#1c1c1f"` | Campos y botones dentro de Login Edge. |

## Tipografía y escala

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `fontFamily` | string | texto (máx. 64) | `""` | Familia tipográfica instalada en el sistema. Vacío = Inter incluida en el tema. |
| `uiScale` | number | 0.5–2.0 | `1` | Escala global, además del ajuste automático a la resolución, 0.5–2. |
| `fontScale` | number | 0.75–1.5 | `1` | Tamaño del texto de Login Edge, botones y nombres, 0.75–1.5 (el reloj usa clockScale). |

## Login Edge

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `notchCompactWidth` | integer | 120–480 | `200` | Ancho de Login Edge recogido, en píxeles de referencia (1920×1080). |
| `notchCompactHeight` | integer | 24–64 | `34` | Alto de Login Edge recogido. |
| `notchExpandedWidth` | integer | 340–720 | `440` | Ancho de Login Edge desplegado (el alto depende del contenido). |
| `notchRadius` | integer | 4–48 | `22` | Radio de las esquinas inferiores. |
| `notchShoulder` | integer | 0–24 | `12` | Curva de unión con el borde superior (0 = sin curva). |
| `notchStartExpanded` | bool | true | false | `false` | true = Login Edge empieza desplegado; false = recogido (escribir lo despliega igualmente). |
| `notchIdleCollapse` | integer | 0 o 5–600 | `60` | Segundos sin actividad para recogerse y borrar la contraseña escrita: 0 (nunca) o 5–600. |

## Reloj

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `clockPosition` | enum | center | top-left | top-right | bottom-left | bottom-right | `center` | Posición del reloj. |
| `clockFormat` | enum | 24h | 12h | `24h` | Formato de hora. |
| `clockSeconds` | bool | true | false | `false` | Mostrar segundos. |
| `clockScale` | number | 0.5–2.0 | `1` | Tamaño relativo del reloj, 0.5–2. |
| `clockWeight` | enum | thin | light | regular | medium | `light` | Grosor de la hora. |
| `clockOffsetX` | integer | -600–600 | `0` | Desplazamiento horizontal fino, en píxeles de referencia. |
| `clockOffsetY` | integer | -400–400 | `0` | Desplazamiento vertical fino, en píxeles de referencia. |
| `dateFormat` | string | texto (máx. 48) | `"dddd, d MMMM"` | Formato de fecha de Qt (https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method). Vacío = por defecto. |

## Selector de usuarios

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `userStrip` | enum | always | auto | never | `always` | always | auto (se oculta con un solo usuario) | never. |
| `avatarSize` | integer | 40–120 | `64` | Diámetro del avatar. |
| `userNames` | bool | true | false | `true` | Mostrar el nombre bajo cada avatar. |
| `userInactiveOpacity` | number | 0.2–1.0 | `0.6` | Opacidad de los usuarios no seleccionados. |
| `userStripMargin` | integer | 16–300 | `64` | Distancia al borde inferior. |
| `manualUser` | enum | auto | always | never | `auto` | Entrada manual de usuario: auto (sólo si SDDM no lista usuarios) | always | never. Sin usuarios listados siempre está disponible. |

## Energía

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `showShutdown` | bool | true | false | `true` | Botón de apagar (sólo si SDDM lo permite; pide confirmación). |
| `showRestart` | bool | true | false | `true` | Botón de reiniciar (ídem). |
| `showSuspend` | bool | true | false | `false` | Botón de suspender (ídem). |

## Movimiento

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `animations` | bool | true | false | `true` | Activar animaciones. |
| `animationSpeed` | number | 0.25–3.0 | `1` | Multiplicador de velocidad: duración = base / velocidad, 0.25–3. |

## Comportamiento

| Clave | Tipo | Valores | Defecto | Descripción |
|---|---|---|---|---|
| `multiMonitor` | enum | all | primary | `all` | all (inicio de sesión en todas las pantallas) | primary (las demás sólo fondo y reloj). |
| `authTimeout` | integer | 5–120 | `30` | Segundos de espera a la respuesta del inicio de sesión antes de reactivar el formulario. |

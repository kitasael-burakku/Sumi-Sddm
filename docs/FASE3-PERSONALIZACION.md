# Sumi SDDM — Fase 3: personalización, validación y vista previa

Fecha: 2026-11-22. Todo en `~/Projects/Sumi-SDDM/`; sin privilegios, sin ventanas (offscreen), sin tocar
`/etc`, `/usr`, Quickshell ni la configuración real del usuario (las pruebas usan `XDG_CONFIG_HOME`
temporales; `~/.config/sumi-sddm/` no existe). Sólo se escribió en `~/.cache/sumi-sddm/` (copias de prueba).

## 1. Diseño

```
schema/config-schema.json ──gen──► components/schema.js   (datos para el QML)
            │                  ├──► theme/sumi/theme.conf  (defaults comentados)
            │                  └──► docs/CONFIG.md
            ▼
tools/sumiconf/schema.py   strict()  ← CLI (y el helper de la Fase 5)
                           lenient() ═ components/config.js (QML)   ← mismos casos: tests/fixtures/config-vectors.js
```

- **Una sola fuente.** `Style.qml` ya no tiene ningún valor por defecto propio: lee cada clave con
  `Config.read()` sobre el esquema generado. `gen --check` (dentro de `check` y de las pruebas) falla si
  algún artefacto está desactualizado.
- **Dos lecturas con un propósito distinto.** El greeter es tolerante (nunca bloquea el acceso). La CLI es
  estricta (rechaza, no corrige) y escribe todo o nada.
- **INI compatible con QSettings, sin ambigüedades.** Sólo `[General]`; textos/colores/rutas siempre entre
  comillas; sin comillas se rechazan `,` (QSettings haría una lista), `;` (comentario), `"` y `\`; sólo los
  escapes `\"` y `\\`; nada que empiece por `@` (QSettings lo deserializa como `@Variant`/`@ByteArray`);
  claves desconocidas o repetidas son error; máximo 64 KiB.
- **Escritura atómica**: temporal en el mismo directorio, `fsync`, `chmod 0644`, `rename`, `fsync` del
  directorio. No escribe a través de un enlace simbólico; la lectura usa `O_NOFOLLOW`.
- **Wallpaper**: se valida por contenido (no por extensión): JPEG (incluido progresivo), PNG y WebP (sólo si
  está `qt6-imageformats`), 320–16384 px por lado, ≤ 120 Mpx, ≤ 40 MiB; abierto con `O_NOFOLLOW` y comprobado
  con `fstat` sobre el mismo descriptor que se copia (sin carrera entre comprobar y copiar). Se copia a
  `~/.config/sumi-sddm/backgrounds/user.<ext>` y la configuración guarda `background="backgrounds/user.<ext>"`,
  la ruta relativa que tendrá dentro del tema instalado (el usuario `sddm` no puede leer `$HOME`).
  En modo estricto `background` sólo admite `backgrounds/<nombre>.<ext>` o una imagen bajo `/usr/share`.
- **Vista previa sin privilegios**: `preview` copia el tema a `~/.cache/sumi-sddm/preview/sumi` con la
  configuración y el wallpaper del usuario y lo captura offscreen con el arnés (`tools/harness/Render.qml`,
  que ahora carga el Greeter desde el directorio que se le indique). `try --yes` abre esa copia en el
  greeter real en una ventana; sin `--yes` sólo explica que toma el teclado.

## 2. Claves nuevas

`fontScale` (texto de notch, botones y nombres), `clockWeight`, `clockOffsetX`, `clockOffsetY`,
`userNames`, `userInactiveOpacity`, `userStripMargin`. Total: 41 claves en 9 grupos, cada una con etiqueta
y ayuda en inglés para la UI de Settings (`config schema --json`).

## 3. CLI

| Orden | Qué hace |
|---|---|
| `config path / schema / show / get` | consulta (todas con `--json`) |
| `config set CLAVE=VALOR …` | valida todas; si una falla, no escribe ninguna; `VALOR` vacío = quitar |
| `config unset / validate [ARCHIVO] / reset / restore` | `reset` deja copia en `theme.conf.user.prev` |
| `wallpaper set ARCHIVO / clear / info` | valida, copia, borra sólo nuestras copias `user.*` |
| `preview [--scenario] [--size] [--out]` | PNG con la configuración del usuario |
| `try --yes` | ventana `--test-mode` |
| `gen [--check]` | regenera / comprueba los artefactos |
| `check` | gen --check + lint + Python + QML (software y OpenGL) + 4 humos con el greeter real |

## 4. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `gen --check` | artefactos al día |
| `qmllint --max-warnings 0`, archivo a archivo (21) | 0 avisos |
| Python (`tests/py`, 30 casos): esquema, paridad, estricta, INI, escritura atómica, imágenes, CLI de extremo a extremo con XDG temporal, vista previa | 30/30 |
| QML (42 casos del Greeter + 5 de configuración/paridad; qmltestrunner cuenta además initTestCase/cleanupTestCase de cada archivo: 51), software | 51/51 |
| QML, OpenGL | 51/51 |
| Greeter real, tema sin `theme.conf.user` | `custom=0`, sin avisos |
| Greeter real con `valid.conf.user` | `custom=4` (lo esperado), sin avisos |
| Greeter real con `garbage.conf.user` | `custom=3` (lo que predice la lectura tolerante), sin avisos |
| Greeter real con un `theme.conf.user` escrito por la CLI (7 claves, fecha con coma entre comillas, wallpaper preparado) | `custom=7`, `clock=12h`, wallpaper cargado sin avisos |
| Regresión visual con la configuración por defecto, Fase 2 frente a Fase 3 (notch y selector, 6 escenarios) | 0 píxeles distintos |
| Vista previa con wallpaper, acento y nombre del usuario | revisada visualmente |

`custom=N` es el número de claves que el greeter real ve distintas de su defecto (se registra al arrancar;
no contiene valores). Compararlo con lo esperado prueba que el QSettings real y nuestro lector coinciden.

## 5. Problemas encontrados

Resueltos:
- `str.strip()` de Python recorta `\x1c`–`\x1f` y `trim()` de JavaScript no: se rompía la paridad en casos
  límite. Python recorta ahora el mismo conjunto que JS.
- Redondeo: `round()` de Python es bancario; se usa `floor(x + 0.5)` como `Math.round`.
- `"0x10"` es 16 para `Number()` de JS y un error para Python: ambos usan la misma expresión regular de número.
- `unittest discover -t` exige paquetes; se ejecuta sin `-t`.
- Una prueba de la vista previa medía un píxel oscuro del propio degradado de prueba; corregida tras revisar
  la imagen.

Abiertos / limitaciones:
- Nada de esto se ha aplicado al sistema: instalar el tema y copiar la configuración y el wallpaper dentro de
  él es la Fase 5 (helper con `pkexec`).
- La vista previa usa usuarios simulados (salvo el nombre del usuario actual) y no puede mostrar avatares
  reales: SDDM no puede leerlos (Fase 1).
- `fontFamily` acepta cualquier familia con caracteres seguros, pero no comprueba que esté instalada (si no
  existe, Qt usa otra). Se puede añadir con `fc-list` en la Fase 4.
- Inter no incluye glifos CJK: un nombre en japonés se dibuja con la fuente de reserva del sistema.

## 6. Pendiente para la Fase 4 (integración con Settings)

La integración sólo necesita la CLI: `config schema --json` (construir la página), `config show --json`
(estado), `config set … --json` (cambios), `wallpaper set|clear --json`, `preview --json` (imagen) y
`try --yes`. Antes de tocar Quickshell se presentará un plan específico para aprobación.

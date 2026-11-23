# Contrato JSON de `sumi-sddm` (api 1)

Lo que un programa (Settings de Sumi Shell u otro) puede esperar de `sumi-sddm … --json`. Las pruebas de
`tests/py/test_contract.py` fijan estos campos. Un cambio incompatible sube `api`; añadir campos, no.

## Reglas generales

- **Cómo se lanza.** Siempre con `argv` (nunca a través de un shell) y con verbos fijos. Los valores van en
  un solo argumento `CLAVE=VALOR`, y la CLI los valida de forma estricta aunque el cliente ya lo haya hecho.
- **Salida estándar.** Un único objeto JSON:

  ```json
  {"ok": true,  "api": 1, ...}
  {"ok": false, "api": 1, "code": "<código>", "error": "<texto para personas, en español>", ...}
  ```

- **Códigos de salida.**
  - `0`: correcto.
  - `1`: error con JSON.
  - `2`: uso incorrecto. Cuando el error lo detecta el analizador de argumentos (orden o argumento que no
    existe, `--expect` mal formado), sale texto en la salida de errores y **no hay JSON**. Un cliente con
    verbos fijos no debería verlo nunca.
- **`code` es estable; `error` no.** No conviene analizar el texto de `error`.

| `code` | Significado | Qué hacer |
|---|---|---|
| `invalid` | valor, clave o archivo no válidos (también un `theme.conf.user` roto) | enseñar `error` |
| `conflict` | `--expect` no coincide: otro cambió la configuración. Lleva `stamp` (la actual). En `install`/`uninstall`: `~/.local/bin/sumi-sddm` no es nuestro | recargar `config show` y avisar |
| `busy` | otra operación tiene el bloqueo (más de 5 s) o ya hay una ventana `try` abierta | reintentar más tarde |
| `missing` | falta algo necesario: copia `.prev`, `fc-list` | enseñar `error` |
| `io` | error del sistema de archivos (permisos, enlace simbólico donde no debe haberlo) | enseñar `error` |
| `render` | la vista previa no se pudo generar | enseñar `error` |
| `unsupported` | orden de desarrollo en la copia instalada, o `install` fuera del repositorio | — |
| `usage` | operación desconocida | — |

## Huella y concurrencia

- **`stamp`** es la huella de la configuración preparada: `theme.conf.user` más las copias del wallpaper.
  Son 32 caracteres hexadecimales.
  - La devuelven `config show`, `preview` y todas las escrituras.
  - Cambia con cualquier escritura, sea de la CLI o a mano.
  - No cambia al leer ni con una escritura que no cambia nada.
- **Escrituras.** Son `config set|unset|reset|restore` y `wallpaper set|clear`. Aceptan `--expect STAMP`:
  con el bloqueo tomado, si la huella ya no es esa, no escriben y responden `code: "conflict"`.
- **Bloqueo.** Toda escritura toma `flock` sobre `~/.config/sumi-sddm/.lock`. Las lecturas que devuelven
  `stamp` toman el bloqueo compartido, así que valores y huella son siempre una foto coherente.
- **Vistas previas.** Se hacen de una en una: hay un bloqueo propio en la caché.

## Órdenes

| Orden | Respuesta `ok: true` (además de `ok` y `api`) |
|---|---|
| `version --json` | `version` (del proyecto, `VERSION`), `schema` (versión del esquema), `kind`: `"checkout"` o `"user"` |
| `config schema --json` | `version`, `section`, `groups: [{id, label, …}]`, `keys: [{key, group, type, default, label, help?, min?, max?, step?, values?, …}]` |
| `config show --json` | `version`, `path`, `stamp`, `values: {clave: {value, default, set}}`, `warnings: [{key, message}]` (mensajes en inglés, para la UI) |
| `config get CLAVE --json` | `key`, `value`, `set` |
| `config path --json` | `path` |
| `config fonts --json` | `families: [{family, system}]`. `system: false` = sólo en tu `$HOME`: el greeter (usuario `sddm`) no la verá |
| `config validate [ARCHIVO] --json` | `path`, `keys` |
| `config set CLAVE=VALOR… [--expect S] --json` | `stamp`. Todo o nada; `VALOR` vacío = quitar la clave |
| `config unset CLAVE… [--expect S] --json` | `stamp` |
| `config reset [--expect S] --json` | `stamp`. Deja la copia en `theme.conf.user.prev` |
| `config restore [--expect S] --json` | `stamp` |
| `wallpaper set ARCHIVO [--expect S] --json` | `background`, `width`, `height`, `kind`, `bytes`, `stamp` |
| `wallpaper clear [--expect S] --json` | `stamp` |
| `wallpaper info --json` | `background`; si hay imagen, además `file`, `width`, `height`, `kind`, `bytes` |
| `preview [--scenario S] [--size AxH] [--out PNG] --json` | `png`, `scenario`, `size` y `stamp` (de la configuración con la que se generó) |
| `install --status --json` | `launcher`, `installed`, `release`, `foreign` |
| `install --user --json` | `version`, `release`, `launcher`, `previous`, `removed` |
| `uninstall --user --json` | `removed`, `kept` (la configuración, que no se borra) |

`try --yes` no tiene JSON: abre una ventana y devuelve el código de salida del greeter.

## Cómo encontrar la CLI

`install --user` copia la CLI, el tema y el arnés a `$XDG_DATA_HOME/sumi-sddm/releases/<versión>-<marca>/` y
deja el lanzador `~/.local/bin/sumi-sddm`, un script y no un enlace. Un cliente busca `sumi-sddm` en el
`PATH` y comprueba que `version --json` responda con `api == 1`. Si no la encuentra, la función no está
disponible; nada más depende de ella.

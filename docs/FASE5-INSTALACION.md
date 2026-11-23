# Sumi SDDM — Fase 5: instalación segura (informe)

Plan aprobado: [FASE5-PLAN.md](FASE5-PLAN.md). Este informe crece por partes.

## Parte A — helper, acción de polkit, paquete y CLI (2026-11-22)

Sólo en el repositorio y sin privilegios. No se ha escrito en `/usr`, `/etc` ni `/var`, ni se ha ejecutado
`pkexec` ni `sudo`. El paquete se construyó con `makepkg` sin instalarlo.

| Pieza | Archivo |
|---|---|
| Helper (Python, `#!/usr/bin/python3 -IB`) | `system/sumi-sddm-helper` |
| Acción de polkit `org.sumi.sddm.helper` | `system/org.sumi.sddm.helper.policy` |
| Prueba con el greeter real, compartida por el helper y la CLI | `tools/sumiconf/probe.py` |
| Cabecera común de `theme.conf.user` aplicado | `tools/sumiconf/ini.py` (`APPLIED_HEADER`) |
| Paquete | `packaging/arch/PKGBUILD`, `packaging/arch/sumi-sddm.install` |
| CLI | `tools/sumi-sddm system status \| probe \| apply \| reset \| rollback \| activate \| deactivate [TEMA]` |
| Recuperación | `docs/RECUPERACION.md`, que también se instala en `/usr/share/doc/sumi-sddm/` |
| Pruebas | `tests/py/test_helper.py` |

### Cómo cumple el plan

- **Verbos y argumentos.** Verbos fijos. El único argumento es el nombre de un tema instalado
  (`deactivate TEMA`), comprobado con `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$` y con su `metadata.desktop`. Nada más.
- **Entrada de `apply`.** Llega por stdin:
  - formato 1 = cabecera JSON de hasta 4 KiB, con claves exactas; configuración de hasta 64 KiB e imagen de hasta
    40 MiB;
  - se rechazan los datos de más, los truncados y lo que no sea UTF-8;
  - se valida con la lectura estricta y se escribe el texto **normalizado**, no el recibido;
  - la imagen se comprueba por contenido desde un temporal 0600 propio;
  - `background` tiene que corresponderse con la imagen enviada.
- **Escrituras.**
  - Sólo `theme.conf.user`, `backgrounds/user.<ext>`, la clave `Current` de `[Theme]` en `/etc/sddm.conf` y
    `/var/lib/sumi-sddm` (0700: `state.json`, `log`, `lock`, `backups/`, `work/`).
  - Atómicas, sin seguir enlaces, y verificadas por hash después.
  - Se rechaza un destino que sea un enlace, un directorio del tema escribible por grupo u otros, o un dueño que no
    sea root.
- **Prueba previa con el greeter real.** Copia del tema en `/run` (0755) con los archivos nuevos, y
  `sddm-greeter-qt6 --test-mode` offscreen, como `sddm` mediante `setpriv --no-new-privs` y con el entorno vacío.
  Exige `sumi-sddm: ready`, un `custom=N` igual al que predice la lectura tolerante y ningún error QML. Si falla,
  no se escribe nada (`code: "probe"`, con `problems`).
- **`/etc/sddm.conf`.**
  - Cambia sólo el valor de cada `Current` de `[Theme]`. Conserva comentarios, orden, finales de línea CRLF, modo
    y dueño. Si no hay `[Theme]`, la añade. Es idempotente.
  - Comprueba después que el tema efectivo es el esperado, con el orden real de SDDM; si no, repone el archivo.
  - `deactivate` repone el archivo **byte a byte** si nadie lo tocó después. Si lo editaste, sólo devuelve
    `Current` a su valor y conserva tus cambios.
- **Respaldo y vuelta atrás.** Respaldo antes de cada cambio; se conservan 8. `rollback` deshace el último cambio,
  y el siguiente deshace el anterior.
- **Su propio código.** Como root, el helper se niega a correr si él o lo que importa no es de root o es
  escribible por otros, o si no está en `/usr/lib/sumi-sddm`. Las variables de prueba (`SUMI_SDDM_HELPER_ROOT` y
  `SUMI_SDDM_HELPER_PROBE`) son un error si se corre como root.
- **Registro.** Fecha, quién (`pkexec:<uid>` o `root`), verbo y resultado. Ningún valor de configuración, y hay
  una prueba que lo comprueba.
- **No toca** PAM ni la autenticación, y no reinicia SDDM.
- **polkit:** `allow_active=auth_admin` (contraseña de administrador cada vez); `allow_any` y `allow_inactive` en
  `no`; `exec.path` = el helper.

### Pruebas

| Prueba | Resultado |
|---|---|
| `test_helper.py` (21, sin root):<br>• raíz falsa; 15 entradas inválidas que no escriben nada<br>• prueba previa fallida que no escribe ni activa<br>• enlaces en `theme.conf.user`, `backgrounds/` y `/etc/sddm.conf` rechazados<br>• tema escribible por el grupo rechazado; tema ausente; bloqueo ocupado<br>• reset y cadena de rollback; rotación de respaldos<br>• activar/desactivar: reposición exacta, sin `[Theme]`, CRLF con `Current` repetido, edición posterior conservada, tema con nombre y nombres inválidos<br>• registro sin valores<br>• `system` de la CLI con un pkexec falso (apply → `inSync`, un cambio posterior lo deshace, activate/deactivate, autenticación cancelada → `denied`) | 21/21 |
| Prueba previa con el **greeter real** sobre la copia preparada (sin root) | `custom=3`, lo esperado |
| `makepkg` en un directorio temporal | construido; ejecuta `gen --check` y `test_helper.py` en `check()` |
| Contenido del paquete | todo `root:root`, el helper 0755 y el resto 0644; nada fuera de las cinco rutas del paquete (tema, `/usr/lib/sumi-sddm`, acción de polkit, licencia y doc) |
| El helper **del paquete extraído**, sin root y con raíz falsa: `status`, y `apply` con el greeter real | funciona con su estructura instalada (`custom=2`) y no deja `__pycache__` |
| `tools/sumi-sddm check` | gen, lint, Python 69, QML 51 + 51 y 4 smokes: OK |

Paquete: `build/sumi-sddm-0.4.0-1-any.pkg.tar.zst`, SHA-256
`12498124169cb3692e911b4d7b7bab5cf356e0a5491f23a673e3b0f88c27cb6b`.

### Lo que sólo se puede probar como root (pasos de la parte B)

Todavía no se ha ejecutado:
- la comprobación de su propio código;
- `chown` del directorio de ejecución y de los archivos;
- la copia en `/run`;
- `setpriv` hacia `sddm`;
- leer el journal como root.

El primer paso privilegiado propuesto es `system probe`. Sólo crea temporales en `/run` y `/tmp` y su estado en
`/var/lib/sumi-sddm`, y no cambia nada que vea el greeter: ejercita esas partes antes de cualquier escritura.

`namcap` no está instalado: el paquete no se ha revisado con él.

## Parte B — pasos en el sistema

### B2: paquete instalado por el autor (2026-11-22)

`sudo pacman -U build/sumi-sddm-0.4.0-1-any.pkg.tar.zst`.

| Comprobación | Resultado |
|---|---|
| `pacman -Qkk sumi-sddm` | 53 archivos, 0 alterados |
| Helper, tema y acción | de `root:root` |
| `pkaction --action-id org.sumi.sddm.helper` | `implicit active: auth_admin`; `any`/`inactive`: `no`; `exec.path` = el helper |
| Tema activo | sigue siendo `orbital` (`/etc/sddm.conf`) |

`sumi-sddm system probe` falló al principio porque `~/.local/bin/sumi-sddm` era anterior a la orden `system`. Se
reinstaló la copia de usuario (`install --user`).

### B3: `system probe` como root (2026-11-22)

Con el diálogo de polkit de la shell:
- **Resultado:** la prueba previa pasa (`custom=0`, sin problemas).
- **Primera ejecución de las partes que sólo funcionan como root:** comprobación de su propio código, `chown` del
  directorio de ejecución, copia en `/run`, `setpriv --no-new-privs` hacia `sddm` y lectura del journal.
- **Sin restos:** ni `/run/sumi-sddm-stage-*` ni `/tmp/sumi-sddm-probe-run-*`.
- **Estado:** `/var/lib/sumi-sddm` queda root 0700.
- **Nada visible ha cambiado:** el tema no tiene archivos de usuario, `/etc/sddm.conf` no cambió y el paquete
  sigue intacto.
- **Registro:** el journal anota el `pkexec` con el comando exacto.

### B4: tu configuración en el tema instalado (2026-11-22)

- **20:34:59, el autor:** `system apply`, con 8 claves y el wallpaper (1920×859 JPEG). Queda `inSync`.
- **Fuente mal nombrada.** La revisión encontró `fontFamily="Maple Mono"`, mientras que la familia instalada en
  `/usr/share/fonts` es `Maple Mono NF`. `fc-match "Maple Mono"` daba `Noto Sans Mono`, y el aviso de
  `config show` ya lo señalaba.
- **20:37, corregido con su permiso:** `config set "fontFamily=Maple Mono NF"` con `--expect`, y `system apply`
  de nuevo.
  - La prueba previa como `sddm` pasa con `custom=7`, lo esperado: `uiScale=1` es el valor por defecto y no
    cuenta.
  - Respaldo `20261122-203737-apply-*`.
  - Los archivos son `root:root 0644` y el estado queda `inSync`.
- **Tema activo:** sigue `orbital`. La activación es un paso aparte.

### B5: activación (2026-11-22, por orden expresa del autor)

`sumi-sddm system activate`, con el diálogo de polkit:
- **Prueba previa** como `sddm`: pasa con `custom=7`.
- **Respaldo:** `20261122-204501-activate-*`.
- **Cambio en `/etc/sddm.conf`:** el `diff` es sólo `Current=orbital` → `Current=sumi`, y el archivo sigue siendo
  `root:root 0644`.
- **Estado:** `system status` da `activeTheme: sumi` (decidido por `/etc/sddm.conf`), `active` e `inSync`.
- **Sin reinicios:** ni SDDM (activo desde las 09:56) ni la shell (PID 1416, `NRestarts=0`). Se verá en la
  próxima pantalla de inicio.
- **Pendiente:** comprobar el inicio de sesión real (B6, autor).

## Mejoras posteriores (2026-11-22)

- **Sugerencia en el aviso de fuente.** El aviso de `fontFamily` sugiere la familia instalada más parecida:
  «“Maple Mono” is not installed … did you mean “Maple Mono NF”?». La sugerencia va también en el campo
  `suggestion`.
- **Avatar.** `sumi-sddm avatar info | set ARCHIVO | clear`, por **AccountsService**:
  - **Por qué AccountsService.** SDDM busca `~/.face.icon` → `/var/lib/AccountsService/icons/<usuario>` →
    `FacesDir`. El primero no sirve con el `$HOME` en `drwx--x---`. AccountsService deja a cada usuario cambiar SU
    avatar (`change-own-user-data`: sí, sin contraseña) y guarda una copia que `sddm` puede leer. No amplía el
    helper de root.
  - **La imagen.** Se valida por contenido (lado mínimo 64) y se recorta a un PNG cuadrado de 512 px con Qt
    offscreen, para quedar bajo el límite de 1 MiB de AccountsService.
  - **Vista previa.** Enseña el avatar real si la pantalla de inicio podrá leerlo (`--meicon` del arnés).
  - **Pruebas.** 3 casos con un AccountsService falso. **Tu avatar real no se ha cambiado.**
- **Arreglo del tema: avatar circular con el renderizador software.** Antes, `clip` de un `Rectangle` sólo
  recortaba al rectángulo, así que una foto salía cuadrada y tapaba el anillo. Las fotos reales no se habían
  probado: sólo las iniciales. Ahora un `Canvas` dibuja la imagen como «cover» dentro de un círculo. Con OpenGL
  ya estaba bien (MultiEffect).
  - **Prueba** `tests/qml/tst_avatar.qml` en los dos renderizadores: pasa con el arreglo y falla en software con
    el código anterior.
  - **Versión.** Sube a **0.4.1**: el tema instalado (0.4.0) aún no lleva el arreglo y hay que reinstalar el
    paquete.

## Parte C — Settings → Login screen: aplicar, usar, restaurar y avatar (entregada)

Pedida por el autor el 2026-11-22. Fuentes en `integration/sumi-shell/`. Trabajo privado en
`~/Projects/Quickshell/.sddm-settings-c-20261122/`.

- **Bases tomadas justo antes.** Las 10 rutas de la Fase 4 en el vivo y en la fuente son **idénticas** al
  candidato que se entregó entonces, así que el candidato nuevo se construye desde los archivos de **antes** de
  cualquier integración (`origin/`) con el `edit.py` completo. No hay parches encadenados.
- **Rutas que cambian:** sólo 3 (`surfaces/Settings.qml`, `services/SddmTheme.qml`, `components/SddmField.qml`).
  `deliver.py --work` deja fuera del manifiesto las que no cambian.

**Lo que añade:**
- **Overview.**
  - «On the login screen» dice *Not installed / Installed, not in use / In use* y, en el pie, si lo aplicado
    coincide con lo guardado.
  - Tres acciones nuevas:

    | Acción | Orden | Pulsaciones |
    |---|---|---|
    | «Apply to the login screen» | `system apply` | una |
    | «Use as the login screen» | `system activate` | dos |
    | «Restore the previous login screen» | `system deactivate` | dos |

  - Las tres pasan por pkexec, en un proceso aparte, para que esperar la contraseña no bloquee los demás cambios.
  - Mientras tanto, todas dicen «Waiting for your password…».
  - Cancelar → «Authentication cancelled · nothing changed». Prueba previa fallida → el error y su primer problema.
- **Users.** Primera fila «Avatar»: el `PathField` redondo de Settings (como el del Lock), «Remove», marca de
  personalizado y restablecer. Por `sumi-sddm avatar set|clear`, sin contraseña.

**Pruebas:**

| Prueba | Resultado |
|---|---|
| `deliver.py --work … prepare / check / self-test / apply` en seco | 3 rutas × 2 árboles en base; entrega y vuelta atrás correctas; la entrega de la Fase 4 sigue intacta |
| Banco `real`: los 48 pasos de antes, más estado del sistema, Apply (`inSync` cambia), Use con dos pulsaciones (`In use`), Restore (vuelve a `orbital`), avatar puesto y quitado | 78/78, 0 avisos QML |
| ↳ El sistema es falso | raíz privada con el tema «instalado», pkexec falso que ejecuta el helper del repositorio sobre ella, greeter falso y AccountsService falso. El `/etc/sddm.conf` falso termina en `Current=orbital` |
| `missing` / `incompatible` / `terminal` | 12/12, 12/12, 20/20 |
| Recarga en caliente desde el estado actual de la sesión (Fase 4) → 3 rutas | 2 cargas, 78/78, 0 avisos |
| Lo que se entregaría frente a lo probado | idéntico byte a byte |

**Límites:**
- **Miniatura del avatar.** En el banco no se ve, porque `PathField` usa MultiEffect y el banco usa el
  renderizador software. En la sesión sí se dibuja, como la del Lock.
- **Contraseña.** El diálogo real de polkit desde Settings sólo se verá en la sesión: en el banco, pkexec es falso.

### Entrega y avatar (2026-11-22, autorizados)

- **`deliver.py --work … apply --apply`**, con la sesión desbloqueada:
  - 3 rutas en fuente y vivo, de base a candidato, en las 6 entradas;
  - recarga validada al primer intento: 2 «Configuration Loaded» y 0 avisos en el registro de la recarga;
  - mismo PID (1416), `NRestarts=0` y `settings.json` con el mismo SHA-256;
  - los avisos `qt.qpa.wayland.textinput` del journal son de las 21:00 y 21:04, anteriores a la entrega (21:06):
    son de Qt al escribir en un campo.
- **Respaldo y vuelta atrás.** El respaldo está en
  `~/.local/state/sumi-sddm-sddm-settings-c-20261122-xabuso1o/backup`. Para deshacer:

  ```sh
  python3 integration/sumi-shell/deliver.py --work ~/Projects/Quickshell/.sddm-settings-c-20261122 rollback --bundle <respaldo> --apply
  ```

- **Avatar.** `sumi-sddm avatar set ~/Downloads/keiko.png`, la imagen que ya usa el Lock de Sumi Shell (PNG
  1254×1254):
  - AccountsService guarda `/var/lib/AccountsService/icons/kitasa-elburakku` (PNG 512×512, `root 0644`), legible
    por `sddm`; `sddmUses` apunta a ese archivo;
  - la vista previa lo enseña recortado en círculo.
- **Pendiente del autor:** ver la página en la sesión (miniatura del avatar y diálogo de contraseña) y el primer
  inicio de sesión real con Sumi.

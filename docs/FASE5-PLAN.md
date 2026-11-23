# Sumi SDDM — Fase 5: plan de instalación segura (helper con pkexec, respaldos y vuelta atrás)

Fecha: 2026-11-22. **Aprobado** el 2026-11-22 con las cuatro recomendaciones de §6: paquete de Arch, `auth_admin`
cada vez, configuración por la entrada estándar y `pacman -U` lo ejecutas tú. Parte A hecha
([informe](FASE5-INSTALACION.md)). Cada paso de la parte B sigue necesitando su autorización.

## 0. Lo que hay (sólo lectura)

- **SDDM y polkit.** SDDM 0.21.0-8 (`sddm.service` activo y habilitado) y polkit 128 (`polkitd`, backend JS).
  `/usr/bin/pkexec` es setuid root.
- **Agente de autenticación.** Es **Sumi Shell** (`shell.integrations.polkitAgent = true`): el diálogo de `pkexec`
  saldrá en la shell.
- **Orden de lectura de SDDM.** Lee `/usr/lib/sddm/sddm.conf.d/default.conf` → `/etc/sddm.conf.d/theme.conf`
  (`Current=orbital`) → **`/etc/sddm.conf`** (`Current=orbital`), y el último gana.
  - Ningún paquete es dueño de `/etc/sddm.conf` ni de `/etc/sddm.conf.d/theme.conf`.
  - `orbital` está instalado a mano en `/usr/share/sddm/themes/orbital`.
- **Usuario `sddm`.** Es uid 960, con home `/var/lib/sddm` (`drwxr-x---`). No puede leer tu `$HOME`
  (`drwx--x---`): el wallpaper tiene que estar **dentro del tema instalado** (R3 de la Fase 1).
- **Cómo lee el greeter la configuración.** Lee `theme.conf` y después `theme.conf.user` **del directorio del
  tema** (verificado con el greeter real en la Fase 3). La configuración del usuario sólo puede vivir ahí.
- **Herramientas.** `runuser` y `setpriv` están, así que se puede probar el tema **como el usuario `sddm`**.
  `makepkg` también está.

## 1. Principios

1. **Pasos separados, y ninguno reinicia SDDM.** Instalar el tema, aplicar tu configuración y **activarlo** son
   tres pasos distintos. Activar sólo cambia qué tema se verá **la próxima vez** que aparezca la pantalla de inicio
   de sesión.
2. **El código que corre como root es inmutable para tu usuario.** El helper y su copia de `sumiconf` están en
   `/usr/lib/sumi-sddm/`, con dueño root y modo 0755/0644. Nunca se ejecuta como root nada de tu `$HOME` ni del
   checkout.
3. **El helper no abre archivos tuyos.** La configuración y el wallpaper le llegan **por la entrada estándar**:
   un paquete con límites de tamaño, preparado por la CLI sin privilegios. Así el root no recorre tu `$HOME` y
   desaparecen los enlaces simbólicos y las carreras entre comprobar y abrir (R5).
4. **Verbos fijos, sin rutas ni órdenes en `argv`.** El helper revalida todo con la lectura estricta (el mismo
   `sumiconf`) y comprueba las imágenes por contenido.
5. **Escribe en cuatro sitios y en ninguno más:**
   - `/usr/share/sddm/themes/sumi/theme.conf.user`
   - `/usr/share/sddm/themes/sumi/backgrounds/user.<ext>`
   - la clave `[Theme] Current` de `/etc/sddm.conf`
   - su estado y sus respaldos en `/var/lib/sumi-sddm/` (0700)

   Nada más: ni PAM, ni la autenticación, ni otros archivos de SDDM, ni permisos del directorio del tema (sigue
   siendo root 0755).
6. **Antes de tocar lo que verá el greeter, se prueba como lo verá.** Copia preparada del tema con los archivos
   nuevos y `sddm-greeter-qt6 --test-mode` offscreen **como el usuario `sddm`**. Si no registra
   `sumi-sddm: ready` con el número de claves esperado y sin errores QML, no se escribe nada.
7. **Respaldo antes de cada escritura y vuelta atrás.** Todo se escribe atómicamente: temporal + `fsync` +
   `rename`, sin seguir enlaces. Se rechaza si un destino es un enlace o no es de root.
8. **El registro dice qué verbo, cuándo y con qué resultado.** Nunca valores de configuración ni nada sensible
   (en el login no hay contraseñas que registrar, y el helper no las ve).

## 2. Parte A — en el repositorio (sin privilegios)

| # | Qué | Archivos |
|---|---|---|
| A1 | Helper `sumi-sddm-helper` (Python, `#!/usr/bin/python3 -IB`) | `system/sumi-sddm-helper` |
| A2 | Acción de polkit `org.sumi.sddm.helper` (`exec.path` = el helper, `auth_admin`) | `system/org.sumi.sddm.helper.policy` |
| A3 | Paquete de Arch con fuentes locales: el tema en `/usr/share/sddm/themes/sumi`, el helper y `sumiconf` en `/usr/lib/sumi-sddm`, la acción en `/usr/share/polkit-1/actions`. **No activa nada.** `check()` ejecuta las pruebas | `packaging/arch/PKGBUILD`, `sumi-sddm.install` |
| A4 | CLI: `sumi-sddm system status \| apply \| reset \| rollback \| activate \| deactivate`, todas con `--json`. Preparan el paquete de entrada y llaman a `pkexec /usr/lib/sumi-sddm/sumi-sddm-helper <verbo>`. `status` no necesita root | `tools/sumi-sddm` |
| A5 | Pruebas sin root (ver §4) | `tests/py/test_helper.py` |
| A6 | Guía de recuperación desde una TTY | `docs/RECUPERACION.md` |

**Verbos del helper:**

| Verbo | Qué hace |
|---|---|
| `apply` | Lee el paquete de la entrada estándar (≤ 41 MiB: `theme.conf.user` ≤ 64 KiB y la imagen opcional). Valida, prepara una copia, la prueba como `sddm`, respalda y escribe `theme.conf.user` y `backgrounds/user.<ext>`, borrando las copias `user.*` viejas |
| `reset` | Respalda y quita `theme.conf.user` y `backgrounds/user.*` |
| `rollback` | Repone el último respaldo, con la misma prueba previa |
| `activate` | Exige el tema instalado y la prueba como `sddm` superada. Respalda `/etc/sddm.conf`, guarda el tema anterior (`orbital`) y cambia **sólo** el valor de `Current` en `[Theme]`. Conserva comentarios, orden, modo y dueño; crea `[Theme]` si no existe. Es idempotente |
| `deactivate` | Repone el tema anterior guardado (o quita la clave si antes no estaba) |
| `status` | Lectura: tema activo, instalado, versión, archivos del usuario aplicados, últimos respaldos |

- **Quién puede llamarlo.** Por `pkexec` (`PKEXEC_UID`) o como root directo. Lo segundo es para recuperar desde una
  TTY: `sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate`.
- **Gancho de pruebas.** El gancho que redirige las rutas a una raíz falsa **sólo funciona sin root**: como root
  se rechaza.

## 3. Parte B — en el sistema (cada paso, con tu autorización)

| Paso | Qué | Quién | Efecto en el inicio de sesión |
|---|---|---|---|
| B1 | Construir el paquete (`makepkg` en un directorio temporal, sin instalar) y revisar su contenido | yo | ninguno |
| B2 | Instalar el paquete (`pacman -U`) | tú (pide tu contraseña de sudo), o yo con `pkexec` si lo prefieres | ninguno: el tema se instala, pero sigue activo `orbital` |
| B3 | Prueba del tema **instalado** como `sddm` (sin root, con `runuser` vía el helper `status --probe`) | yo | ninguno |
| B4 | `sumi-sddm system apply`: tu configuración y tu wallpaper dentro del tema | yo, con el diálogo de polkit en la shell | ninguno: `orbital` sigue activo |
| B5 | **Activar**: `sumi-sddm system activate` | sólo con tu orden expresa para ese paso | la **próxima** pantalla de inicio será Sumi |
| B6 | Comprobar en el inicio de sesión real (cerrar sesión o reiniciar, cuando tú quieras) | tú | — |

**Recuperación** (también en `docs/RECUPERACION.md`), si la pantalla de inicio de Sumi fallara:
1. Ctrl+Alt+F3, inicia sesión en la TTY y ejecuta `sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate`.
   Repone `orbital`.
2. O bien edita `Current=orbital` en `/etc/sddm.conf`.
3. Si el QML de Sumi ni siquiera carga, SDDM pasa solo a su tema interno y aun así se puede iniciar sesión.

## 4. Pruebas (antes de cualquier paso de la parte B)

- **Helper con raíz falsa, sin root:**
  - formato y límites del paquete de entrada; lectura estricta; imágenes falsas o enormes;
  - destino enlace, destino de otro dueño, directorio del tema ausente;
  - escritura atómica, respaldos y su rotación;
  - `rollback`;
  - `activate`/`deactivate` sobre copias de varios `sddm.conf`: sin `[Theme]`, con comentarios, con `Current`
    repetido, idempotencia, reposición exacta byte a byte;
  - que una prueba previa fallida (greeter falso) no escribe nada;
  - verbos y argumentos desconocidos.
- **CLI `system`** con un `pkexec` falso, para probar la conversación y los códigos de error.
- **Paquete:** `makepkg` en un temporal, lista de archivos, permisos y que no haya nada fuera de las cuatro rutas.
  `namcap` si está instalado.
- **Lo de siempre:** `tools/sumi-sddm check` (tema, configuración, greeter real en `--test-mode`).

## 5. Parte C — Settings (después, con su propio plan)

En Settings → Login screen:
- **«Apply to login screen»:** el estado «Not installed yet» pasa a decir si lo aplicado coincide con lo guardado.
- **«Use as login screen» / «Restore previous»:** con doble pulsación.
- **Cómo funciona:** las tres usan `sumi-sddm system …`. Modifica Quickshell, así que llevará su propio plan y
  autorización, como en la Fase 4.

## 6. Decisiones que te tocan

1. **Cómo llegan el tema y el helper al sistema:**
   - **un paquete de Arch construido desde el repositorio** (recomendado: pacman sabe qué archivos son suyos,
     desinstalar es `pacman -R`, y el helper queda con dueño root), o
   - un instalador propio que copia con `pkexec` desde el checkout.
2. **Cuántas veces pide contraseña polkit:**
   - **cada vez** (`auth_admin`, recomendado), o
   - una vez cada 5 minutos (`auth_admin_keep`).
3. **Cómo recibe el helper tu configuración:**
   - **por la entrada estándar** (recomendado: el root no abre nada de tu `$HOME`), o
   - el helper la lee de `~/.config/sumi-sddm`.
4. **Quién instala el paquete (B2):**
   - **tú, con `sudo pacman -U`** (recomendado: tú ves el comando y la contraseña), o
   - yo, mediante `pkexec` con el diálogo de la shell.

# Sumi SDDM — Fase 6: pruebas finales (informe)

Plan aprobado: [FASE6-PLAN.md](FASE6-PLAN.md). El autor pidió no hacer, por ahora, nada que necesite su presencia o
un reinicio. Lo hecho hasta aquí no lo necesita.

## Parte A — automático (2026-11-22)

| # | Hecho | Resultado |
|---|---|---|
| A1 | `sumi-sddm system log [--boot N] [--json]` (`tools/sumiconf/greeterlog.py`). Lee del journal sólo los greeters del usuario `sddm` (las ventanas `--test-mode` no cuentan) y los juzga con `probe.judge`. Resume inicios correctos y fallidos, mensajes del daemon, peticiones del greeter y la sesión elegida, sin nombres de usuario | Arranque actual: Sumi OK, `custom=7`, 1 inicio correcto, `hyprland.desktop`. Arranque anterior: sólo `orbital`. 5 pruebas con registros sintéticos |
| A2 | Varios monitores con el **greeter real**: `smoke --screens N`, con pantallas offscreen por un archivo de configuración de la plataforma. Exige N `ready` y exactamente una `primary=true`. Va en `check` con 2 pantallas | 2 pantallas (software) y 3 (OpenGL): una vista por pantalla, una sola principal, 0 avisos |
| A3 | **Accesibilidad**: prueba que recorre el Greeter en cinco estados (compacta, expandida, sesiones, confirmación, manual). Todo control que toma foco con Tab debe tener rol y nombre. Además, Tab cicla y Mayús+Tab invierte | Encontró dos fallos reales, ya corregidos (abajo); 57 + 57 QML |
| A4 | Regresión: `check` completo, banco de Settings (4 escenarios y recarga en caliente) y `makepkg` | `check`: Python 78, QML 57 + 57, 5 smokes OK. Banco: 78 + 12 + 12 + 20 y recarga en caliente con 2 cargas |

### Lo que encontró A3, ya corregido en el tema

- **El selector de usuarios** toma el foco con Tab, pero no tenía rol ni nombre para un lector de pantalla. Ahora es
  `Accessible.List`, con nombre «Users» y una descripción de cómo moverse (← →). Cada ficha sigue siendo un
  `RadioButton` con su nombre.
- **El campo de contraseña.** En Qt 6.12, `Accessible.passwordEdit: true` hace que el nombre se lea **siempre
  vacío**, aunque se declare; se comprobó aislado. La etiqueta llega ahora por `Accessible.description` y por
  `Accessible.labelledBy` con su texto de marcador («Password»).
- **Regresión visual frente al último commit,** en 7 estados, con OpenGL y el reloj enmascarado:
  - un solo píxel del suavizado de un nombre cambia 1/255 (238 → 237), imperceptible;
  - lo demás es el reloj, que cambia de minuto, y el spinner del estado de error, que también varía entre dos
    capturas de la misma versión.
- **Versión 0.4.2.** Paquete construido en `build/sumi-sddm-0.4.2-1-any.pkg.tar.zst`, SHA-256
  `f9abac6f4e22cd43b4e0a6b01d23786476be3ae16be8fef3d18e851a6f0f943a`. Contiene sólo las rutas previstas. **No
  instalado**: lo instala el autor.

## Parte C

- **C1 (hecho).** En Quickshell, `tools/settings-navigation/checks.js`: 31 → 32 páginas. El banco
  (`review.py` sobre una copia del árbol vivo) pasa con 227 comprobaciones y 0 avisos, incluida la ruta de
  `shell/sddm`. **Sin commit** en Quickshell.
- **C2 (pendiente del autor).** `sudo pacman -S namcap`, y después revisaré el paquete.
- **C3 (decidido).** MIT, que se añadirá al publicar Sumi Shell y Sumi SDDM.

## Parte B — en real, con el autor

### C2: namcap (2026-11-22)

- **Paquete:** el error de licencia se corrigió.
  - `LicenseRef-pending` ahora va con `/usr/share/licenses/sumi-sddm/LICENSE-PENDING`, una nota hasta que se
    publique con MIT.
  - El paquete pasa a `0.4.2-2` y sólo añade esa nota.
- **Avisos que quedan, falsos positivos:**
  - los módulos `sumiconf.*` son privados del paquete (`/usr/lib/sumi-sddm/tools`) y el helper los carga él mismo;
  - `sddm`, `polkit`, `util-linux` y `systemd` se usan en ejecución (el tema, la acción, `setpriv`, `journalctl`).
- **PKGBUILD:** `pkgver` ya no se calcula con `tr` (namcap no lo tiene). Es literal, y
  `tests/py/test_packaging.py` exige que coincida con `VERSION`.
- **Avisos del PKGBUILD para cuando se publique:** «File referenced in $startdir» (es local a propósito),
  «Missing url» y «Missing Maintainer tag».

### B5: Settings en la sesión (2026-11-22, 21:46)

- **Lo que vio el autor:** «In use» y «Shows your current settings»; la miniatura redonda del avatar se ve; un
  cambio deja «Apply» disponible; «Apply» → diálogo de polkit de la shell → aplicado; Environment muestra
  «Login screen theme».
- **Comprobado:**
  - el journal registra `pkexec … sumi-sddm-helper apply` a las 21:46:50, desde la shell (CWD `~`);
  - `system status` da `inSync` y `active`;
  - la shell no registró avisos nuevos.

### B1 + B2 + B3: teclado, sesiones y contraseña incorrecta (2026-11-22, arranque de las 21:51)

- **Lo que vio el autor:** todo bien (escribir sin clic, Esc, Tab y Mayús+Tab, ← →, la lista de sesiones con
  Esc sin cambiar, el aviso de Bloq Mayús, el error con la contraseña incorrecta y después la correcta).
- **`system log`:** Sumi OK (`custom=7`, 0 avisos); **2 inicios fallidos y 1 correcto**; sesión
  `hyprland.desktop` en los tres (Esc en la lista no la cambió).
- **Corregido en `system log`, encontrado en esta prueba:**
  - SDDM 0.21 envía `LoginFailed` **dos veces** por intento fallido, y el primer resumen contaba 4;
  - los mensajes de información los escribe como «Information Message received…», con otro formato.
  - Ahora los intentos se cuentan con las líneas «Authentication … successful/failed» del daemon (una por
    intento, sin guardar nombres), con una prueba sintética que reproduce el registro real.
- **Usuario vacío en los fallos.** El daemon escribe `Authentication for user "" failed`: en un fallo, el helper
  de SDDM no informa del usuario. El tema envía siempre el usuario seleccionado, y el intento correcto, con el
  mismo código, salió con el nombre.

### B4: energía desde la notch (2026-11-22)

- **Lo que vio el autor:** «Restart» y «Shut down» piden confirmación; Cancelar/Esc vuelve sin hacer nada;
  confirmar «Restart» reinicia.
- **`system log --boot -1`** (arranque de 21:57:32 a 21:58:34):
  - Sumi OK, `custom=7`;
  - peticiones del greeter: sólo `Connect` y `Reboot`×1. Las cancelaciones no enviaron nada, y no hubo ningún
    `PowerOff`.
- **El daemon:** a las 21:58:32 recibe `Reboot` → systemd detiene SDDM → reinicio.
- **Arranque siguiente** (21:58:57): Sumi OK, `custom=7`, 1 inicio de sesión correcto en `hyprland.desktop`.

## Cierre de la Fase 6

Todo lo que el autor podía comprobar en real está comprobado:
- el greeter con el tema y la configuración;
- inicio de sesión correcto e incorrecto, Bloq Mayús;
- teclado;
- sesiones;
- reiniciar, y apagar hasta la confirmación;
- avatar;
- Settings en la sesión con «Apply» y polkit.

Automatizado: `check` (Python 80, QML 57 + 57, 5 smokes con el greeter real, uno con dos pantallas), el banco de
Settings (78 + 12 + 12 + 20 y recarga en caliente) y el banco de navegación de Quickshell (227).

Queda fuera, como límite declarado:

| Límite | Por qué |
|---|---|
| Varios monitores **físicos** | Sólo hay un monitor. Probado con el greeter real y pantallas offscreen |
| Lector de pantalla real | No se ha probado con uno. Sí se comprueban roles y etiquetas en cinco estados |
| Apagar de verdad | Sólo hasta la confirmación; el reinicio sí se confirmó |
| Publicación | Licencia MIT, `url` y `Maintainer` del PKGBUILD y fuente no local: cuando el autor publique |

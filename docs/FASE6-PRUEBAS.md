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

## Pendiente (con el autor presente)

- **Instalar 0.4.2:** `sudo pacman -U build/sumi-sddm-0.4.2-1-any.pkg.tar.zst`.
- **B1:** contraseña incorrecta y Bloq Mayús.
- **B2:** sólo teclado.
- **B3:** sesión desde la notch.
- **B5:** Settings en la sesión.
- **B4:** energía; reinicia el equipo.
- **Después de cada una:** compruebo con `sumi-sddm system log`.

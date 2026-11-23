# Sumi SDDM — Fase 6: plan de pruebas finales

Fecha: 2026-11-22. **Aprobado** el 2026-11-22: parte A, B1 a B5, C1 y C2. La licencia será **MIT**, y se
añadirá cuando se publiquen Sumi Shell y Sumi SDDM. Informe: [FASE6-PRUEBAS.md](FASE6-PRUEBAS.md).

## 0. Dónde estamos

**Ya comprobado en real:** el tema activo en el greeter real (X11, 1920×1080), 0 avisos QML, las 7 claves leídas
(`custom=7`), el avatar de AccountsService, el inicio de sesión con contraseña correcta en la sesión Hyprland y el
aspecto, aprobado por el autor.

**Automatizado hoy:**
- 73 pruebas de Python: configuración, contrato, helper, avatar;
- 55 + 55 de QML, con los renderizadores software y OpenGL;
- 4 smokes con el greeter real en `--test-mode`;
- el banco de Settings: 78 + 12 + 12 + 20 comprobaciones y recarga en caliente.

**Lo que falta, de los informes anteriores:**

| Hueco | De dónde |
|---|---|
| Contraseña incorrecta, Bloq Mayús y mensajes del daemon, en real | Fase 2 (`--test-mode` no autentica) |
| Reiniciar y apagar reales, con su confirmación | Fase 2 |
| Cambio de sesión desde la notch, en real | Fase 2 |
| Varios monitores: sólo simulado dentro del arnés | Fase 2 (un único monitor físico) |
| Accesibilidad: roles y nombres declarados, no verificados | Fase 2 |
| La página de Settings vista en la sesión (miniatura del avatar, diálogo de polkit de «Apply») | Fase 5, parte C |
| El banco de la navegación de Quickshell espera 31 páginas; ahora son 32 | Fase 4 |
| El paquete no se ha revisado con `namcap` | Fase 5 |
| Licencia del proyecto sin decidir | desde la Fase 2 |

## 1. Parte A — automático, sin privilegios (yo)

| # | Qué |
|---|---|
| A1 | `sumi-sddm system log [--boot N] [--json]`, de sólo lectura. Lee el journal del greeter del arranque y lo juzga con `probe.judge` (tema cargado, `ready`, `custom` esperado, avisos QML). Resume, sin datos sensibles, los inicios correctos y fallidos y la sesión elegida. Sirve para comprobar cada prueba real de la parte B en un segundo |
| A2 | **Varios monitores con el greeter real**: smoke con dos pantallas offscreen (archivo de configuración de la plataforma `offscreen`). Debe haber dos `ready`, una `primary=true` y otra `primary=false`, sin avisos. Además, con `multiMonitor=primary`, la secundaria sólo con fondo y reloj |
| A3 | **Accesibilidad estática**: prueba QML que recorre el Greeter en cada estado. Todo control que acepta foco debe tener `Accessible.role` y un `Accessible.name` no vacío. El orden de Tab debe ser el documentado en el README |
| A4 | **Regresión completa**: `check`, helper, avatar, `makepkg` en un temporal, y el banco de Settings con los cuatro escenarios |
| A5 | **Informe final** `docs/FASE6-PRUEBAS.md` y estado del README |

## 2. Parte B — en real, con tu ayuda (una por vez, cuando quieras)

Te doy los pasos y, después de cada una, compruebo el registro con `system log`.

| # | Prueba | Riesgo |
|---|---|---|
| B1 | **Contraseña incorrecta**: escribirla mal → mensaje de error y campo listo para reintentar; con Bloq Mayús activo → aviso; después, la correcta | ninguno: sólo cierras sesión |
| B2 | **Teclado sólo**: escribir sin hacer clic (la notch se expande), Tab por los controles, Esc recoge, ←/→ en usuarios | ninguno |
| B3 | **Sesión desde la notch**: abrir la lista, moverse, Esc sin cambiar; si quieres, elegir «Hyprland (uwsm)» una vez | bajo: SDDM recuerda la última sesión |
| B4 | **Energía**: «Restart» → confirmación → Cancelar (comprobar) → otra vez → Confirmar (reinicia). «Shut down» sólo hasta la confirmación y Cancelar | reinicia el equipo (B4a) |
| B5 | **Settings en tu sesión**: la página Login screen, la miniatura del avatar, un cambio pequeño → «Apply» → diálogo de polkit → «Has your current settings»; deshacer el cambio y volver a aplicar. Environment → «Login screen theme: Available» | ninguno: tu tema sigue activo |

## 3. Parte C — opcional, con su autorización

| # | Qué |
|---|---|
| C1 | Actualizar en Quickshell `tools/settings-navigation/checks.js` (31 → 32 páginas), para que ese banco vuelva a pasar. Modifica el repositorio de Quickshell: sólo con tu permiso |
| C2 | Instalar `namcap` (`sudo pacman -S namcap`, lo haces tú) y revisar el paquete |
| C3 | Decidir la licencia del proyecto (Inter ya va con la OFL) |

## 4. Decisiones que te tocan

1. **¿Apruebas la parte A?** Es sólo del repositorio.
2. **¿Qué pruebas reales quieres hacer?** Recomiendo B1, B2, B3 y B5. B4 sólo si no te importa reiniciar una
   vez.
3. **¿Quieres C1 y C2?** C3 sólo cuando lo tengas claro.

# Integración con Sumi Shell: Settings → Desktop tools → Login screen

> **2026-11-23**: Sumi Shell tiene ahora una **ventana propia** Login screen (`core/LoginLayer`, `services/LoginUi`,
> `surfaces/LoginScreen`, `components/SddmPreviewPane` y `SddmSystemPanel`, en el árbol de la shell; ADR-41 e informe
> `docs/SUMI-LOGIN-UI-2026-11-23.md` del repo de Sumi Shell). Settings → Login screen quedó como resumen con «Open».
> Aquí se mantienen al día `services/SddmTheme.qml` y `components/SddmField.qml` (iguales a la shell). `bench/` se rehízo
> para la página resumen (filas, Open, Apply/Use/Restore y, por el servicio, los caminos de la CLI real); la ventana tiene
> su propio banco en `tools/login-ui/` del repo de Sumi Shell. `edit.py` y `deliver.py` son registro de la entrega del
> 2026-11-22.

Lo que Sumi Shell necesita para configurar Sumi SDDM desde Settings. Se guarda aquí, versionado con el tema, pero
**se ejecuta dentro de la shell**: la shell no importa nada de este repositorio. Sólo lanza la orden `sumi-sddm`
del PATH (contrato JSON en [docs/CLI-JSON.md](../../docs/CLI-JSON.md)), y si no la encuentra la página lo explica.

| Archivo | Qué es |
|---|---|
| `services/SddmTheme.qml` | Singleton. Cola de procesos `sumi-sddm` con verbos fijos y argv, escrituras agrupadas (300 ms) con `--expect`, vista previa (600 ms, una a la vez), `claim()` (sin la página abierta no corre nada) |
| `components/SddmField.qml` | Una clave del esquema → el control de Settings según su tipo (Toggle, Choice, Slider, campo hex/texto/ruta) |
| `components/SddmPreview.qml` | La imagen de `sumi-sddm preview` con selector de escena |
| `edit.py` | Aplica los cambios a una COPIA del árbol de la shell; cada cambio se ancla en un texto que debe aparecer exactamente una vez |
| `deliver.py` | Entrega por rutas a fuente (dotfiles) y vivo, con guarda SHA-256, respaldo, diario y vuelta atrás; sin `--apply` sólo lee |
| `bench/` | Banco offscreen (`qs -p`, HOME/XDG privados, sin compositor ni buses): escenarios `real`, `missing`, `incompatible`, `terminal` y `--reload-from` (recarga en caliente) |

Archivos de Sumi Shell que cambian (10 rutas):
- **Nuevos:** los 3 de arriba.
- **Modificados:** `surfaces/Settings.qml`, `lib/settings-nav.js`, `lib/settings-sections.js` (pestañas de la
  página), `scripts/capabilities.py` (capacidad `login.sddmTheme`), `services/Capabilities.qml` (su etiqueta) y los
  dos `qmldir`.
- **Sin tocar:** `settings.json`, `settings-schema.js`, presets, Export/Import, el IPC público, Lock y PAM.

```sh
P=~/Projects/Quickshell/.sddm-settings-20261122          # copia privada (ignorada por git)
python3 edit.py "$P/candidate"                            # sobre una copia del árbol
python3 bench/review.py "$P/candidate" "$P/bench" --scenario all
python3 bench/review.py "$P/candidate" "$P/hot" --scenario real --reload-from "$P/before" --manifest "$P/manifest.json"
python3 deliver.py prepare && python3 deliver.py check && python3 deliver.py self-test
python3 deliver.py apply            # en seco; con --apply SÓLO con autorización de esa entrega
```

# Sumi SDDM

Tema de inicio de sesión para SDDM (≥ 0.21, Qt 6): minimalista, con una notch superior como centro de
autenticación. Compatible con Sumi Shell, pero **independiente**: no usa Quickshell, Hyprland ni ningún
servicio de Sumi.

> Estado: Fases 1–6 completas. Instalado (paquete) y activo en esta máquina, probado en real; informe final en
> [docs/FASE6-PRUEBAS.md](docs/FASE6-PRUEBAS.md) y recuperación en [docs/RECUPERACION.md](docs/RECUPERACION.md).

## Estructura

```
schema/config-schema.json  fuente única de la configuración (claves, tipos, rangos, defaults, etiquetas de UI)
theme/sumi/                lo que se instalará en /usr/share/sddm/themes/sumi
  metadata.desktop         QtVersion=6, ConfigFile=theme.conf
  theme.conf               defaults documentados (GENERADO desde el esquema)
  Main.qml                 adaptador: contexto de SDDM → propiedades de Greeter
  components/              Greeter, Style, Notch, NotchShape, Background, Clock, UserStrip, Avatar, controles
    config.js              lectura tolerante (paridad con tools/sumiconf/schema.py)
    schema.js              GENERADO desde el esquema
  assets/fonts/            Inter 4 sin modificar + OFL.txt
VERSION                    versión del proyecto (única fuente)
tools/sumi-sddm            CLI (sin privilegios): config, wallpaper, preview, try, install --user, gen y desarrollo
tools/sumiconf/            esquema, validación estricta/tolerante, INI de QSettings, imágenes, rutas,
                           huella y bloqueo (state.py), instalación de usuario (install.py)
tools/harness/             dobles de SDDM y Render.qml (vista previa y capturas)
system/                    helper privilegiado (pkexec) y su acción de polkit
packaging/arch/            PKGBUILD local (tema + helper + acción); no activa nada
integration/sumi-shell/     Settings → Login screen para Sumi Shell (servicio, controles, edit.py, deliver.py, banco)
tests/py/                  pruebas de sumiconf y de la CLI
tests/qml/                 pruebas del Greeter y de la paridad de configuración (qmltestrunner)
tests/fixtures/            casos compartidos Python/QML y theme.conf.user de prueba
docs/                      auditoría, informes por fase y CONFIG.md (GENERADO)
```

## Configuración (sin privilegios)

La configuración personal vive en `~/.config/sumi-sddm/` (`theme.conf.user` y `backgrounds/`). El tema
instalado no se toca: aplicarla al sistema será trabajo del helper de la Fase 5. Claves: [docs/CONFIG.md](docs/CONFIG.md).

```sh
tools/sumi-sddm config show                       # * = personalizado
tools/sumi-sddm config set clockFormat=12h accentColor=#ffb38a   # valida todo o no escribe nada
tools/sumi-sddm config unset clockFormat
tools/sumi-sddm config edit                       # $EDITOR con todas las claves comentadas; no guarda nada inválido
tools/sumi-sddm wallpaper set ~/Imágenes/fondo.jpg               # valida y copia; clear | info
tools/sumi-sddm avatar set ~/Imágenes/yo.png                     # tu avatar (AccountsService, sin contraseña)
tools/sumi-sddm preview                           # PNG en ~/.cache/sumi-sddm/preview/
tools/sumi-sddm try --yes                         # ventana --test-mode (toma el teclado)
```

### En el sistema (Fase 5)

```sh
cd packaging/arch && makepkg                      # construir el paquete (sin root)
sudo pacman -U sumi-sddm-*.pkg.tar.zst            # instalar: NO activa el tema
tools/sumi-sddm system status                     # instalado, tema activo, ¿tu configuración aplicada?
tools/sumi-sddm system apply                      # lleva tu configuración y wallpaper al tema (pide contraseña)
tools/sumi-sddm system activate                   # Sumi será la pantalla de inicio la PRÓXIMA vez
tools/sumi-sddm system deactivate                 # vuelve al tema anterior
```

Si algo sale mal en la pantalla de inicio: [docs/RECUPERACION.md](docs/RECUPERACION.md).

Todas aceptan `--json`, con un contrato versionado para otros programas (Settings de Sumi Shell):
[docs/CLI-JSON.md](docs/CLI-JSON.md). Las escrituras admiten `--expect HUELLA` para no pisar cambios ajenos.

```sh
tools/sumi-sddm config fonts                      # familias instaladas (~ = sólo en tu $HOME: el greeter no las ve)
tools/sumi-sddm install --user                    # copia a ~/.local/share/sumi-sddm + lanzador ~/.local/bin/sumi-sddm
tools/sumi-sddm uninstall --user                  # quita ambos; conserva ~/.config/sumi-sddm
```

## Desarrollo

```sh
tools/sumi-sddm gen                  # tras editar schema/config-schema.json
tools/sumi-sddm check                # gen --check + lint + pruebas (Python y QML, software y OpenGL) + humo
tools/sumi-sddm render --size all    # capturas de todos los escenarios en tests/out/
```

`smoke` carga el tema en el greeter REAL (`sddm-greeter-qt6 --test-mode`, offscreen) desde una copia en
`~/.cache/sumi-sddm/` y comprueba, por el registro, que su QSettings lee exactamente las claves esperadas.
En `--test-mode` no hay daemon: no se autentica ni se apaga de verdad.

## Teclado

| Dónde | Tecla | Acción |
|---|---|---|
| Notch compacta | cualquier carácter | expande y lo escribe en el campo |
| | Intro / Espacio / ↓ | expande |
| Campo de contraseña | Intro | iniciar sesión |
| | Esc | borra; con el campo vacío, recoge la notch |
| Cualquier sitio | Tab / Mayús+Tab | contraseña → sesión → reiniciar → apagar → usuarios |
| Selector de usuarios | ← / → | cambia de usuario (borra la contraseña escrita) |
| | Intro / Espacio | vuelve al campo |
| | cualquier carácter | lo escribe en la contraseña |
| Lista de sesiones | ↑ / ↓, Intro | elegir · Esc: volver sin cambiar |
| Confirmación de energía | ← / →, Intro | Cancelar tiene el foco por defecto · Esc: cancelar |

## Licencias

Inter: SIL OFL 1.1 (`theme/sumi/assets/fonts/OFL.txt`). El proyecto será MIT: el autor lo decidió el 2026-11-22
y el archivo de licencia se añadirá al publicarlo, junto con Sumi Shell. Iconos y fondo: dibujados en el propio QML del tema.

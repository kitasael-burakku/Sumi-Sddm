# Sumi SDDM

Tema de inicio de sesión para SDDM (≥ 0.21, Qt 6): minimalista, con una notch superior como centro de
autenticación. Compatible con Sumi Shell, pero **independiente**: no usa Quickshell, Hyprland ni ningún
servicio de Sumi.

> Estado: Fase 2 (tema funcional, sin instalador). **No está instalado ni activado** en el sistema.

## Estructura

```
theme/sumi/              lo que se instalará en /usr/share/sddm/themes/sumi
  metadata.desktop       QtVersion=6, ConfigFile=theme.conf
  theme.conf             valores por defecto documentados (las personalizaciones van en theme.conf.user)
  Main.qml               adaptador: contexto de SDDM → propiedades de Greeter
  components/            Greeter, Style (config validada), Notch, NotchShape, Background, Clock,
                         UserStrip, Avatar, InputField, IconButton, PillButton, Spinner, Icon
  assets/fonts/          Inter 4 sin modificar + OFL.txt
tests/harness/           dobles de SDDM (MockBackend/Users/Sessions/Keyboard) y Render.qml (capturas)
tests/qml/               pruebas de comportamiento (qmltestrunner)
tests/fixtures/          theme.conf.user de prueba (válido y con basura)
tools/sumi-sddm          herramientas de desarrollo (sin privilegios)
docs/                    auditoría e informes por fase
```

## Desarrollo

```sh
tools/sumi-sddm lint                 # qmllint, 0 avisos exigidos
tools/sumi-sddm test                 # qmltestrunner, renderizador software y OpenGL (offscreen)
tools/sumi-sddm render --size all    # capturas de todos los escenarios en tests/out/
tools/sumi-sddm smoke                # greeter REAL (--test-mode, offscreen) sobre una copia en ~/.cache
tools/sumi-sddm check                # lint + test + smoke
```

Nada de esto abre ventanas, pide privilegios ni toca `/etc`, `/usr` o la configuración de SDDM.

Para verlo en una ventana (roba el foco del teclado mientras esté abierta; se cierra con la ventana):

```sh
sddm-greeter-qt6 --test-mode --theme ~/.cache/sumi-sddm/smoke/sumi   # tras un `smoke`
```

En `--test-mode` no hay daemon: el inicio de sesión no se autentica y los botones de energía no
hacen nada.

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

Inter: SIL OFL 1.1 (`theme/sumi/assets/fonts/OFL.txt`). La licencia del propio proyecto está pendiente
de decidir por el autor. Iconos y fondo: dibujados en el propio QML del tema.

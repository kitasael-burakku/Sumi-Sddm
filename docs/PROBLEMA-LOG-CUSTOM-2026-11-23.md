# Problema: `system log` marca un fallo falso cuando la configuración se aplicó después del arranque

Encontrado el 2026-11-23 al preparar la ventana Login screen de Sumi Shell, que enseña `system log`. **Sin corregir.**

## Qué pasa

En la máquina del autor, `sumi-sddm system log --json` sale con código 1 y dice:

```json
"greeters": [{ "pid": "878", "sumi": true, "ok": false,
  "ready": "sumi-sddm: ready users=1 sessions=2 primary=true clock=24h custom=7",
  "problems": ["se esperaba custom=6: sumi-sddm: ready users=1 sessions=2 primary=true clock=24h custom=7"] }],
"sumiOk": false, "expectCustom": 6, "logins": {"succeeded": 1, "failed": 0}
```

El greeter funcionó: el inicio de sesión fue correcto y no hubo mensajes de error. Sólo no coincide la cuenta de
claves personalizadas.

## Causa probable (sin verificar en el código)

`expectCustom` se calcula con el `theme.conf.user` aplicado **ahora** (`probe.expected_custom`,
`tools/sumiconf/probe.py:22`). El greeter de este arranque leyó el que estaba aplicado **cuando arrancó**. Si después
se aplicó otra configuración con una clave personalizada menos (Settings o el editor, `system apply`), las dos
cuentas difieren y se informa un problema que no lo es.

## Qué ve quien lo usa

- La ventana Login screen de Sumi Shell (página System) y el panel del sistema del editor enseñarían
  «1 problem» / «problemas» en un arranque sano.
- `system log` sale con 1: un script que lo use como comprobación daría fallo.

## Posibles arreglos (por decidir)

1. Comparar con lo aplicado en el momento del greeter: el helper ya guarda copias fechadas al aplicar
   (`/var/lib/sumi-sddm/backups/`). Si `lastChange` es posterior a la hora del greeter, usar la copia anterior
   o no comparar `custom`.
2. Si lo aplicado cambió después del greeter, convertir la diferencia en un aviso informativo («applied after this
   login screen started»), no en `problems`, y no salir con 1.
3. Que el greeter informe la huella de lo que leyó (además de `custom=`), y comparar huellas, no cuentas.

## Cómo reproducirlo

1. Arrancar con Sumi activo y una configuración aplicada de N claves personalizadas.
2. En la sesión, quitar o cambiar una clave y `sumi-sddm system apply`.
3. `sumi-sddm system log --json`: `sumiOk: false` con «se esperaba custom=N−1».

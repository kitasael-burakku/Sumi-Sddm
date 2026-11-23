# Sumi SDDM — recuperación

Si la pantalla de inicio de sesión de Sumi no funciona bien (no deja escribir, se queda en blanco, no responde),
**no hace falta reinstalar nada**: basta con volver al tema anterior.

## 1. Desde una consola de texto (TTY)

1. En la pantalla de inicio, pulsa **Ctrl+Alt+F3**. Si no responde, prueba con F2 a F6.
2. Inicia sesión con tu usuario y contraseña.
3. Ejecuta:

   ```sh
   sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate
   ```

   Repone el tema que había antes de activar Sumi (lo guarda el helper al activar). Para elegir otro tema
   instalado:

   ```sh
   sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate orbital
   ```

4. Vuelve a la pantalla gráfica con **Ctrl+Alt+F1** (o F2/F7). Sólo verás el tema repuesto la próxima vez que
   aparezca la pantalla de inicio. Para forzarlo ya, `sudo systemctl restart sddm` **cierra todas las sesiones
   gráficas abiertas**.

## 2. Sin el helper (a mano)

En `/etc/sddm.conf`, que es el archivo que SDDM lee al final y el que manda, cambia la línea de `[Theme]`:

```ini
[Theme]
Current=orbital
```

`sudo nano /etc/sddm.conf` vale. El helper guarda el archivo anterior en `/var/lib/sumi-sddm/backups/*-activate-*/sddm.conf`.

## 3. Si sólo falla tu configuración

Si el tema funciona sin tu configuración pero no con ella, puedes quitarla o volver a la anterior sin desactivar
Sumi:

```sh
sudo /usr/lib/sumi-sddm/sumi-sddm-helper reset      # quita theme.conf.user y tu wallpaper del tema
sudo /usr/lib/sumi-sddm/sumi-sddm-helper rollback   # vuelve a lo aplicado antes del último cambio
```

## Qué no puede pasar

- **El tema no toca la autenticación.** No modifica PAM ni las contraseñas: si el tema falla, tu usuario y tu
  contraseña siguen igual y funcionan en la TTY.
- **Un error de carga no te deja fuera.** Si el QML de Sumi ni siquiera carga, SDDM pasa solo a su tema interno y
  se puede iniciar sesión.
- **El helper no reinicia SDDM.** Activar o desactivar sólo cambia qué tema se verá la próxima vez.

#!/bin/sh
# sumi-sddm system launcher v1 — instalado por el paquete sumi-sddm como /usr/bin/sumi-sddm.
# Una copia de usuario (`sumi-sddm install --user`, en ~/.local/bin) gana si va antes en el PATH.
exec /usr/bin/python3 -I -B /usr/lib/sumi-sddm/tools/sumi-sddm "$@"

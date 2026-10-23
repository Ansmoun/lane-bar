#!/bin/sh
set -e
AUTO_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
        *) echo "arg desconocido: $1" >&2; exit 1 ;;
    esac
    shift
done
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi
SRC="${REAL_HOME}/proyectos/lane-bar"
DST="/opt/lane-bar"
if [ "$(id -u)" -ne 0 ]; then echo "necesita root"; exit 1; fi
if [ ! -f "$SRC/lane-bar.lua" ]; then echo "falta $SRC/lane-bar.lua"; exit 1; fi
if [ ! -d "/opt/lanetk/src/lib" ]; then echo "falta LaneTK"; exit 1; fi
if [ -d "$DST" ] && [ "$AUTO_YES" -eq 0 ]; then
    printf "==> Reemplazar $DST? [y/N] "
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelado."; exit 0 ;; esac
fi
echo "==> lane-bar — instalación en $DST"
rm -rf "$DST"; mkdir -p "$DST"
tar -C "$SRC" --exclude='./.git' --exclude='*.bak' --exclude='*.bak-*' \
    --exclude='*.orig' --exclude='*.swp' --exclude='.DS_Store' \
    -cf - . | tar -C "$DST" -xf -
chmod -R a+rX,go-w "$DST"
chmod +x "$DST/run"
[ -x "$DST/bin/lane-bar" ] && chmod +x "$DST/bin/lane-bar"
[ -f "$DST/tools/install.sh" ] && chmod +x "$DST/tools/install.sh"
cd "$DST"
if ./run -e '
    require("bar.engine")
    require("bar.widgets")
    require("bar.styles")
    require("launcher")
    require("launcher.tab")
    require("launcher.themes")
    print("requires OK")
' 2>&1; then
    echo "    OK"
else
    echo "    FALLO" >&2; exit 1
fi
echo "==> Instalación completa. lane-bar en $DST"

if [ -d "/opt/lane-launcher" ]; then
    echo
    echo "==> ATENCIÓN: /opt/lane-launcher todavía existe."
    echo "    El launcher fue fusionado en lane-bar (super+d →"
    echo "    /opt/lane-bar/bin/lane-bar toggle-launcher)."
    echo "    Una vez verificado que el atajo funciona, se puede"
    echo "    borrar con:  sudo rm -rf /opt/lane-launcher"
fi

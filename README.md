# lane-bar

Barra superior para [LaneTK](https://github.com/Ansmoun/lanetk). Forma parte
del ecosistema del entorno [Lane](https://github.com/Ansmoun/lane) pero es
autónoma.

Es un daemon con trigger file. Arranca con la sesión y permanece vivo. Se
configura mediante un `layout.lua` externo que declara qué widgets aparecen,
en qué orden, con qué estilo de separador y qué geometría.

## Requisitos

- LuaJIT
- LaneTK en `/opt/lanetk` o clonado en `~/proyectos/lanetk`
- Servidor X
- `xrandr` para detección de monitores
- `bspc` (opcional, para el modo smart con bspwm)

## Instalación

```sh
git clone https://github.com/Ansmoun/lane-bar.git
cd lane-bar
sudo tools/install.sh
```

## Configuración

La barra lee `layout.lua` desde el directorio del proyecto. El archivo declara
los widgets en tres zonas (izquierda, centro, derecha), el estilo de
separador y la geometría base:

```lua
return {
    style  = "dock",
    gap    = 12,
    left   = { "prompt" },
    center = {},
    right  = {
        { toggle_group = "telemetry", default = "visible",
          widgets = { "net", "mem", "gpu", "cpu", "temp" } },
        "bright", "vol", "bat", "clock",
    },
}
```

## Uso

Arrancar el daemon:

```sh
/opt/lane-bar/run /opt/lane-bar/app.lua
```

Control mediante trigger:

```sh
echo toggle > /tmp/lane-bar.cmd
echo "style dock" > /tmp/lane-bar.cmd
echo reload > /tmp/lane-bar.cmd
echo quit > /tmp/lane-bar.cmd
```

## Licencia

GPL-3.0. Ver [LICENSE](LICENSE).

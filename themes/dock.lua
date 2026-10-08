-- themes/dock.lua: tema por defecto. Reproduce el layout previo a
-- la introducción del sistema de temas (dock flotante abajo con
-- telemetría a la derecha).

return {
    style     = "dock",
    gap       = 12,
    left      = { "prompt" },
    center    = {},
    right     = {
        { toggle_group = "telemetry", default = "visible",
          widgets = { "net", "mem", "gpu", "cpu", "temp" } },
        "bright", "vol", "bat", "clock",
    },
}

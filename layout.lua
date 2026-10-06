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

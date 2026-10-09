-- themes/win10.lua: barra tipo Windows 10 taskbar.
--
--   [⊞] [🔍 Buscar]   [🦊] [⌨] [📁]      [🔔 📶 💾 📈] [☀ 🔊 🔋] [🕐]
--    ^start ^prompt   ^tasklist           ^telemetría  ^tray      ^reloj

local cairo = require("lib.cairo")

return {
    style   = "minimal",
    gap     = 14,
    fg_mode = "flat",

    follow_cursor = false,
    monitor       = "primary",

    geometry = {
        position = "bottom",
        width    = "screen",
        height   = 40,
        margin   = { 0, 0, 0, 0 },
    },

    draw_bg = function(cr, w, h, T)
        local bg  = T.bg_rgb or { 0.04, 0.05, 0.08 }
        local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }
        cairo.set_rgb(cr, bg[1], bg[2], bg[3])
        cairo.rectangle(cr, 0, 0, w, h)
        cairo.fill(cr)
        cairo.set_rgb(cr, sep[1], sep[2], sep[3])
        cairo.rectangle(cr, 0, 0, w, 1)
        cairo.fill(cr)
    end,

    left = {
        "start",
        "prompt",
    },
    center = {
        "tasklist",
    },
    right = {
        "vol", "bright", "bat", "clock",
    },
}

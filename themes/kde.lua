-- themes/kde.lua: barra tipo KDE Plasma.
--
--   [⊞]  [🔍]                            [📶 💾 📈]  [☀ 🔊 🔋 🕐]
--    ^start ^prompt                      ^telemetría    ^tray
--
-- Flat, monocromo (fg_mode = "flat"), fondo del tema = bg_card.

local cairo = require("lib.cairo")

return {
    -- "minimal" emite GapSep entre cada widget (el "none" no
    -- espaciaba nada, por eso se veía todo pegado).
    style   = "minimal",
    gap     = 16,
    -- Fuerza todos los widgets a fg_normal, ignorando el color
    -- propio de telemetría (net=violeta, cpu=verde, etc).
    fg_mode = "flat",
    -- Política por defecto del tema: barra fija en el monitor
    -- primario, sin seguir al mouse. El usuario puede sobreescribir
    -- desde config.bar.{follow_cursor,monitor}.
    follow_cursor = false,
    monitor       = "primary",

    geometry = {
        position = "top",
        width    = "screen",
        height   = 32,
        margin   = { 0, 0, 0, 0 },
    },

    -- Fondo sólido con borde inferior sutil.
    draw_bg = function(cr, w, h, T)
        local bg  = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
        local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }
        cairo.set_rgb(cr, bg[1], bg[2], bg[3])
        cairo.rectangle(cr, 0, 0, w, h)
        cairo.fill(cr)
        cairo.set_rgb(cr, sep[1], sep[2], sep[3])
        cairo.rectangle(cr, 0, h - 1, w, 1)
        cairo.fill(cr)
    end,

    left = {
        "start",
        "prompt",
    },
    center = {},
    right = {
        { toggle_group = "telemetry", default = "visible",
          widgets = { "net", "mem", "cpu" } },
        "bright", "vol", "bat", "clock",
    },
}

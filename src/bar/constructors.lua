-- Registry de constructores de widgets de barra.
-- Cada constructor es function(theme) -> Area | {
--   widget = <Area>, color = "#hex" | nil, set_fg = fn | nil }
--
-- El campo color se usa para el fondo del widget (modos bg,
-- underline, island) y para calcular el fg por contraste.
-- El campo set_fg, si está, permite al engine recolorear el texto
-- del widget.

local W = require("lib.widgets")
local G = require("lib.helpers.graphics")
local log = require("lib.log")

local M = {}

-- Envuelve un Text y expone set_fg.
local function text_widget(opts)
    local t = W.Text.new(opts)
    return {
        widget = t,
        set_fg = function(hex)
            local r, g, b = G.hex_to_rgba(hex)
            t:set_color(r, g, b)
        end,
    }
end

-- Añade un campo color al resultado de text_widget.
local function with_color(res, hex)
    res.color = hex
    return res
end

-- ─── Widgets sin color de telemetria (fondo transparente) ───

M["clock"] = function(theme)
    local T = theme or {}
    local c = T.accent_rgb or T.fg_rgb or { 0.9, 0.9, 0.9 }
    return text_widget {
        text = os.date("%H:%M"),
        font = "DejaVu Sans Bold 10",
        r = c[1], g = c[2], b = c[3],
        align = "center", valign = "center",
    }
end

M["taglist"] = function(theme)
    local T = theme or {}
    local c = T.fg_rgb or { 0.9, 0.9, 0.9 }
    return text_widget {
        text = "tags",
        font = "DejaVu Sans 10",
        r = c[1], g = c[2], b = c[3],
        align = "center", valign = "center",
    }
end

M["prompt"] = function(theme)
    local T = theme or {}
    local c = T.fg_rgb or { 0.9, 0.9, 0.9 }
    return text_widget {
        text = "",
        font = "DejaVu Sans 10",
        r = c[1], g = c[2], b = c[3],
        align = "center", valign = "center",
    }
end

-- ─── Widgets con color de telemetria ───
-- El color viene de theme.telemetry.<key>. Si la paleta no tiene
-- el campo, cae a theme.accent, y si no a un gris neutro.

local function telemetry(label, key)
    return function(theme)
        local T = theme or {}
        local hex = (T.telemetry and T.telemetry[key])
            or T.accent
            or "#808080"
        local c = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local r = text_widget {
            text = label,
            font = "DejaVu Sans 10",
            r = c[1], g = c[2], b = c[3],
            align = "center", valign = "center",
        }
        return with_color(r, hex)
    end
end

M["cpu"]    = telemetry("cpu",  "cpu")
M["mem"]    = telemetry("mem",  "ram")
M["gpu"]    = telemetry("gpu",  "gpu")
M["net"]    = telemetry("net",  "internet")
M["temp"]   = telemetry("temp", "temp")
M["bright"] = telemetry("bri",  "bright")
M["vol"]    = telemetry("vol",  "volume")
M["bat"]    = telemetry("bat",  "battery")

function M.register(name, fn)
    M[name] = fn
end

return M

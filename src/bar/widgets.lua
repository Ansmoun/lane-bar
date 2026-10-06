local W     = require("lib.widgets")
local G     = require("lib.helpers.graphics")
local F     = require("lib.helpers.format")
local D     = require("lib.data")
local Area  = require("lib.area")
local cairo = require("lib.cairo")
local svg   = require("lib.svg")

local M = {}

local ICON_SIZE = 18

-- Nombres del helper lib.icons. Algunos widgets usan nombres cortos
-- ("mem", "bat") que el helper no conoce; los traducimos acá.
local ICON_ALIAS = {
    mem    = "ram",
    bat    = "battery-outline",
    bright = "brightness",
    vol    = "volume-white",
    prompt = "search",
}

local function make_icon(name, rgb, size)
    size = size or ICON_SIZE
    local real = ICON_ALIAS[name] or name
    local surf = require("lib.icons").surface(real, size)
    if surf then
        return W.Icon.new {
            surface = surf,
            width = size, height = size,
            color = { rgb[1], rgb[2], rgb[3] },
            valign = "center",
        }
    end
    -- Fallback: un Text vacío del tamaño del icono, para que el layout
    -- no se rompa si el icono no existe.
    return W.Text.new {
        text = "",
        font = "DejaVu Sans 1",
        min_width = size, min_height = size,
    }
end

-- ─── BatteryIcon: outline SVG + fill semantico + bolt ───
-- Sigue el patron de Awesome (widgets/bat.lua):
--   - contorno y bolt tintados con color de contraste del fondo
--   - relleno con color semantico segun nivel:
--       pct <= 15 -> crit, pct <= 35 -> warn, > 35 -> muted
-- Esto da tres colores distintos en pantalla y hace visible
-- la forma, el nivel y el rayo.
local BatteryIcon = setmetatable({}, { __index = Area })
BatteryIcon.__index = BatteryIcon

function BatteryIcon.new(opts)
    opts = opts or {}
    local self = setmetatable(Area.new(opts), BatteryIcon)
    self.bw = opts.bw or 22
    self.bh = opts.bh or 11
    self.color = opts.color or { 1, 1, 1 }
    self.fill_crit = opts.fill_crit or { 0.8, 0.15, 0.11 }
    self.fill_warn = opts.fill_warn or { 0.84, 0.36, 0.05 }
    self.fill_base = opts.fill_base or { 0.57, 0.51, 0.45 }
    self.pct = 0
    self.charging = false
    local I = require("lib.icons")
    self.outline = I.surface("battery-outline", self.bw)
    self.bolt    = I.surface("battery-bolt",    self.bw)
    self.min_w = self.bw
    self.min_h = self.bh
    self.max_w = self.bw
    self.max_h = self.bh
    return self
end

function BatteryIcon:set_fill_colors(crit, warn, base)
    self.fill_crit = crit
    self.fill_warn = warn
    self.fill_base = base
end

function BatteryIcon:set_state(pct, charging)
    if self.pct == pct and self.charging == charging then return end
    self.pct = pct or 0
    self.charging = charging and true or false
    self:damage()
end

function BatteryIcon:set_color(r, g, b)
    if r == nil then self.color = nil
    else self.color = { r, g, b } end
    self:damage()
end

function BatteryIcon:draw(cr)
    if not self.outline then return end
    local r, g, b = self.color[1], self.color[2], self.color[3]
    local x = self.x0 + (self:getWidth()  - self.bw) / 2
    local y = self.y0 + (self:getHeight() - self.bh) / 2

    local pct = math.min(1, math.max(0, self.pct))
    local fill = self.fill_base
    if pct <= 0.15 then fill = self.fill_crit
    elseif pct <= 0.35 then fill = self.fill_warn end

    local pad_l = self.bw * 0.10
    local pad_r = self.bw * 0.20
    local pad_t = self.bh * 0.20
    local pad_b = self.bh * 0.20
    local ix = x + pad_l
    local iy = y + pad_t
    local iw = self.bw - pad_l - pad_r
    local ih = self.bh - pad_t - pad_b
    local fh = ih * pct
    if fh > 0.3 then
        cairo.set_rgba(cr, fill[1], fill[2], fill[3], 1.0)
        cairo.rectangle(cr, ix, iy + (ih - fh), iw, fh)
        cairo.fill(cr)
    end

    cairo.draw_surface_tinted(cr, self.outline,
        x, y, self.bw, self.bh, r, g, b)

    if self.charging and self.bolt then
        cairo.draw_surface_tinted(cr, self.bolt,
            x, y, self.bw, self.bh, r, g, b)
    end
end

local function icon_text(name, text, rgb, size)
    size = size or ICON_SIZE
    local ico = make_icon(name, rgb, size)
    local txt = W.Text.new {
        text   = text,
        font   = "DejaVu Sans Bold 10",
        r = rgb[1], g = rgb[2], b = rgb[3],
        align  = "center", valign = "center",
    }
    local grp = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        children = {
            { widget = ico, weight = 0 },
            { widget = txt, weight = 0 },
        },
    }
    return grp, ico, txt
end

local function fg_apply(ico, txt)
    return function(hex)
        local r, g, b = G.hex_to_rgba(hex)
        txt:set_color(r, g, b)
        if ico.set_color then
            ico:set_color(r, g, b)
        else
            ico.color = { r, g, b }
        end
        ico:damage()
    end
end

local function simple(icon, key, tick_ms, sampler, formatter)
    return function(T, srv)
        local hex = (T.telemetry and T.telemetry[key]) or T.accent or "#808080"
        local rgb = { G.hex_to_rgba(hex) }
        local grp, ico, txt = icon_text(icon, "--", rgb)
        local timer
        local function refresh()
            local ok, val = pcall(sampler)
            if ok and val ~= nil then
                txt:set_text(formatter(val))
            else
                txt:set_text("--")
            end
        end
        return {
            widget = grp,
            color = hex,
            set_fg = fg_apply(ico, txt),
            start = function()
                refresh()
                timer = srv:add_timer(tick_ms, refresh)
            end,
            stop = function()
                if timer then timer:cancel(); timer = nil end
            end,
        }
    end
end

M.clock = function(T, srv)
    local hex = T.accent or "#d79921"
    local rgb = { G.hex_to_rgba(hex) }
    local txt = W.Text.new {
        text = os.date("%H:%M"),
        font = "DejaVu Sans Bold 10",
        r = rgb[1], g = rgb[2], b = rgb[3],
        align = "center", valign = "center",
    }
    local timer
    return {
        widget = txt,
        set_fg = function(h)
            local r, g, b = G.hex_to_rgba(h)
            txt:set_color(r, g, b)
        end,
        start = function()
            timer = srv:add_timer(5000, function()
                txt:set_text(os.date("%H:%M"))
            end)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

M.cpu = simple("cpu", "cpu", 2000, function()
    local s = D.cpu.sample(); return s and s.usage
end, function(v) return string.format("%d%%", math.floor(v * 100)) end)

M.mem = simple("mem", "ram", 2000, function()
    local s = D.ram.sample(); return s and s.pct
end, function(v) return string.format("%d%%", math.floor(v * 100)) end)

M.gpu = simple("gpu", "gpu", 2000, function()
    local s = D.gpu.status(); return s and s.render
end, function(v) return string.format("%d%%", v) end)

M.temp = simple("temp", "temp", 5000, function()
    local path = D.temps.find_coretemp()
    if not path then return nil end
    local t = D.temps.read_coretemp(path)
    local max = 0
    for _, v in pairs(t) do if v and v > max then max = v end end
    return max > 0 and max or nil
end, function(v) return string.format("%d\u{00B0}", v) end)

M.bat = function(T, srv)
    local hex = (T.telemetry and T.telemetry.battery) or T.accent or "#83a598"
    local rgb = { G.hex_to_rgba(hex) }
    local ico = BatteryIcon.new { color = { 0, 0, 0 }, bw = 22, bh = 11 }
    if T.usage_crit then ico:set_fill_colors({ G.hex_to_rgba(T.usage_crit) },
                                             { G.hex_to_rgba(T.usage_warn or T.usage_crit) },
                                             { G.hex_to_rgba(T.muted or "#928374") })
    elseif T.usage_warn then ico:set_fill_colors({ G.hex_to_rgba(T.usage_warn) },
                                                 { G.hex_to_rgba(T.usage_warn) },
                                                 { G.hex_to_rgba(T.muted or "#928374") })
    end
    local txt = W.Text.new {
        text = "--", font = "DejaVu Sans Bold 10",
        r = rgb[1], g = rgb[2], b = rgb[3],
        align = "center", valign = "center",
    }
    local grp = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        children = {
            { widget = ico, weight = 0 },
            { widget = txt, weight = 0 },
        },
    }
    local timer
    local function refresh()
        if not D.bat.available() then
            txt:set_text("--"); ico:set_state(0, false); return
        end
        local s = D.bat.sample()
        if not s then
            txt:set_text("--"); ico:set_state(0, false); return
        end
        local charging = (s.status == "Charging" or s.status == "Full")
        ico:set_state(s.capacity / 100, charging)
        txt:set_text(string.format("%d%%", s.capacity))
    end
    return {
        widget = grp,
        color = hex,
        set_fg = function(h)
            local r, g, b = G.hex_to_rgba(h)
            txt:set_color(r, g, b)
            ico:set_color(r, g, b)
        end,
        start = function()
            refresh()
            timer = srv:add_timer(10000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

M.bright = simple("bright", "bright", 3000, function()
    local s = D.brightness.sample(); return s and s.pct
end, function(v) return string.format("%d%%", math.floor(v * 100)) end)

M.vol = function(T, srv)
    local hex = (T.telemetry and T.telemetry.volume) or T.accent or "#af3a03"
    local rgb = { G.hex_to_rgba(hex) }
    local grp, ico, txt = icon_text("vol", "--", rgb)
    local timer
    local function refresh()
        local s = D.volume.sample()
        if not s then txt:set_text("--"); return end
        if s.muted then txt:set_text("mute")
        else txt:set_text(string.format("%d%%", math.floor(s.pct * 100))) end
    end
    return {
        widget = grp,
        color = hex,
        set_fg = fg_apply(ico, txt),
        start = function()
            refresh()
            timer = srv:add_timer(2000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

M.net = function(T, srv)
    local hex = (T.telemetry and T.telemetry.internet) or T.accent or "#b16286"
    local rgb = { G.hex_to_rgba(hex) }
    local grp, ico, txt = icon_text("net", "--", rgb)
    local prev_rx, prev_tx, prev_t
    local wifi = require("lib.data.wifi")
    local net  = require("lib.data.net")
    local timer
    local function refresh()
        local iface = wifi.iface()
        if not iface or iface == "" then txt:set_text("--"); return end
        local b = net.iface_bytes(iface)
        if not b then txt:set_text("--"); return end
        local now = os.time()
        if prev_rx and prev_t then
            local dt = now - prev_t
            if dt > 0 then
                local rx = (b.rx - prev_rx) / dt
                local tx = (b.tx - prev_tx) / dt
                txt:set_text(string.format("%s/%s", F.speed(tx), F.speed(rx)))
            end
        end
        prev_rx, prev_tx, prev_t = b.rx, b.tx, now
    end
    return {
        widget = grp,
        color = hex,
        set_fg = fg_apply(ico, txt),
        start = function()
            refresh()
            timer = srv:add_timer(3000, refresh)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

M.prompt = function(T, srv)
    local hex = T.fg_normal or "#ebdbb2"
    local rgb = { G.hex_to_rgba(hex) }
    local grp, ico, txt = icon_text("prompt", "", rgb)
    return { widget = grp, set_fg = fg_apply(ico, txt) }
end

function M.register(name, fn) M[name] = fn end

return M

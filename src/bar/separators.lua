-- Primitivas de separadores y envoltorios para la barra.
-- Portado de ui/bar.lua (Awesome).

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local G     = require("lib.helpers.graphics")
local pango = require("lib.pango")
local Text  = require("lib.widgets.text")

local M = {}

-- ─── Utilidades de color ─────────────────────────────────────

function M.luminance(hex)
    if not hex or #hex < 7 then return 0.5 end
    local r = tonumber(hex:sub(2,3), 16) or 0
    local g = tonumber(hex:sub(4,5), 16) or 0
    local b = tonumber(hex:sub(6,7), 16) or 0
    return (0.299*r + 0.587*g + 0.114*b) / 255
end

function M.pick_fg(hex)
    return M.luminance(hex) > 0.55 and "#000000" or "#FEFEFE"
end

function M.rgb_to_hex(rgb)
    local r = math.floor((rgb[1] or 0) * 255 + 0.5)
    local g = math.floor((rgb[2] or 0) * 255 + 0.5)
    local b = math.floor((rgb[3] or 0) * 255 + 0.5)
    return string.format("#%02x%02x%02x", r, g, b)
end

-- ─── ArrowSep: triangulo de transicion entre dos colores ────

local ArrowSep = setmetatable({}, { __index = Area })
ArrowSep.__index = ArrowSep

function ArrowSep.new(color_from, color_to, theme, width)
    local self = setmetatable(Area.new {}, ArrowSep)
    self.color_from = color_from
    self.color_to   = color_to
    self.theme      = theme or {}
    self.width      = width or 16
    self.min_w = self.width
    self.max_w = self.width
    self.min_h = 0
    self.max_h = 10000
    return self
end

function ArrowSep:askMinMax(minw, minh, maxw, maxh)
    return minw + self.width, minh, maxw + self.width, maxh
end

function ArrowSep:draw(cr)
    local x0, y0 = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()
    if w < 1 or h < 1 then return end

    -- Fondo color_from
    if self.color_from and self.color_from ~= "alpha" then
        local r, g, b = G.hex_to_rgba(self.color_from)
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, x0, y0, w, h)
        cairo.fill(cr)
    end

    -- Triangulo color_to
    local tr, tg, tb
    if self.color_to and self.color_to ~= "alpha" then
        tr, tg, tb = G.hex_to_rgba(self.color_to)
    else
        local T = self.theme
        if T.bg_rgb then
            tr, tg, tb = T.bg_rgb[1], T.bg_rgb[2], T.bg_rgb[3]
        else
            tr, tg, tb = 0.1, 0.1, 0.13
        end
    end
    -- Triangulo con base a la derecha y pico en el centro izquierdo:
    -- forma de arrow_left. El fondo es color_from (el anterior), el
    -- triangulo es color_to (el nuevo) entrando desde la izquierda.
    cairo.set_rgb(cr, tr, tg, tb)
    cairo.move_to(cr, x0 + w, y0)
    cairo.line_to(cr, x0, y0 + h / 2)
    cairo.line_to(cr, x0 + w, y0 + h)
    cairo.close_path(cr)
    cairo.fill(cr)
end

M.ArrowSep = ArrowSep

-- ─── GlyphSep: separador de texto (│ o ┃) ────────────────────

function M.GlyphSep(char, color, font)
    local t = Text.new {
        text = char,
        font = font or "DejaVu Sans 10",
        align = "center", valign = "center",
    }
    local r, g, b = G.hex_to_rgba(color or "#333333")
    t:set_color(r, g, b)
    t.min_w = 12
    t.max_w = 12
    return t
end

-- ─── GapSep: spacer de ancho fijo ────────────────────────────

function M.GapSep(width)
    local t = Text.new {
        text = "",
        font = "DejaVu Sans 1",
    }
    t.min_w = width
    t.max_w = width
    return t
end

-- ─── Wrapper: envuelve un widget con fondo/subrayado/isla ────

local Wrapper = setmetatable({}, { __index = Area })
Wrapper.__index = Wrapper

function Wrapper.new(inner, mode, color, opts)
    opts = opts or {}
    local self = setmetatable(Area.new {}, Wrapper)
    self.inner = inner
    self.mode  = mode  -- "bg" | "underline" | "island"
    self.color = color
    self.radius = opts.radius or 3
    self.vgap   = opts.vgap or 0
    self.pad_x  = opts.pad_x or 0
    self.min_h  = 0
    return self
end

function Wrapper:set_window(win)
    self.window = win
    if self.inner then
        if self.inner.set_window then self.inner:set_window(win)
        else self.inner.window = win end
    end
end

function Wrapper:askMinMax(minw, minh, maxw, maxh)
    if not self.inner then return minw, minh, maxw, maxh end
    local iw, ih, imw, imh = self.inner:askMinMax(0, 0, 0, 0)
    local pad2 = self.pad_x * 2
    local v2 = self.vgap * 2
    return minw + iw + pad2, minh + ih + v2,
           maxw + imw + pad2, maxh + imh + v2
end

function Wrapper:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    if not self.inner then return end
    local px0 = x0 + self.pad_x
    local px1 = x1 - self.pad_x
    if self.mode == "island" then
        self.inner:layout(px0, y0 + self.vgap, px1, y1 - self.vgap)
    else
        self.inner:layout(px0, y0, px1, y1)
    end
end

function Wrapper:getByXY(x, y)
    if self.inner then
        local hit = self.inner:getByXY(x, y)
        if hit then return hit end
    end
    return Area.getByXY(self, x, y)
end

function Wrapper:draw(cr)
    local x0, y0 = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()

    if self.color then
        local r, g, b = G.hex_to_rgba(self.color)
        if self.mode == "bg" then
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, x0, y0, w, h)
            cairo.fill(cr)
        elseif self.mode == "underline" then
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, x0, y0 + h - 2, w, 2)
            cairo.fill(cr)
        elseif self.mode == "island" then
            cairo.set_rgb(cr, r, g, b)
            cairo.rounded_rect(cr, x0 + 2, y0 + self.vgap,
                w - 4, h - self.vgap * 2, self.radius)
            cairo.fill(cr)
        end
    end

    if self.inner then self.inner:draw(cr) end
end

-- ─── Constructores de wrappers ──────────────────────────────

function M.ColorBox(inner, color)
    return Wrapper.new(inner, "bg", color, { pad_x = 0 })
end

function M.UnderlineBox(inner, color)
    return Wrapper.new(inner, "underline", color, { pad_x = 0 })
end

function M.IslandBox(inner, color, vgap)
    return Wrapper.new(inner, "island", color,
        { vgap = vgap or 4, pad_x = 0 })
end

return M

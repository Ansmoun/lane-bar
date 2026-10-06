-- Traduce una spec de posicion a coordenadas absolutas sobre un
-- monitor.
--
-- spec:
--   position  = "top" | "bottom" | "left" | "right" | "free"
--   width     = <px> | "screen" | "N%" | nil (default: segun
--               position: "screen" para top/bottom, <px> para
--               left/right)
--   height    = <px> | "screen" | "N%" | nil (default: segun
--               position)
--   margin    = { top, right, bottom, left } (px)
--   x, y      = <px> | "center" | "start" | "end" | "N%" (opcional,
--               "free" y "bottom" usan x; "top" y "bottom" usan y solo en "free")
--
-- Devuelve { x, y, w, h, position }.

local M = {}

-- Resuelve una dimension (ancho o alto) contra el tamano del monitor.
local function dim(val, avail)
    if val == nil then return nil end
    if type(val) == "number" then return math.floor(val) end
    if val == "screen" then return avail end
    if type(val) == "string" then
        local pct = val:match("^(%d+)%%$")
        if pct then return math.floor(avail * tonumber(pct) / 100) end
    end
    error("geometry: dimension desconocida: " .. tostring(val))
end

-- Resuelve una posicion (x o y) contra el tamano del monitor.
local function pos(val, avail, size)
    if val == nil then return 0 end
    if type(val) == "number" then return math.floor(val) end
    if val == "center" then return math.floor((avail - size) / 2) end
    if val == "start"  then return 0 end
    if val == "end"    then return avail - size end
    if type(val) == "string" then
        local pct = val:match("^(%d+)%%$")
        if pct then return math.floor(avail * tonumber(pct) / 100) end
    end
    error("geometry: posicion desconocida: " .. tostring(val))
end

function M.compute(spec, mon)
    spec = spec or {}
    local m = spec.margin or {}
    local mt = m[1] or 0
    local mr = m[2] or 0
    local mb = m[3] or 0
    local ml = m[4] or 0

    local position = spec.position or "top"
    local w, h, x, y

    if position == "top" then
        w = dim(spec.width or "screen", mon.w)
        h = dim(spec.height, mon.h) or 24
        x = mon.x + ml
        y = mon.y + mt

    elseif position == "bottom" then
        w = dim(spec.width or "screen", mon.w)
        h = dim(spec.height, mon.h) or 24
        x = mon.x + pos(spec.x, mon.w, w)
        y = mon.y + mon.h - h - mb

    elseif position == "left" then
        w = dim(spec.width, mon.w) or 24
        h = dim(spec.height or "screen", mon.h)
        x = mon.x + ml
        y = mon.y + mt

    elseif position == "right" then
        w = dim(spec.width, mon.w) or 24
        h = dim(spec.height or "screen", mon.h)
        x = mon.x + mon.w - w - mr
        y = mon.y + mt

    elseif position == "free" then
        w = dim(spec.width, mon.w) or 200
        h = dim(spec.height, mon.h) or 24
        x = mon.x + pos(spec.x, mon.w, w)
        y = mon.y + pos(spec.y, mon.h, h)

    else
        error("geometry: position desconocida: " .. tostring(position))
    end

    return { x = x, y = y, w = w, h = h, position = position }
end

return M

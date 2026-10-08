local W     = require("lib.widgets")
local G     = require("lib.helpers.graphics")
local F     = require("lib.helpers.format")
local D     = require("lib.data")
local Area  = require("lib.area")
local cairo = require("lib.cairo")
local svg   = require("lib.svg")
local pango = require("lib.pango")

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


-- M.start: botón "inicio". Icono clickeable que dispara el toggle
-- del launcher via su trigger file. Usado por los temas kde/win10.
--
-- opts:
--   size       : tamaño del icono (default 22)
--   icon       : nombre del icono (default "start")
--   command    : trigger file del launcher (default "/tmp/lane-launcher.cmd")
M.start = function(T, srv, ctx)
    local size = 22
    local ico_name = "start"
    local trigger  = "/tmp/lane-launcher.cmd"
    local hex = T.fg_normal or "#ebdbb2"
    local rgb = { G.hex_to_rgba(hex) }
    local ico = make_icon(ico_name, rgb, size)

    ico._on_click = function()
        local f = io.open(trigger, "w")
        if f then f:write("toggle\n"); f:close() end
    end

    -- Publica la posición del botón en session para que el launcher
    -- pueda anclarse a él (anchor = "start"). Se hace cada 500ms
    -- porque la posición real solo se conoce después del primer
    -- layout del árbol.
    local timer
    return {
        widget = ico,
        start = function()
            timer = srv:add_timer(500, function()
                if not ctx or not ctx.sess then return end
                local w = (ico.x1 or 0) - (ico.x0 or 0)
                if w > 0 then
                    ctx.sess:set("start", {
                        x = ico.x0, y = ico.y0,
                        w = w,
                        h = (ico.y1 or 0) - (ico.y0 or 0),
                    })
                end
            end)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
            if ctx and ctx.sess then ctx.sess:clear("start") end
        end,
    }
end


-- ─── Tasklist ───────────────────────────────────────────────────
--
-- Visor de ventanas activas del monitor donde vive la barra. Cada
-- ventana es un icono clickeable.
--
--   [🦊] [⌨] [📁]        ^activa     ^inactiva  ^inactiva
--
-- Click izquierdo: enfoca la ventana (y su escritorio si aplica).
-- Click derecho: cierra la ventana.
--
-- Datos: bspc query para IDs, xprop para WM_CLASS + _NET_WM_NAME.
-- Poll cada 1000ms.

-- Consulta bspc: devuelve array de { id (hex string), id_dec (num) }.
local function bspc_leaves(monitor)
    local out = {}
    if not monitor or monitor == "" then return out end
    local cmd = string.format(
        "bspc query -N -m %s -n '.leaf' 2>/dev/null", monitor)
    local h = io.popen(cmd)
    if not h then return out end
    for line in h:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local n = tonumber(line)
            if n then
                out[#out + 1] = { id = line, id_dec = n }
            end
        end
    end
    h:close()
    return out
end

-- xprop batch: WM_CLASS + _NET_WM_NAME de N ventanas en un solo
-- proceso. Devuelve { [id_hex] = { class = "...", name = "..." } }.
local function xprop_batch(ids)
    local out = {}
    if #ids == 0 then return out end
    local args = {}
    for _, w in ipairs(ids) do
        args[#args + 1] = "-id " .. w.id
    end
    local cmd = "xprop " .. table.concat(args, " ")
                .. " WM_CLASS _NET_WM_NAME 2>/dev/null"
    local h = io.popen(cmd)
    if not h then return out end
    local cur_id = nil
    for line in h:lines() do
        -- xprop agrupa por ventana y separa con línea en blanco.
        if line == "" then
            cur_id = nil
        else
            -- Detectar el inicio de un bloque por la primera línea
            -- que contiene "WM_CLASS" o "_NET_WM_NAME".
            local cls = line:match('WM_CLASS%s*%(STRING%)%s*=%s*"([^"]+)"%s*,%s*"([^"]+)"')
            if cls then
                -- Guardamos con la ventana actual (por orden).
                -- xprop no incluye el id en cada línea, así que
                -- reconstruimos por orden de aparición.
                out[#out + 1] = { class = cls }
            end
            local nm = line:match('_NET_WM_NAME%s*%(UTF8_STRING%)%s*=%s*"([^"]*)"')
            if nm and #out > 0 then
                out[#out].name = nm
            end
        end
    end
    h:close()
    -- Mapear por índice al id original.
    local by_id = {}
    for i, w in ipairs(ids) do
        by_id[w.id] = out[i] or { class = nil, name = nil }
    end
    return by_id
end

-- Sinónimos de WM_CLASS → nombre de icono estándar. La mayoría de
-- apps ya emiten un WM_CLASS que find_icon resuelve, pero hay
-- excepciones donde el binario se llama distinto al icono.
local WMCLASS_ICON_ALIAS = {
    ["pcmanfm"]        = "system-file-manager",
    ["thunar"]         = "Thunar",
    ["nautilus"]       = "org.gnome.Nautilus",
    ["nemo"]           = "folder",
    ["caja"]           = "folder",
    ["dolphin"]        = "system-file-manager",
    ["st"]             = "utilities-terminal",
    ["xterm"]          = "utilities-terminal",
    ["alacritty"]      = "utilities-terminal",
    ["kitty"]          = "utilities-terminal",
    ["lxappearance"]   = "preferences-desktop-theme",
    ["pavucontrol"]    = "multimedia-volume-control",
    ["nm-connection-editor"] = "network-wireless",
    ["blueman-manager"] = "bluetooth",
    ["gimp"]           = "gimp",
    ["inkscape"]       = "inkscape",
    ["code"]           = "code",
    ["code-oss"]       = "code-oss",
    ["vlc"]            = "vlc",
    ["mpv"]            = "mpv",
}

-- Mapeo de _NET_WM_NAME (para apps LANE que todas emiten lanetk
-- como WM_CLASS) a iconos propios del proyecto.
local LANE_NAME_TO_ICON = {
    ["Laneter"]           = "tab-book",
    ["LANE — Archivos"]   = "files/folder",
    ["LANE — Config"]     = "tab-settings",
    ["LANE — Discos"]     = "tab-disk",
    ["LANE — Procesos"]   = "tab-list",
    ["LANE — Bateria"]    = "tab-battery",
    ["LANE — Logout"]     = "logout/logout",
    ["LANE — Inicio"]     = "tab-home",
    ["LANE — Buscar"]     = "tab-search",
    ["LANE — Launcher"]   = "tab-dashboard",
    ["LANE — Red"]        = "tab-wifi",
    ["LANE — Screenshot"] = "screenshot/area",
    ["LANE — Sysmon"]     = "tab-chip",
}

M.tasklist = function(T, srv, ctx)
    local ICON_SIZE   = 22
    local PAD_X       = 6
    local GAP         = 4
    local ITEM_W      = ICON_SIZE + PAD_X * 2
    local ITEM_H      = ICON_SIZE + 4
    local POLL_MS     = 500

    local D        = require("lib.data.launcher")
    local Icons    = require("lib.icons")
    local svg      = require("lib.svg")

    local TaskList = setmetatable({}, { __index = Area })
    TaskList.__index = TaskList

    function TaskList.new(opts)
        local self = setmetatable(Area.new(opts), TaskList)
        self._hover_visual = true
        self._pressed_visual = true
        self.theme = T
        self.windows = {}
        self.hover_idx = -1
        self.min_h, self.max_h = ITEM_H, ITEM_H
        self.min_w = 20
        self.max_w = 10000
        return self
    end

    function TaskList:set_windows(list)
        self.windows = list
        self:damage()
    end

    function TaskList:draw(cr)
        local T2 = self.theme
        local accent = T2.accent_rgb or { 0.9, 0.7, 0.4 }
        local sep    = T2.separator_rgb or { 0.3, 0.3, 0.3 }
        local fg     = T2.fg_rgb or { 0.9, 0.9, 0.9 }
        local y = self.y0
        local h = self:getHeight()
        for i, w in ipairs(self.windows) do
            local x = self.x0 + (i - 1) * (ITEM_W + GAP)
            local active = w.active
            local hover  = (i == self.hover_idx)

            -- Barra inferior de "activo" (estilo Win10).
            if active then
                cairo.set_rgba(cr, accent[1], accent[2], accent[3], 0.25)
                cairo.rounded_rect(cr, x + 1, y + 2, ITEM_W - 2, h - 4, 4)
                cairo.fill(cr)
                cairo.set_rgb(cr, accent[1], accent[2], accent[3])
                cairo.rounded_rect(cr, x + 4, y + h - 3, ITEM_W - 8, 2, 1)
                cairo.fill(cr)
            elseif hover then
                cairo.set_rgba(cr, sep[1], sep[2], sep[3], 0.35)
                cairo.rounded_rect(cr, x + 1, y + 2, ITEM_W - 2, h - 4, 4)
                cairo.fill(cr)
            end

            if w.surface then
                cairo.draw_surface(cr, w.surface,
                    x + PAD_X, y + (h - ICON_SIZE) / 2,
                    ICON_SIZE, ICON_SIZE)
            else
                -- Fallback: letra inicial de name o class.
                local label = (w.name or w.class or "?")
                -- Si name tiene "—" usamos lo que sigue (más limpio).
                local after = label:match("—%s*(.+)$")
                if after then label = after end
                local letter = label:sub(1, 1):upper()
                local iw, ih = pango.measure(letter, "DejaVu Sans Bold 12")
                pango.draw_text(cr,
                    x + (ITEM_W - iw) / 2, y + (h - ih) / 2,
                    letter, "DejaVu Sans Bold 12",
                    { r = fg[1], g = fg[2], b = fg[3] })
            end
        end
    end

    function TaskList:on_mouse_move(mx, my)
        local idx = -1
        for i, _ in ipairs(self.windows) do
            local x0 = (i - 1) * (ITEM_W + GAP)
            if mx >= x0 and mx < x0 + ITEM_W then idx = i; break end
        end
        if idx ~= self.hover_idx then
            self.hover_idx = idx
            self:damage()
        end
    end

    function TaskList:on_mouse_press(mx, my, button)
        for i, w in ipairs(self.windows) do
            local x0 = (i - 1) * (ITEM_W + GAP)
            if mx >= x0 and mx < x0 + ITEM_W then
                if button == 1 then
                    -- Enfocar. Si la ventana está en otro desktop, bspc
                    -- la trae automáticamente con -f.
                    os.execute(string.format(
                        "bspc node %s -f >/dev/null 2>&1 &", w.id))
                elseif button == 3 then
                    os.execute(string.format(
                        "bspc node %s -c >/dev/null 2>&1 &", w.id))
                end
                return
            end
        end
    end

    local widget = TaskList.new {}

    -- Cache: "key" -> surface | false
    local icon_cache = {}

    -- Cascada de resolución de icono:
    --   1. name en LANE_NAME_TO_ICON → Icons.surface (iconos del proyecto)
    --   2. WMCLASS_ICON_ALIAS[class] → D.find_icon
    --   3. D.find_icon(class)
    --   4. D.find_icon(name)
    --   5. Icons.surface(class) o Icons.surface(name)
    --   6. nil → fallback a letra inicial
    local function resolve_icon(w)
        local cache_key = (w.class or "") .. "|" .. (w.name or "")
        local cached = icon_cache[cache_key]
        if cached ~= nil then return cached or nil end

        local surf = nil

        -- Paso 1: name en tabla LANE.
        if w.name and LANE_NAME_TO_ICON[w.name] then
            surf = Icons.surface(LANE_NAME_TO_ICON[w.name], ICON_SIZE)
        end

        -- Paso 2-3: class (con y sin sinónimo).
        if not surf and w.class and w.class ~= "" then
            local cls = w.class:lower()
            local alias = WMCLASS_ICON_ALIAS[cls]
            local path = D.find_icon(alias or cls)
            if path then
                if path:match("%.svg$") then
                    surf = svg.load(path, ICON_SIZE, ICON_SIZE)
                else
                    surf = cairo.load_png_cached(path)
                end
            end
        end

        -- Paso 4: name completo.
        if not surf and w.name and w.name ~= "" then
            local path = D.find_icon(w.name:lower())
            if path then
                if path:match("%.svg$") then
                    surf = svg.load(path, ICON_SIZE, ICON_SIZE)
                else
                    surf = cairo.load_png_cached(path)
                end
            end
        end

        -- Paso 5: Icons del proyecto (fallback).
        if not surf then
            surf = Icons.surface(w.class or "", ICON_SIZE)
            if not surf and w.name then
                surf = Icons.surface(w.name, ICON_SIZE)
            end
        end

        icon_cache[cache_key] = surf or false
        return surf
    end

    local timer
    local function refresh()
        if not ctx or not ctx.sess then return end
        local dock = ctx.sess:get("dock")
        local mon = dock and dock.monitor
        if not mon then return end

        local leaves = bspc_leaves(mon)
        local ids = {}
        for _, w in ipairs(leaves) do ids[#ids + 1] = { id = w.id } end
        local meta = xprop_batch(ids)

        -- Ventana activa: la que tiene el foco del WM en este monitor.
        local active_id = nil
        do
            local h = io.popen(string.format(
                "bspc query -N -m %s -n '.active' 2>/dev/null", mon))
            if h then
                active_id = h:read("*l")
                h:close()
            end
            if not active_id or active_id == "" then
                h = io.popen(
                    "bspc query -N -n 'focused' 2>/dev/null")
                if h then
                    active_id = h:read("*l")
                    h:close()
                end
            end
        end

        local out = {}
        for _, w in ipairs(leaves) do
            local m = meta[w.id] or {}
            local class = m.class and (m.class[2] or m.class[1])
            local item = {
                id = w.id,
                class = class,
                name = m.name,
                active = (w.id == active_id),
            }
            item.surface = resolve_icon(item)
            out[#out + 1] = item
        end
        widget:set_windows(out)
    end

    return {
        widget = widget,
        start = function()
            local ok, err = pcall(refresh)
            if not ok then
                require("lib.log").warn("bar",
                    "tasklist refresh (start) fallo: %s", tostring(err))
            end
            timer = srv:add_timer(POLL_MS, function()
                local ok2, err2 = pcall(refresh)
                if not ok2 then
                    require("lib.log").warn("bar",
                        "tasklist refresh fallo: %s", tostring(err2))
                end
            end)
        end,
        stop = function()
            if timer then timer:cancel(); timer = nil end
        end,
    }
end

function M.register(name, fn) M[name] = fn end

return M

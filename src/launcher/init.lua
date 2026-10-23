-- launcher/init.lua: controlador de la ventana del launcher, embebido
-- en el daemon de lane-bar.
--
-- A diferencia del lane-launcher one-shot original, este módulo NO:
--   - crea su propio Server (usa el de la barra)
--   - carga la paleta (usa T de la barra)
--   - inicializa anim (usa el de la barra, fps=60)
--   - llama theme.load()/config.get() propios (la barra los tiene)
--   - instala config.watch/theme.watch/reload.install (la barra los encadena)
--   - watcha SIGUSR2 (todo va por lane-bar.sock)
--   - resuelve monitores por io.popen("xrandr") (la barra ya los tiene)
--
-- API:
--   local Launcher = require("launcher")
--   local L = Launcher.new {
--       srv       = srv,
--       T         = T,
--       config    = config,
--       bar_state = {
--           geo       = function() return bar_geo end,       -- nil o {x,y,w,h,position,monitor}
--           start_pos = function() return x,y,w,h end,       -- nil o números ROOT
--       },
--   }
--   L:toggle() / L:show() / L:hide() / L:is_open() / L:invalidate()
--
-- El tab del launcher se construye lazy (require("launcher.tab") solo la
-- primera vez que se muestra). Si se invalida, se destruye y se recrea.
-- lib.data.launcher conserva su cache entre invalidaciones (global al
-- proceso de la barra).

local Window  = require("lib.window")
local cairo   = require("lib.cairo")
local xanim   = require("lib.xshape_anim")
local screens = require("lib.screens")
local xcb     = require("lib.xcb")
local log     = require("lib.log")

local M = {}
M.__index = M

local RADIUS     = 6
local ANIM_MS    = 260
local DEFAULT_W  = 640
local DEFAULT_H  = 460

local function pick_primary_screen()
    local list = screens.list()
    for _, s in ipairs(list) do
        if s.name == "VGA-1" then return s end
    end
    return list[1]
end

-- Resuelve monitor por nombre (mismo contrato que el lane-launcher
-- original). Solo se usa como fallback cuando no hay dock publicado.
-- Con dock, el monitor sale de bar_state.geo().monitor.
local function resolve_monitor(srv, name)
    name = name or "primary"
    if name == "primary" then
        return pick_primary_screen()
    elseif name == "cursor" then
        local cx, cy = xcb.query_pointer(srv.conn)
        if cx then
            local m = screens.at(cx, cy)
            if m then return m end
        end
        return pick_primary_screen()
    elseif name == "focused" then
        local h = io.popen("bspc query -M --names -d 2>/dev/null")
        if h then
            local mname = h:read("*l"); h:close()
            if mname and mname ~= "" then
                for _, s in ipairs(screens.list()) do
                    if s.name == mname then return s end
                end
            end
        end
        return pick_primary_screen()
    else
        for _, s in ipairs(screens.list()) do
            if s.name == name then return s end
        end
        log.warn("launcher", "monitor desconocido: %s", tostring(name))
        return pick_primary_screen()
    end
end

function M.new(opts)
    local self = setmetatable({}, M)
    self.srv       = opts.srv
    self.T         = opts.T
    self.config    = opts.config
    self.bar_state = opts.bar_state or {}

    self._win        = nil
    self._win_handle = nil
    self._tab        = nil
    self._cur_w      = DEFAULT_W
    self._cur_h      = DEFAULT_H

    return self
end

function M:is_open()
    if not self._win_handle then return false end
    if not self._win or self._win.destroyed then return false end
    return self._win_handle:visible()
end

function M:_read_dock_geo()
    local g = self.bar_state.geo and self.bar_state.geo()
    if not g then return nil end
    if not g.x or not g.w or g.w <= 0 then return nil end
    return { x = g.x, y = g.y, w = g.w, h = g.h,
             edge = g.position, monitor = g.monitor }
end

function M:_read_start_pos()
    if not self.bar_state.start_pos then return nil end
    local x, y, w, h = self.bar_state.start_pos()
    if not x or not w or w <= 0 then return nil end
    return { x = x, y = y, w = w, h = h }
end

-- Resuelve posicion del launcher segun cfg.launcher.anchor.
function M:_resolve_anchor(cfg)
    local anchor = cfg.launcher.anchor or "dock"
    local gap    = cfg.launcher.gap or 8

    if anchor == "dock" then
        local g = self:_read_dock_geo()
        if g then
            local edge = g.edge or "bottom"
            if edge == "bottom" then
                local x = g.x + math.floor((g.w - self._cur_w) / 2)
                local y = g.y - self._cur_h - gap
                if y < 0 then y = 0 end
                return x, y
            elseif edge == "top" then
                local x = g.x + math.floor((g.w - self._cur_w) / 2)
                local y = g.y + g.h + gap
                return x, y
            elseif edge == "left" then
                local x = g.x + g.w + gap
                local y = g.y + math.floor((g.h - self._cur_h) / 2)
                if y < 0 then y = 0 end
                return x, y
            elseif edge == "right" then
                local x = g.x - self._cur_w - gap
                local y = g.y + math.floor((g.h - self._cur_h) / 2)
                if y < 0 then y = 0 end
                return x, y
            end
        end
        anchor = "monitor-center"
    end

    -- Monitor: primero el del dock, si no cfg.launcher.monitor o "cursor".
    local mon = nil
    do
        local g = self:_read_dock_geo()
        if g and g.monitor and g.monitor ~= "" then
            for _, s in ipairs(screens.list()) do
                if s.name == g.monitor then mon = s; break end
            end
        end
    end
    if not mon then
        mon = resolve_monitor(self.srv, cfg.launcher.monitor or "cursor")
    end
    if not mon then return nil end

    if anchor == "monitor-center" then
        return mon.x + math.floor((mon.w - self._cur_w) / 2),
               mon.y + math.floor((mon.h - self._cur_h) / 2)
    elseif anchor == "monitor-top" then
        return mon.x + math.floor((mon.w - self._cur_w) / 2),
               mon.y + gap
    elseif anchor == "cursor" then
        local cx, cy = xcb.query_pointer(self.srv.conn)
        if not cx then return nil end
        local mcur = screens.at(cx, cy) or mon
        local x = mcur.x + math.floor((mcur.w - self._cur_w) / 2)
        local y = cy - self._cur_h - gap
        if y < mcur.y then y = mcur.y + gap end
        return x, y
    elseif anchor == "monitor-bottom-right"
        or anchor == "monitor-bottom-left"
        or anchor == "monitor-top-right"
        or anchor == "monitor-top-left" then
        local margin = cfg.launcher.margin or 12
        local x, y
        if anchor:find("right") then
            x = mon.x + mon.w - self._cur_w - margin
        else
            x = mon.x + margin
        end
        if anchor:find("bottom") then
            y = mon.y + mon.h - self._cur_h - margin
        else
            y = mon.y + margin
        end
        return x, y
    elseif anchor == "start" then
        local s = self:_read_start_pos()
        local g = self:_read_dock_geo()
        if not s then
            return self:_resolve_anchor({ launcher = { anchor = "dock", gap = gap } })
        end
        local mon_start = nil
        if g and g.monitor and g.monitor ~= "" then
            for _, sc in ipairs(screens.list()) do
                if sc.name == g.monitor then mon_start = sc; break end
            end
        end
        if not mon_start then
            mon_start = resolve_monitor(self.srv, cfg.launcher.monitor or "cursor")
        end
        local x = s.x
        if mon_start then
            local max_x = mon_start.x + mon_start.w - self._cur_w - 2
            if x > max_x then x = max_x end
            if x < mon_start.x then x = mon_start.x end
        end
        local y
        local edge = g and g.edge or "top"
        if edge == "bottom" then
            y = (g and g.y or 0) - self._cur_h - gap
        else
            y = (g and (g.y + g.h) or 0) + gap
        end
        if y < 0 then y = 0 end
        return x, y
    elseif anchor == "free" then
        local pos = cfg.launcher.pos or { x = 0, y = 0 }
        return mon.x + (pos.x or 0), mon.y + (pos.y or 0)
    end
    return nil
end

function M:_compute_position()
    return self:_resolve_anchor(self.config.get())
end

function M:_ensure_window()
    local cfg = self.config.get()
    self._cur_w = (cfg.launcher.size and cfg.launcher.size.w) or DEFAULT_W
    self._cur_h = (cfg.launcher.size and cfg.launcher.size.h) or DEFAULT_H

    local x, y = self:_compute_position()
    if self._win and not self._win.destroyed then
        if x and y then self._win:move(x, y) end
        return self._win
    end

    local T = self.T
    local self_ref = self
    local opts = {
        kind = "menu",
        title = "lane-launcher",
        width  = self._cur_w,
        height = self._cur_h,
        disable_q_close = true,
        backing_store = 2,
        initial_mask_hidden = true,
        on_draw = function(cr, cw, ch)
            local bg  = T.bg_rgb
            local bcg = T.bg_card_rgb
            if not bg or not bcg then
                cairo.set_rgb(cr, 0.04, 0.05, 0.08)
                cairo.paint(cr)
                return
            end
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rounded_rect(cr, 0, 0, cw, ch, RADIUS)
            cairo.fill(cr)
            cairo.set_rgb(cr, bcg[1], bcg[2], bcg[3])
            cairo.rounded_rect(cr, 2, 2, cw - 4, ch - 4, RADIUS - 2)
            cairo.fill(cr)
        end,
        on_focus_in = function()
            if self_ref._tab and self_ref._tab.focus then
                self_ref._tab.focus()
            end
        end,
        on_close = function() end,
    }
    if x then opts.x = x; opts.y = y
    else opts.x = "cursor-screen"; opts.y = "cursor-screen" end
    self._win = Window.new(self.srv, opts)
    self._win_handle = xanim.attach {
        srv = self.srv, win = self._win,
        w = self._cur_w, h = self._cur_h,
        radius = 0, ms = ANIM_MS,
    }
    return self._win
end

function M:do_show()
    if self:is_open() then return end
    self:_ensure_window()

    if not self._win.root then
        local launcher_mod = require("launcher.tab")
        self._tab = launcher_mod.new(self.srv, self.T)
        self._win:set_root(self._tab.widget)
        self._tab.start()
        self._win:damage_all()
        self._win:draw()
        if self._win.cr and self._win.image_surface then
            cairo.save(self._win.cr)
            cairo.set_operator(self._win.cr, cairo.OPERATOR.SOURCE)
            cairo.set_source_surface(self._win.cr, self._win.image_surface, 0, 0)
            cairo.paint(self._win.cr)
            cairo.restore(self._win.cr)
            cairo.flush_surface(self._win.surface)
        end
    end

    self._win:set_input_focus()
    if self._tab and self._tab.focus then self._tab.focus() end
    self._win_handle:show()
    log.info("launcher", "mostrado")
end

function M:do_hide()
    if not self._win_handle or not self._win_handle:visible() then
        return
    end
    if not self._win or self._win.destroyed then
        self._win_handle:reset()
        return
    end
    log.info("launcher", "ocultando")
    pcall(function() self._win:restore_input_focus() end)
    -- Sin srv:stop(): la barra sigue viva. La ventana queda mapeada con
    -- shape vacía; el próximo show() solo hace animate(1).
    self._win_handle:hide(function()
        log.info("launcher", "menu cerrado")
    end)
end

function M:show()
    self:do_show()
end

function M:hide()
    self:do_hide()
end

function M:toggle()
    if self:is_open() then
        local x, y = self:_compute_position()
        if x and self._win and not self._win.destroyed then
            if self._win.x ~= x or self._win.y ~= y then
                log.info("launcher", "reposicionando")
                self:do_hide()
                local tm
                tm = self.srv:add_timer(50, function()
                    tm:cancel()
                    self:do_show()
                end)
                return
            end
        end
        self:do_hide()
    else
        self:do_show()
    end
end

-- Destruye la ventana y el tab. El próximo show() recrea.
-- Llamado por la barra desde config.watch/theme.watch/reload.install.
function M:invalidate()
    if not self._win or self._win.destroyed then return end
    local was_open = self:is_open()
    if was_open then
        self:do_hide()
    end
    local tm
    tm = self.srv:add_timer(80, function()
        tm:cancel()
        if self._win and not self._win.destroyed then
            if self._tab and self._tab.stop then
                pcall(function() self._tab.stop() end)
            end
            self._win:close("invalidate")
        end
        self._win        = nil
        self._win_handle = nil
        self._tab        = nil
    end)
end

return M

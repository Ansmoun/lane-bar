local Server   = require("lib.server")
local Window   = require("lib.window")
local theme    = require("lib.theme")
local screens  = require("lib.screens")
local cairo    = require("lib.cairo")
local log      = require("lib.log")
local reload   = require("lib.reload")
local anim     = require("lib.anim")
local geometry = require("bar.geometry")
local engine   = require("bar.engine")
local widgets  = require("bar.widgets")
local styles_mod = require("bar.styles")
local xanim      = require("lib.xshape_anim")
local session    = require("lib.session")   -- [SESSION]
local config   = require("lib.config")

local SPEC_PATH = "layout.lua"

local srv = Server.new { exit_on_empty = false }
anim.init(srv, { fps = 30 })

-- [SESSION] Bus de estado compartido con otros satelites LANE.
-- Publica "dock" (geometria) y consulta "launcher" (open/closed).
local sess = session.new(srv, "lane-bar")

local T = theme.load()
log.info("bar", "paleta: %s", T.path)

local SPEC = dofile(SPEC_PATH)
if type(SPEC) ~= "table" then
    log.error("bar", "layout.lua no devolvio tabla")
    os.exit(1)
end

local function pick_primary_screen()
    local list = screens.list()
    for _, s in ipairs(list) do
        if s.name == "VGA-1" then return s end
    end
    return list[1]
end
-- Se resuelve en rebuild() segun config.bar.monitor.
local mon = nil

local ewmh_mod = require("lib.ewmh")
local xcb      = require("lib.xcb")

-- Resuelve el monitor segun config.bar.monitor:
--   "cursor"   -> monitor bajo el mouse (default)
--   "primary"  -> VGA-1 si existe, si no el primero
--   "focused"  -> monitor con el escritorio activo (via bspc)
--   "<name>"   -> monitor con ese nombre (ej "VGA-1", "LVDS-1")
local function resolve_monitor(name)
    name = name or "cursor"
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
            local mname = h:read("*l")
            h:close()
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
        log.warn("bar", "monitor desconocido en config: %s", tostring(name))
        return pick_primary_screen()
    end
end


local bar_win, bar_data, bar_starts, bar_stops
local stopping = false

local ewmh_inst = ewmh_mod.new(srv)

local function detect_super_keycode()
    local h = io.popen("xmodmap -pk 2>/dev/null | grep -E 'Super_L|Super_R' | head -1 | awk '{print $1}'")
    if h then
        local k = tonumber(h:read("*l"))
        h:close()
        if k then return k end
    end
    return 133
end
local super_code = detect_super_keycode()

local _smart_active = false
local _smart_timer  = nil
local _follow_timer = nil
local bar_handle    = nil

-- Seguidor de puntero: el dock vive en el monitor donde esta el
-- mouse. Debounce de 200ms para evitar vibracion cuando el cursor
-- oscila sobre el borde entre monitores.
local current_mon   = nil
local pending_mon   = nil
local pending_since = 0
local bar_spec      = nil
local bar_geo       = nil
local FOLLOW_MS     = 250
local DEBOUNCE_MS   = 200

-- Devuelve true si hay ventanas en el monitor donde vive el dock.
--
-- Se usa bspc en vez de EWMH porque _NET_CURRENT_DESKTOP es global:
-- con dos monitores apilados, el "workspace activo" de EWMH es el
-- del monitor con foco, no el del dock. Consultar EWMH daba falsos
-- positivos y el dock no se ocultaba al cambiar de pantalla.
--
-- bspc query -N -m <mon> -n '.leaf' devuelve los window ids de las
-- hojas del arbol de ese monitor. Si hay al menos una, hay ventana.
local function has_windows_on_dock_monitor()
    if not current_mon then return false end
    local h = io.popen(
        "bspc query -N -m " .. current_mon.name ..
        " -n '.leaf' 2>/dev/null")
    if not h then
        -- Fallback: si bspc no esta, mostrar (no ocultar por las dudas).
        return false
    end
    local any = false
    for _ in h:lines() do any = true; break end
    h:close()
    return any
end

-- [SESSION] Consulta session.launcher.open. Retrocompat: el archivo
-- /tmp/lane-launcher-open sigue vigente hasta que launcher Fase 1c
-- lo deprecie; ambos canales coexisten.
local function launcher_open_by_session()
    local l = sess:get("launcher")
    return l and l.open == true
end

local function wants_visible()
    if not _smart_active then return true end
    -- El launcher escribe este archivo mientras esta abierto. Se
    -- fuerza el dock visible para que el launcher tenga su base
    -- y el reveal se sienta como si saliera del dock.
    local f = io.open("/tmp/lane-launcher-open", "r")
    if f then f:close() return true end
    -- [SESSION] Canal nuevo.
    if launcher_open_by_session() then return true end
    local km = xcb.query_keymap(srv.conn)
    if km and xcb.key_pressed(km, super_code) then return true end
    return not has_windows_on_dock_monitor()
end

local function apply_visibility()
    if not bar_win or bar_win.destroyed then return end
    if not bar_handle then return end
    if not _smart_active then
        bar_handle:show()
        return
    end
    if wants_visible() then
        local was = bar_handle:visible()
        bar_handle:show()
        if not was then
            xcb.configure_window(srv.conn, bar_win.id,
                xcb.CONFIG.Stack, { stack = 0 })
            xcb.flush(srv.conn)
        end
    else
        bar_handle:hide()
    end
end

-- [SESSION] Firma local de la ultima geometria publicada, para
-- evitar writes redundantes al JSON (que bumpearian _gen y harian
-- despertar de mas al poll de 200ms de los otros clientes).
local _last_published = nil

local function write_dock_geometry(geo)
    local mon_name = current_mon and current_mon.name or ""
    local key = string.format("%d:%d:%d:%d:%s:%s",
        geo.x, geo.y, geo.w, geo.h, mon_name,
        geo.position or "")
    if _last_published == key then return end
    _last_published = key

    -- Retrocompat: launcher (y cualquier consumidor externo) sigue
    -- leyendo este archivo mientras dure la transicion.
    local gf = io.open("/tmp/lane-dock-geometry", "w")
    if gf then
        gf:write(string.format("%d %d %d %d\n",
            geo.x, geo.y, geo.w, geo.h))
        gf:close()
    end

    -- [SESSION] Canal nuevo.
    sess:set("dock", {
        present = true,
        x = geo.x, y = geo.y,
        w = geo.w, h = geo.h,
        monitor = mon_name ~= "" and mon_name or nil,
        edge    = geo.position,
    })
end

local function follow_pointer()
    local cfg = config.get()
    if not cfg.bar.follow_cursor then return end

    if not bar_win or bar_win.destroyed then return end
    if not current_mon or not bar_spec then return end

    local cx, cy = xcb.query_pointer(srv.conn)
    if not cx then return end

    local new_mon = screens.at(cx, cy)
    if not new_mon then return end

    if new_mon.name == current_mon.name then
        pending_mon = nil
        return
    end

    if not pending_mon or pending_mon.name ~= new_mon.name then
        pending_mon   = new_mon
        pending_since = xcb.now_ms()
        return
    end

    if xcb.now_ms() - pending_since < DEBOUNCE_MS then return end

    -- Aplicar move.
    local geo = geometry.compute(bar_spec, new_mon)
    bar_win:move(geo.x, geo.y)
    bar_geo     = geo
    current_mon = new_mon
    pending_mon = nil

    xcb.configure_window(srv.conn, bar_win.id,
        xcb.CONFIG.Stack, { stack = 0 })
    xcb.flush(srv.conn)
    write_dock_geometry(geo)

    log.info("bar", "dock movido a %s (%dx%d+%d+%d)",
        new_mon.name, geo.w, geo.h, geo.x, geo.y)
end

local function stop_widgets()
    if bar_stops then
        for _, stop in ipairs(bar_stops) do
            pcall(stop)
        end
    end
    bar_starts, bar_stops = nil, nil
end

local function build_strut(geo)
    local s = { left = 0, right = 0, top = 0, bottom = 0 }
    local p = geo.position
    if p == "top"    then s.top    = geo.h end
    if p == "bottom" then s.bottom = geo.h end
    if p == "left"   then s.left   = geo.w end
    if p == "right"  then s.right  = geo.w end
    return s
end

-- Claves de geometria: las define el estilo. El SPEC solo aporta
-- contenido (left, center, right, gap, style). Para forzar
-- geometria del usuario, usar SPEC.geometry = {...}.
local GEO_KEYS = {
    position = true, width = true, height = true,
    margin = true, x = true, y = true,
}

local function effective_spec(spec, style_mod)
    local out = {}
    for k, v in pairs(style_mod.defaults or {}) do out[k] = v end
    for k, v in pairs(spec or {}) do
        if not GEO_KEYS[k] then out[k] = v end
    end
    for k, v in pairs(spec.geometry or {}) do out[k] = v end
    return out
end

local function teardown_bar()
    if bar_win and not bar_win.destroyed then
        bar_win:close("disabled")
        bar_win = nil
    end
    stop_widgets()
    if _smart_timer then _smart_timer:cancel(); _smart_timer = nil end
    if _follow_timer then _follow_timer:cancel(); _follow_timer = nil end
    bar_handle = nil
    bar_data   = nil
    bar_spec   = nil
    bar_geo    = nil
end

local function publish_dock_absent()
    sess:set("dock", { present = false })
end

local function rebuild()
    local cfg = config.get()

    if not cfg.bar.enabled then
        teardown_bar()
        publish_dock_absent()
        _last_published = nil
        _smart_active = false
        log.info("bar", "deshabilitada por config")
        return
    end

    if bar_win and not bar_win.destroyed then
        bar_win:close("rebuild")
        bar_win = nil
    end
    stop_widgets()

    mon = resolve_monitor(cfg.bar.monitor)

    local style_mod = styles_mod.get(SPEC.style or "arrow")
    local eff_spec  = effective_spec(SPEC, style_mod)
    local geo = geometry.compute(eff_spec, mon)
    local bar = engine.build(T, eff_spec, widgets, srv)

    local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
    local bg_pixel = math.floor(bg[1] * 255) * 0x10000
                   + math.floor(bg[2] * 255) * 0x100
                   + math.floor(bg[3] * 255)
    bar_win = Window.new(srv, {
        kind = "dock",
        override_redirect = style_mod.override_redirect,
        title = "lane-bar",
        width  = geo.w, height = geo.h,
        x = geo.x, y = geo.y,
        disable_q_close = true,
        strut = build_strut(geo),
        background_pixel = bg_pixel,
        on_draw = function(cr, w, h)
            if style_mod.draw_bg then
                style_mod.draw_bg(cr, w, h, T)
            else
                cairo.set_rgb(cr, T.bg_rgb[1], T.bg_rgb[2], T.bg_rgb[3])
                cairo.paint(cr)
                cairo.set_rgb(cr, T.separator_rgb[1], T.separator_rgb[2], T.separator_rgb[3])
                cairo.rectangle(cr, 0, h - 1, w, 1)
                cairo.fill(cr)
            end
        end,
        on_close = function()
            if not stopping then stop_widgets() end
        end,
    })
    bar_win:set_root(bar.widget)
    bar_data = bar
    bar_starts = bar.starts
    bar_stops  = bar.stops

    _smart_active = (style_mod.visibility == "smart")
    bar_spec = eff_spec
    bar_geo  = geo
    current_mon = mon
    pending_mon = nil
    bar_handle = nil
    if style_mod.rounded and os.getenv("LANETK_NO_SHAPE") ~= "1" then
        local rr = style_mod.rounded.radius
        local radius = (rr == "pill") and math.floor(geo.h / 2) or (rr or 0)
        bar_handle = xanim.attach {
            srv = srv, win = bar_win,
            w = geo.w, h = geo.h,
            radius = radius, ms = 220,
        }
    end
    apply_visibility()
    if _smart_timer then _smart_timer:cancel() end
    _smart_timer = srv:add_timer(120, function()
        if _smart_active then apply_visibility() end
    end)

    if _follow_timer then _follow_timer:cancel(); _follow_timer = nil end
    if cfg.bar.follow_cursor then
        _follow_timer = srv:add_timer(FOLLOW_MS, function()
            follow_pointer()
        end)
    end

    for _, start in ipairs(bar_starts) do
        local ok, err = pcall(start)
        if not ok then log.warn("bar", "start fallo: %s", tostring(err)) end
    end

    -- Compartir geometria con otros daemons (launcher) para
    -- anclarse encima del dock.
    write_dock_geometry(geo)

    log.info("bar", "%s %dx%d+%d+%d sep=%s widgets=%d",
        geo.position, geo.w, geo.h, geo.x, geo.y,
        bar.sep_style, #bar_starts)
end

config.watch(srv, function()
    log.info("bar", "config cambio, rebuild")
    rebuild()
end)

theme.watch(rebuild)
reload.install(srv, function()
    log.info("bar", "SIGUSR1: recargando paleta")
    theme.reload_in_place(T)
    rebuild()
end)

srv:watch_trigger("/tmp/lane-bar.cmd", function(cmd)
    log.info("bar", "trigger: %s", cmd)
    local style_name = cmd:match("^style%s+(%S+)$")
    if style_name then
        if styles_mod[style_name] then
            SPEC.style = style_name
            rebuild()
        else
            log.warn("bar", "estilo desconocido: %s", style_name)
        end
    elseif cmd == "reload" then
        rebuild()
    elseif cmd == "quit" then
        srv:stop()
    end
end)

rebuild()
log.info("bar", "listo")
srv:run()

stopping = true
stop_widgets()
-- [SESSION] Despublicar y desregistrar el cliente.
sess:clear("dock")
sess:close()
log.info("bar", "adios")

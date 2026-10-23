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
local bar_themes = require("themes")
local unix_socket = require("lib.unix_socket")
local Icons     = require("lib.icons")

-- Encuentra la raíz de LANE (donde vive icons-src/). Orden:
--   $LANE_ROOT  ->  /opt/lane  ->  ~/proyectos/lane
-- Necesario para que Icons resuelva iconos propios de LANE (como
-- "start") que no viven en el toolkit.
local function resolve_lane_root()
    local env = os.getenv("LANE_ROOT")
    if env and env ~= "" then
        local h = io.popen("test -d '" .. env .. "/icons-src' && echo yes")
        if h then
            local ok = h:read("*l"); h:close()
            if ok == "yes" then return env end
        end
    end
    local home = os.getenv("HOME") or ""
    for _, p in ipairs({ "/opt/lane", home .. "/proyectos/lane" }) do
        local h = io.popen("test -d '" .. p .. "/icons-src' && echo yes")
        if h then
            local ok = h:read("*l"); h:close()
            if ok == "yes" then return p end
        end
    end
    return nil
end
local xanim      = require("lib.xshape_anim")
local config   = require("lib.config")
local Launcher = require("launcher")

local SPEC_PATH = "layout.lua"

local srv = Server.new { exit_on_empty = false }
anim.init(srv, { fps = 60 })

-- [SESSION] Bus de estado compartido con otros satelites LANE.
-- Publica "dock" (geometria) y consulta "launcher" (open/closed).

local T = theme.load()

-- Apuntar Icons a la raíz de LANE para iconos propios (start, etc).
do
    local lane_root = resolve_lane_root()
    if lane_root then
        Icons.set_root(lane_root)
    else
        log.warn("bar", "no se encontró icons-src de LANE")
    end
end
log.info("bar", "paleta: %s", T.path)

-- Carga del tema: reemplaza el dofile("layout.lua") por el loader
-- del sistema de temas. Si config.bar.theme no existe o falla, cae
-- al tema "dock" (que reproduce el layout previo).
local SPEC, spec_theme_name = bar_themes.load()
log.info("bar", "tema: %s", spec_theme_name)
if type(SPEC) ~= "table" then
    log.error("bar", "layout.lua no devolvio tabla")
    os.exit(1)
end

local function pick_primary_screen()
    -- Consultar el primario real de xrandr, no asumir VGA-1.
    local h = io.popen(
        "xrandr --query 2>/dev/null | grep ' primary ' | head -1 | awk '{print $1}'")
    if h then
        local name = h:read("*l")
        h:close()
        if name and name ~= "" then
            for _, s in ipairs(screens.list()) do
                if s.name == name then return s end
            end
        end
    end
    -- Fallback: primer monitor conectado.
    local list = screens.list()
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
local launcher = nil            -- controlador del launcher embebido
local start_absolute_pos        -- forward decl, se define abajo

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

local function wants_visible()
    if not _smart_active then return true end
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

-- bspwm no honra _NET_WM_STRUT de ventanas override_redirect con
-- _NET_WM_WINDOW_TYPE_DOCK (deja el rect del monitor completo).
-- Aplicamos el padding vía bspc config, que sí es respetado por el
-- tileo. Se resetean los 4 lados antes de aplicar el nuevo, para
-- que un cambio de borde (top→bottom) no deje padding huérfano.
local _last_padding = nil
local function apply_bspc_padding(geo)
    if not current_mon then return end
    local edge = geo.position or "top"
    local value = (edge == "left" or edge == "right")
                  and geo.w or geo.h
    local key = current_mon.name .. ":" .. edge .. ":" .. value
    if _last_padding == key then return end
    _last_padding = key
    local mon = current_mon.name
    -- Resetear los cuatro lados y aplicar el nuevo.
    os.execute(string.format(
        "bspc config -m %s top_padding 0; "
        .. "bspc config -m %s bottom_padding 0; "
        .. "bspc config -m %s left_padding 0; "
        .. "bspc config -m %s right_padding 0; "
        .. "bspc config -m %s %s_padding %d",
        mon, mon, mon, mon, mon, edge, value) .. " >/dev/null 2>&1 &")
end

local function clear_bspc_padding()
    if not current_mon then return end
    _last_padding = nil
    local mon = current_mon.name
    os.execute(string.format(
        "bspc config -m %s top_padding 0; "
        .. "bspc config -m %s bottom_padding 0; "
        .. "bspc config -m %s left_padding 0; "
        .. "bspc config -m %s right_padding 0",
        mon, mon, mon, mon) .. " >/dev/null 2>&1 &")
end

local function write_dock_geometry(geo)
    local mon_name = current_mon and current_mon.name or ""
    local key = string.format("%d:%d:%d:%d:%s:%s",
        geo.x, geo.y, geo.w, geo.h, mon_name,
        geo.position or "")
    if _last_published == key then return end
    _last_published = key

    apply_bspc_padding(geo)
end

local function follow_pointer()
    local cfg = config.get()
    if not resolve_follow_cursor(cfg) then return end

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

-- Construye el spec efectivo del tema aplicando los overrides de
-- config.bar. Si el usuario no definió ninguno (position/height/
-- margin todos nil), devuelve el tema tal cual. Si definió alguno,
-- los mezcla sobre SPEC.geometry sin mutar el SPEC original.
local function build_spec()
    local cfg = config.get()
    local base = SPEC
    local over = {}
    if cfg.bar.position then over.position = cfg.bar.position end
    if cfg.bar.height   then over.height   = cfg.bar.height   end
    if cfg.bar.margin   then over.margin   = cfg.bar.margin   end
    if next(over) == nil then return base end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    out.geometry = {}
    for k, v in pairs(base.geometry or {}) do out.geometry[k] = v end
    for k, v in pairs(over) do out.geometry[k] = v end
    return out
end

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

-- Cascada de política para follow_cursor y monitor:
--   config.bar.X  >  tema.X  >  default histórico
--
-- El config permite nil (usa el tema). El tema puede omitir el
-- campo (usa el default histórico: true y "cursor").
local function resolve_follow_cursor(cfg)
    if cfg.bar.follow_cursor ~= nil then return cfg.bar.follow_cursor end
    if SPEC.follow_cursor ~= nil then return SPEC.follow_cursor end
    return true
end

local function resolve_monitor_name(cfg)
    if cfg.bar.monitor and cfg.bar.monitor ~= "" then
        return cfg.bar.monitor
    end
    if SPEC.monitor and SPEC.monitor ~= "" then return SPEC.monitor end
    return "cursor"
end

local function rebuild()
    local cfg = config.get()

    if not cfg.bar.enabled then
        teardown_bar()
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

    mon = resolve_monitor(resolve_monitor_name(cfg))

    local style_mod = styles_mod.get(SPEC.style or "arrow")
    -- El tema puede sobreescribir el draw_bg del estilo. Útil para
    -- temas que quieren un fondo distinto sin duplicar el estilo.
    local theme_draw_bg = SPEC.draw_bg
    local eff_spec  = effective_spec(build_spec(), style_mod)
    local geo = geometry.compute(eff_spec, mon)
    local bar = engine.build(T, eff_spec, widgets, srv, { ewmh = ewmh_inst, launcher = launcher })

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
            local draw_bg_fn = theme_draw_bg or style_mod.draw_bg
            if draw_bg_fn then
                draw_bg_fn(cr, w, h, T)
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
    if resolve_follow_cursor(cfg) then
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
    -- Recargar el tema ANTES de rebuild. Sin esto, SPEC queda con
    -- el tema cargado al arrancar el daemon: si el usuario cambia
    -- config.bar.theme en caliente, rebuild() usa el SPEC viejo.
    log.info("bar", "config cambio, recargando tema")
    local ok, new_spec, name = pcall(bar_themes.load)
    if ok and type(new_spec) == "table" then
        SPEC = new_spec
        log.info("bar", "tema recargado: %s", tostring(name))
    else
        log.warn("bar", "recarga de tema fallo: %s", tostring(new_spec))
    end
    rebuild()
    if launcher then launcher:invalidate() end
end)

theme.watch(function() rebuild(); if launcher then launcher:invalidate() end end)
reload.install(srv, function()
    log.info("bar", "SIGUSR1: recargando paleta")
    theme.reload_in_place(T)
    rebuild()
    if launcher then launcher:invalidate() end
end)

launcher = Launcher.new {
    srv = srv,
    T   = T,
    config = config,
    bar_state = {
        geo = function()
            if not bar_geo or not current_mon then return nil end
            return {
                x = bar_geo.x, y = bar_geo.y,
                w = bar_geo.w, h = bar_geo.h,
                position = bar_geo.position,
                monitor  = current_mon.name,
            }
        end,
        start_pos = function()
            if not start_absolute_pos then return nil end
            return start_absolute_pos()
        end,
    },
}

rebuild()
-- ─── Socket para otros satélites ────────────────────────────────
-- Expone consultas read-only sobre el estado de la barra. Lo usa
-- el launcher para anclarse al widget start sin necesidad de
-- session.json ni archivos temporales.
--
-- Protocolo: una línea de comando por conexión, respuesta de una
-- línea. Comandos:
--   ping            -> "pong"
--   dock-geo        -> "x y w h edge monitor"
--   start-pos       -> "x y w h" (coordenadas ROOT)
local SOCK_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp")
                  .. "/lane-bar.sock"

start_absolute_pos = function()
    if not bar_data or not bar_geo then return nil end
    local inst = bar_data.instances and bar_data.instances.start
    if not inst or not inst.widget then return nil end
    local w = inst.widget
    -- Los x0/y0 del widget son relativos al padre (0,0 es la
    -- esquina superior izquierda del client area de la ventana).
    -- Sumar bar_geo.x / bar_geo.y da coordenadas root absolutas.
    local x = bar_geo.x + (w.x0 or 0)
    local y = bar_geo.y + (w.y0 or 0)
    local sw = (w.x1 or 0) - (w.x0 or 0)
    local sh = (w.y1 or 0) - (w.y0 or 0)
    if sw <= 0 or sh <= 0 then return nil end
    return x, y, sw, sh
end

local _sock = unix_socket.server {
    srv  = srv,
    path = SOCK_PATH,
    handler = function(cmd, args)
        if cmd == "ping" then
            return "pong"
        elseif cmd == "dock-geo" then
            if not bar_geo then return "0 0 0 0 none none" end
            return string.format("%d %d %d %d %s %s",
                bar_geo.x or 0, bar_geo.y or 0,
                bar_geo.w or 0, bar_geo.h or 0,
                bar_geo.position or "top",
                current_mon and current_mon.name or "none")
        elseif cmd == "start-pos" then
            local x, y, w, h = start_absolute_pos()
            if not x then return "0 0 0 0" end
            return string.format("%d %d %d %d", x, y, w, h)
        elseif cmd == "reload" then
            rebuild()
            return "ok"
        elseif cmd == "quit" then
            srv:stop()
            return "bye"
        elseif cmd == "toggle-launcher" then
            if launcher then launcher:toggle(); return "ok" end
            return nil, "launcher no inicializado"
        elseif cmd == "show-launcher" then
            if launcher then launcher:show(); return "ok" end
            return nil, "launcher no inicializado"
        elseif cmd == "hide-launcher" then
            if launcher then launcher:hide(); return "ok" end
            return nil, "launcher no inicializado"
        elseif cmd == "style" then
            if args and args ~= "" and styles_mod[args] then
                SPEC.style = args
                rebuild()
                return "ok"
            end
            return nil, "estilo desconocido: " .. tostring(args)
        end
        return nil, "unknown command: " .. tostring(cmd)
    end,
}

log.info("bar", "listo")
srv:run()

stopping = true
stop_widgets()
clear_bspc_padding()
log.info("bar", "adios")

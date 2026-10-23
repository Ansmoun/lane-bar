-- tab.lua: controlador del launcher.
--
-- Responsabilidades:
--   - Estado (query, sección activa, selección).
--   - Datos (scan, búsqueda, agrupación por categoría).
--   - Máquina de teclado y navegación.
--   - Lifecycle de timers.
--
-- NO dibuja, NO conoce Cairo, NO construye widgets. Todo eso vive
-- en themes/<name>.lua, cargado vía lib.config.launcher.theme.
--
-- Contrato con el tema (ver themes/init.lua):
--   tema expone  M.build(ctx) -> handle
--   handle = { widget, focus?, start?, stop?,
--              update_results?, update_selection?, update_section? }
--
-- El controlador llama update_* cada vez que el estado cambia.
-- El tema llama ctx.on_* cuando el usuario interactúa.

local log    = require("lib.log")
local D      = require("lib.data.launcher")
local Cat    = require("lib.data.categories")
local Icons  = require("lib.icons")
local themes = require("launcher.themes")

local M = {}

-- Encuentra la raíz de LANE (donde vive icons-src/). Orden:
--   $LANE_ROOT  ->  /opt/lane  ->  ~/proyectos/lane
local function resolve_lane_root()
    local ffi = require("ffi")
    pcall(ffi.cdef, [[
        typedef struct lanetk_dir DIR;
        DIR *opendir(const char *name);
        int closedir(DIR *dirp);
    ]])
    local function dir_exists(p)
        if not p or p == "" then return false end
        local d = ffi.C.opendir(p)
        if d == nil then return false end
        ffi.C.closedir(d)
        return true
    end

    local env = os.getenv("LANE_ROOT")
    if env and env ~= "" and dir_exists(env .. "/icons-src") then
        return env
    end
    local home = os.getenv("HOME") or ""
    for _, p in ipairs({ "/opt/lane", home .. "/proyectos/lane" }) do
        if dir_exists(p .. "/icons-src") then return p end
    end
    return nil
end

function M.new(srv, palette)
    -- Apuntar Icons al root de LANE para que el tema pueda resolver
    -- los iconos tab-*.svg del sidebar.
    local lane_root = resolve_lane_root()
    if lane_root then
        Icons.set_root(lane_root)
    else
        log.warn("launcher", "no se encontró icons-src de LANE")
    end

    -- ─── Estado ──────────────────────────────────────────────────
    local st = {
        query    = "",
        section  = "recientes",
        groups   = nil,        -- { order = {...}, [id] = { entries } }
        results  = {},         -- items de la lista actual
        selected = 1,
    }

    -- ─── Datos iniciales ─────────────────────────────────────────
    -- D.all_entries() internamente hace ensure_cache() que dispara
    -- M.scan() si no hay cache. NO llamar D.scan() explícito acá:
    -- duplicaba el scan (3 ls -1 extra en cada boot).
    local all  = D.all_entries()
    local hist = D.history_top(20)
    st.groups = Cat.group(all, hist)
    if not st.groups[st.section] or #st.groups[st.section] == 0 then
        st.section = st.groups.order[1] or "todas"
    end

    -- ─── Forward declarations ────────────────────────────────────
    local handle                          -- handle devuelto por el tema
    local last_query, last_section = nil, nil
    local refresh_results

    -- ─── Contexto para el tema ───────────────────────────────────
    local ctx = {
        srv     = srv,
        st      = st,
        palette = palette,

        -- Input del usuario.
        on_query_change = function(text)
            st.query = text or ""
            refresh_results()
        end,

        -- Sidebar.
        on_section_click = function(id)
            if not id or st.section == id then return end
            st.section = id
            refresh_results()
            if handle and handle.update_section then handle.update_section() end
        end,

        -- Navegación ↑↓.
        on_move_selection = function(delta)
            local n = #st.results
            if n == 0 then return end
            local ns = st.selected + delta
            if ns < 1 then ns = 1 end
            if ns > n then ns = n end
            if ns == st.selected then return end
            st.selected = ns
            if handle and handle.update_selection then handle.update_selection() end
        end,

        -- Navegación ←→ (secciones).
        on_move_section = function(delta)
            if st.query ~= "" then return end
            local order = st.groups.order
            for i, sid in ipairs(order) do
                if sid == st.section then
                    local ni = i + delta
                    if ni >= 1 and ni <= #order then
                        ctx.on_section_click(order[ni])
                    end
                    return
                end
            end
        end,

        -- Ejecutar una app (o comando). El tema llama esto desde
        -- on_submit / on_click del item. El cierre de la ventana es
        -- responsabilidad del tema (tiene la referencia al window).
        execute = function(entry)
            if entry then D.execute(entry) end
        end,

        -- Resolución de iconos (cacheada en data/launcher).
        get_icon_path = function(entry)
            if not entry then return nil end
            if entry._icon_path then return entry._icon_path end
            if entry.icon and entry.icon ~= "" then
                entry._icon_path = D.find_icon(entry.icon)
            end
            return entry._icon_path
        end,
    }

    -- ─── refresh_results: recálculo tras cambio de query/sección ─
    refresh_results = function()
        local _t0 = os.clock()
        if st.query == last_query and st.section == last_section then
            return
        end
        last_query, last_section = st.query, st.section

        if st.query == "" then
            st.results = st.groups[st.section] or {}
        else
            st.results = D.search(st.query)
        end

        -- Pre-resolver iconos para la lista visible.
        for _, e in ipairs(st.results) do
            if not e._icon_path and e.icon and e.icon ~= "" then
                e._icon_path = D.find_icon(e.icon)
            end
        end

        local _dt = os.clock() - _t0
        if _dt > 0.005 then
            log.info("launcher", "refresh seccion=%s query='%s' items=%d tomó %.1fms",
                st.section, st.query, #st.results, _dt * 1000)
        end

        st.selected = 1
        if handle and handle.update_results then handle.update_results() end
    end

    -- ─── Cargar tema y construir la vista ────────────────────────
    local theme_mod, theme_name = themes.load()
    log.info("launcher", "tema: %s", theme_name)
    handle = theme_mod.build(ctx)

    -- Primer cálculo, para que el tema vea datos en su primer draw.
    refresh_results()

    -- ─── Devolver handle al entry point ──────────────────────────────
    local poll

    return {
        widget = handle.widget,
        focus  = handle.focus or function() end,
        start  = function()
            if handle.start then handle.start() end

            -- Prewarm de iconos: recolectar los paths de todas las
            -- secciones y encolarlos en el tema. El tema los carga
            -- de a pocos por tick, sin bloquear el server.
            do
                local paths = {}
                for _, sid in ipairs(st.groups.order) do
                    for _, e in ipairs(st.groups[sid] or {}) do
                        if e._icon_path then
                            paths[#paths + 1] = e._icon_path
                        elseif e.icon and e.icon ~= "" then
                            local p = D.find_icon(e.icon)
                            if p then
                                e._icon_path = p
                                paths[#paths + 1] = p
                            end
                        end
                    end
                end
                if handle.warm_icons and #paths > 0 then
                    handle.warm_icons(paths)
                end
            end
            -- El poll re-chequea si algo cambió externamente (por
            -- ejemplo, si el tema modifica st.query desde fuera).
            -- refresh_results es idempotente: si nada cambió, sale.
            poll = srv:add_timer(80, function()
                refresh_results()
            end)
        end,
        stop = function()
            if poll then poll:cancel(); poll = nil end
            if handle.stop then handle.stop() end
        end,
    }
end

return M

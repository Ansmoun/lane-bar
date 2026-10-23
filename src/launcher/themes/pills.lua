-- themes/pills.lua: tema tipo Raycast / Spotlight.
--
-- Layout: input arriba, fila de pills horizontales (categorías) y
-- lista plana abajo. Sin sidebar. Una columna, mucho aire.
--
--   ┌─────────────────────────────────────────────┐
--   │   🔍  Buscar aplicaciones...                │
--   ├─────────────────────────────────────────────┤
--   │   Recientes  ·  Todas  ·  Juegos  ·  ...    │  ← pills
--   ├─────────────────────────────────────────────┤
--   │   🦊  Firefox                                │
--   │        Navegador web                         │
--   │   ⌨   Terminal                               │
--   │        Emulador de terminal                  │
--   │                                              │
--   ├─────────────────────────────────────────────┤
--   │                          20 resultados       │
--   └─────────────────────────────────────────────┘

local W      = require("lib.widgets")
local G      = require("lib.helpers.graphics")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local svg    = require("lib.svg")
local Icons  = require("lib.icons")
local Area   = require("lib.area")
local Cat    = require("lib.data.categories")

local M = {}

local ROW_H         = 52
local PAD_H         = 12
local PAD_V         = 10
local CONTENT_PAD_H = 16
local PILL_H        = 28
local PILL_PAD_X    = 10
local PILL_GAP      = 6
local PILL_ICON     = 16

function M.build(ctx)
    local st    = ctx.st
    local theme = ctx.palette

    -- ─── Pills de sección ────────────────────────────────────────
    --
    -- Cada pill dibuja icono + label. El activo lleva fondo accent
    -- (alpha 0.15) y borde accent. Hover sutil.

    -- Instanciar PillBar del toolkit con las secciones del launcher.
    -- El widget se encarga del layout, la animación de expansión y
    -- los handlers de mouse. El tema solo provee la lista de items
    -- y el callback de click.

    local pill_items = {}
    for _, sid in ipairs(st.groups.order) do
        local s = Cat.get(sid)
        if s then
            pill_items[#pill_items + 1] = {
                id    = sid,
                label = s.label,
                icon  = s.icon,
            }
        end
    end

    local pills_bar = W.PillBar.new {
        theme     = theme,
        items     = pill_items,
        active_id = st.section,
        align     = "left",
        spacing   = 4,
        pad_x     = 10,
        gap_icon  = 8,
        icon_size = 16,
        row_h     = 28,
        font      = "DejaVu Sans 10",
        expand_ms = 180,
        on_click  = function(id) ctx.on_section_click(id) end,
    }

    -- ─── Input ───────────────────────────────────────────────────

    local input
    input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 14",
        padding_x = 16, padding_y = 10,
        min_height = 44,
        color_bg = theme.bg_focus,
        color_border = nil,
        corner_radius = 22,
        color_text = theme.fg_rgb,
        placeholder = "Buscar aplicaciones...",
        color_placeholder = theme.muted_rgb,
        on_change = function(text) ctx.on_query_change(text) end,
        on_submit = function()
            input:set_focused(false)
            local e = st.results[st.selected]
            if e then
                ctx.execute(e)
                if input.window then input.window:close("lanzado") end
            end
        end,
        on_cancel = function()
            if input.window then input.window:close("escape") end
        end,
        on_up   = function() ctx.on_move_selection(-1) end,
        on_down = function() ctx.on_move_selection(1)  end,
        on_left = function() ctx.on_move_section(-1)   end,
        on_right= function() ctx.on_move_section(1)    end,
    }
    input.opts.on_focus_request = function()
        input:set_focused(true)
    end

    local input_wrap = W.Group.new {
        orientation = "horizontal",
        padding = PAD_V,
        children = { { widget = input, weight = 1 } },
    }

    -- ─── ScrollView ──────────────────────────────────────────────

    local list
    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 400,
        min_height = ROW_H * 4,
        on_click = function(item)
            if item then
                ctx.execute(item)
                if list.window then list.window:close("launcher ejecutado") end
            end
        end,
    }

    local icon_cache = {}
    local function get_icon_surface(path)
        if not path then return nil end
        local s = icon_cache[path]
        if s ~= nil then return s or nil end
        local ext = (path:match("%.([%w]+)$") or ""):lower()
        local surface
        if ext == "svg" then
            surface = svg.load(path)
        else
            surface = cairo.load_png_cached(path)
        end
        icon_cache[path] = surface or false
        return surface
    end

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end
        local is_sel = (idx == st.selected)

        -- Fondo de fila.
        local row_x = CONTENT_PAD_H - 8
        local row_w = width - 2 * (CONTENT_PAD_H - 8)
        if is_sel then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.10)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 6)
            cairo.fill(cr)
            cairo.set_rgb(cr, r, g, b)
            cairo.rounded_rect(cr, row_x - 2, y + 16, 3, 20, 1.5)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 6)
            cairo.fill(cr)
        end

        -- Icono.
        local icon_size = 32
        local icon_x = CONTENT_PAD_H
        local icon_y = y + (rh - icon_size) / 2
        local surface = get_icon_surface(item._icon_path)
        if surface then
            cairo.draw_surface(cr, surface, icon_x, icon_y, icon_size, icon_size)
        else
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.6)
            cairo.rounded_rect(cr, icon_x, icon_y, icon_size, icon_size, 7)
            cairo.fill(cr)
            local letter = (item.name or "?"):sub(1, 1):upper()
            local r2, g2, b2 = G.hex_to_rgba(theme.fg_normal or "#ebdbb2")
            local lw = pango.measure(letter, "DejaVu Sans Bold 16")
            local _, lh = pango.measure(letter, "DejaVu Sans Bold 16")
            pango.draw_text(cr,
                icon_x + (icon_size - lw) / 2,
                icon_y + (icon_size - lh) / 2,
                letter, "DejaVu Sans Bold 16",
                { r = r2, g = g2, b = b2 })
        end

        -- Texto.
        local text_x = icon_x + icon_size + 14
        local text_w = width - text_x - CONTENT_PAD_H
        local title_color = is_sel and (theme.accent or "#8ec07c")
                            or (theme.fg_normal or "#ebdbb2")
        local r, g, b = G.hex_to_rgba(title_color)
        cairo.save(cr)
        cairo.rectangle(cr, text_x, y, text_w, rh / 2); cairo.clip(cr)
        pango.draw_text(cr, text_x, y + 9, item.name or "?", "DejaVu Sans 12",
            { r = r, g = g, b = b })
        cairo.restore(cr)

        local sub = item.comment or ""
        if item.kind == "command" then sub = "Ejecutar: " .. (item.name or "") end
        if sub ~= "" then
            if #sub > 90 then sub = sub:sub(1, 88) .. "..." end
            local r2, g2, b2 = G.hex_to_rgba(theme.muted or "#928374")
            cairo.save(cr)
            cairo.rectangle(cr, text_x, y + rh / 2, text_w, rh / 2); cairo.clip(cr)
            pango.draw_text(cr, text_x, y + 28, sub, "DejaVu Sans 10",
                { r = r2, g = g2, b = b2 })
            cairo.restore(cr)
        end
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical", width = 10, thickness = 3, handle_r = 4,
        step = ROW_H * 3,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    -- ─── Footer ──────────────────────────────────────────────────

    local footer_count = W.Text.new {
        text = "0 resultados",
        font = "DejaVu Sans 10",
        align = "right", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }
    local function update_footer()
        local n = #st.results
        local text = (n == 1) and "1 resultado" or (n .. " resultados")
        if st.query ~= "" and st.query:sub(1, 1) == ">" then
            text = "comando"
        end
        footer_count:set_text(text)
    end
    local footer_wrap = W.Group.new {
        orientation = "horizontal",
        padding = 8,
        children = { { widget = footer_count, weight = 1 } },
    }

    -- ─── Layout final ────────────────────────────────────────────

    local pills_wrap = W.Group.new {
        orientation = "horizontal",
        padding = 0,
        children = { { widget = pills_bar, weight = 1 } },
    }

    local root = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        children = {
            { widget = input_wrap,  weight = 0 },
            { widget = pills_wrap,  weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 0,
                children = {
                    { widget = list,   weight = 1 },
                    { widget = slider, weight = 0 },
                },
            }, weight = 1 },
            { widget = footer_wrap, weight = 0 },
        },
    }

    -- ─── Handle ──────────────────────────────────────────────────


    -- ─── Prewarm de iconos en background ─────────────────────────
    --
    -- Recibe una lista de paths, los carga de a 2 por tick de
    -- 33ms (~60 iconos/s). Sin esto, la primera vez que entrás a
    -- una sección hay que cargar N SVGs de golpe, y mientras el
    -- server está bloqueado en la carga los timers de animación
    -- no corren: el salto de la sección se ve brusco.

    local warm_state = nil

    local function warm_step()
        if not warm_state then return end
        local n = 0
        while n < 2 and warm_state.idx <= #warm_state.queue do
            get_icon_surface(warm_state.queue[warm_state.idx])
            warm_state.idx = warm_state.idx + 1
            n = n + 1
        end
        if list.window then
            list.window:add_damage(list.x0, list.y0, list.x1, list.y1)
        end
        if warm_state.idx > #warm_state.queue then
            warm_state.timer:cancel()
            warm_state = nil
        end
    end
    return {
        widget = root,

        focus = function()
            if input.window then
                input.window:set_focus_widget(input)
            end
        end,

        update_results = function()
            update_footer()
            list:set_items(st.results)
            list.offset = 0
            list.hover_idx = -1
            if list.window then list.window:damage_all() end
        end,

        update_selection = function()
            if list.window then
                local off = list:get_offset()
                local vh  = list:getHeight()
                if vh > 0 then
                    local first   = math.floor(off / ROW_H)
                    local visible = math.max(1, math.floor(vh / ROW_H))
                    local last    = first + visible - 1
                    local sel0    = st.selected - 1
                    if sel0 < first then
                        list:set_offset(sel0 * ROW_H)
                    elseif sel0 > last then
                        list:set_offset((sel0 - visible + 1) * ROW_H)
                    end
                end
                list.window:damage_all()
            end
        end,

        warm_icons = function(paths)
            if warm_state then
                warm_state.timer:cancel()
                warm_state = nil
            end
            if not paths or #paths == 0 then return end
            warm_state = {
                queue = paths,
                idx = 1,
                timer = ctx.srv:add_timer(33, warm_step),
            }
        end,

        update_section = function()
            pills_bar:set_active(st.section)
            update_footer()
            list:set_items(st.results)
            list.offset = 0
            if list.window then list.window:damage_all() end
        end,

        start = function()
            input:set_focused(true)
        end,

        stop = function()
            if warm_state then
                warm_state.timer:cancel()
                warm_state = nil
            end
            icon_cache = {}
            svg.clear_cache()
        end,
    }
end

return M

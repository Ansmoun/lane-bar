-- themes/sidebar.lua: tema con sidebar vertical de iconos.
--
-- Layout:
--   ┌────────────────────────────────────────┐
--   │  [ input ]                             │
--   │                                        │
--   │  RECIENTES                             │
--   │  ─────────────────────────────         │
--   │  ▪  🦊  scrcpy minimal                 │
--   │  ┃      Scrcpy con perfil ligero       │
--   │  ▪  ⌨   LXTerminal                     │
--   │  ▪      Use the command line           │
--   │                                        │
--   │                        20 resultados   │
--   └────────────────────────────────────────┘
--
-- El sidebar es minimalista: sin fondo, sin cápsula. Solo el icono
-- del activo se tinta con accent y un indicador vertical lo marca.
-- Los iconos se toman de lane/icons-src (vía lib.icons).

local W      = require("lib.widgets")
local G      = require("lib.helpers.graphics")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local svg    = require("lib.svg")
local Icons  = require("lib.icons")
local Area   = require("lib.area")
local Cat    = require("lib.data.categories")

local M = {}

-- Grilla de espaciado. Múltiplos de 4.
local ROW_H          = 52
local SIDEBAR_W      = 40
local SIDEBAR_ITEM_H = 34
local SIDEBAR_ICON   = 22
local SIDEBAR_GAP    = 6
local PAD_H          = 12
local PAD_V          = 10
local CONTENT_PAD_H  = 16

function M.build(ctx)
    local st      = ctx.st
    local theme   = ctx.palette

    -- ─── SectionButton: icono clickeable, minimalista ────────────

    local SectionButton = setmetatable({}, { __index = Area })
    SectionButton.__index = SectionButton
    function SectionButton.new(opts)
        local self = setmetatable(Area.new(opts), SectionButton)
        self.id = opts.id
        self.icon = opts.icon
        self.theme = theme
        self.selected = false
        self._on_section = opts._on_section
        self.min_w, self.max_w = SIDEBAR_ITEM_H, SIDEBAR_ITEM_H
        self.min_h, self.max_h = SIDEBAR_ITEM_H, SIDEBAR_ITEM_H
        return self
    end
    function SectionButton:set_selected(v)
        v = v and true or false
        if self.selected == v then return end
        self.selected = v
        self:damage()
    end
    function SectionButton:draw(cr)
        local w, h = self:getWidth(), self:getHeight()
        local T = self.theme

        -- Solo el activo tiene fondo sutil + indicador.
        if self.selected then
            local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.10)
            cairo.rounded_rect(cr, self.x0, self.y0, w, h, 6)
            cairo.fill(cr)
            -- Indicador vertical a la izquierda (fuera del botón,
            -- sobre el borde del sidebar).
            cairo.set_rgb(cr, r, g, b)
            cairo.rounded_rect(cr, self.x0 - 6, self.y0 + 8, 3, h - 16, 1.5)
            cairo.fill(cr)
        end

        local surf = Icons.surface(self.icon, SIDEBAR_ICON)
        if surf then
            local ix = self.x0 + (w - SIDEBAR_ICON) / 2
            local iy = self.y0 + (h - SIDEBAR_ICON) / 2
            if self.selected then
                local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
                cairo.draw_surface_tinted(cr, surf, ix, iy,
                    SIDEBAR_ICON, SIDEBAR_ICON, r, g, b)
            else
                cairo.draw_surface(cr, surf, ix, iy,
                    SIDEBAR_ICON, SIDEBAR_ICON)
            end
        end
    end
    function SectionButton:on_mouse_press(mx, my, button)
        if button == 1 and self._on_section then
            self._on_section(self.id)
        end
    end

    local section_items = {}
    local sidebar_children = {}
    for _, sid in ipairs(st.groups.order) do
        local s = Cat.get(sid)
        if s then
            local btn = SectionButton.new {
                id = sid,
                icon = s.icon,
                _on_section = function(id) ctx.on_section_click(id) end,
            }
            btn:set_selected(sid == st.section)
            section_items[sid] = btn
            sidebar_children[#sidebar_children + 1] = { widget = btn, weight = 0 }
        end
    end

    -- Padding vertical del sidebar: 20px arriba para respirar del
    -- input, 8px abajo.
    local sidebar = W.Group.new {
        orientation = "vertical",
        padding = 0,
        spacing = SIDEBAR_GAP,
        children = sidebar_children,
    }

    local sidebar_col = W.Group.new {
        orientation = "vertical",
        padding = 0,
        spacing = 0,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_height = 20,
                max_height = 20,
            }, weight = 0 },
            { widget = sidebar, weight = 0 },
        },
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

    -- ─── Header de sección ───────────────────────────────────────

    local section_label = W.Text.new {
        text = "",
        font = "DejaVu Sans Bold 9",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    -- Header con alineación a CONTENT_PAD_H, usando un spacer.
    local header_row = W.Group.new {
        orientation = "horizontal",
        padding = 0,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_width = CONTENT_PAD_H,
            }, weight = 0 },
            { widget = section_label, weight = 1 },
        },
    }

    local header_wrap = W.Group.new {
        orientation = "vertical",
        padding = 6,
        children = { { widget = header_row, weight = 1 } },
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

        -- Fondo de fila con margen lateral para que no toque bordes.
        local row_x = CONTENT_PAD_H - 8
        local row_w = width - 2 * (CONTENT_PAD_H - 8)
        if is_sel then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.10)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 6)
            cairo.fill(cr)
            -- Indicador vertical corto a la izquierda.
            cairo.set_rgb(cr, r, g, b)
            cairo.rounded_rect(cr, row_x - 2, y + 16, 3, 20, 1.5)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 6)
            cairo.fill(cr)
        end

        -- Icono (32px)
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

        -- Texto
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

    -- ─── Footer (derecha) ────────────────────────────────────────

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
    --
    --   ┌─────────────────────────────────────────┐
    --   │ [input]                                 │
    --   ├───┬─────────────────────────────────────┤
    --   │ ▎ │ HEADER                              │
    --   │   │ lista + slider                      │
    --   ├───┴─────────────────────────────────────┤
    --   │                      N resultados        │
    --   └─────────────────────────────────────────┘
    --
    -- El sidebar (sidebar_col) tiene padding-top propio para
    -- respirar del input.

    local sidebar_wrap = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_width = 8,
            }, weight = 0 },
            { widget = sidebar_col, weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_width = 6,
            }, weight = 0 },
        },
    }

    local content_col = W.Group.new {
        orientation = "vertical",
        padding = 0,
        spacing = 0,
        children = {
            { widget = header_wrap, weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 0,
                children = {
                    { widget = list,   weight = 1 },
                    { widget = slider, weight = 0 },
                },
            }, weight = 1 },
        },
    }

    local rows = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = sidebar_wrap, weight = 0 },
            { widget = content_col,  weight = 1 },
        },
    }

    local root = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        children = {
            { widget = input_wrap,  weight = 0 },
            { widget = rows,        weight = 1 },
            { widget = footer_wrap, weight = 0 },
        },
    }

    -- ─── Handle ──────────────────────────────────────────────────

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
            -- Scroll para que el seleccionado sea visible.
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

        update_section = function()
            -- Actualizar tint del sidebar y label del header.
            for sid, btn in pairs(section_items) do
                btn:set_selected(sid == st.section)
            end
            local sec = Cat.get(st.section)
            local label = (st.query == "" and sec) and sec.label:upper()
                          or (st.query ~= "" and "BÚSQUEDA") or ""
            section_label:set_text(label)
            update_footer()
            list:set_items(st.results)
            list.offset = 0
            if list.window then list.window:damage_all() end
        end,

        start = function()
            -- Estado inicial del header.
            local sec = Cat.get(st.section)
            if sec and st.query == "" then
                section_label:set_text(sec.label:upper())
            end
            input:set_focused(true)
        end,

        stop = function()
            icon_cache = {}
            svg.clear_cache()
        end,
    }
end

return M

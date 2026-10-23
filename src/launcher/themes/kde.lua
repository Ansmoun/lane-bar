-- themes/kde.lua: launcher tipo KDE Plasma Kickoff.
--
-- Layout:
--   ┌───────────────┬──────────────────────────────┐
--   │  ⭐ Favoritos  │  🔍 Buscar aplicaciones...   │
--   │  📱 Aplicac.  │  ─────────────────────────   │
--   │  🖥  Sistema   │  FAVORITOS                    │
--   │  🎮 Juegos    │  ─────────────                │
--   │  📄 Oficina   │  🦊 Firefox                   │
--   │  🌐 Internet  │  ⌨  Terminal                  │
--   │  ...          │  📁 PCMan FM                  │
--   │               │                    20 items   │
--   └───────────────┴──────────────────────────────┘
--
-- Sidebar con icono + label siempre visible (a diferencia del tema
-- pills donde solo se ve el icono hasta hover/click).

local W      = require("lib.widgets")
local G      = require("lib.helpers.graphics")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local svg    = require("lib.svg")
local Icons  = require("lib.icons")
local Area   = require("lib.area")
local Cat    = require("lib.data.categories")

local M = {}

local SIDEBAR_W       = 180
local SIDEBAR_ITEM_H  = 38
local SIDEBAR_ICON    = 22
local SIDEBAR_GAP     = 2
local CONTENT_PAD_H   = 16
local PAD_V           = 10
local ROW_H           = 52

-- Etiquetas alternativas para las secciones genéricas.
local LABEL_OVERRIDE = {
    recientes = "Favoritos",
    todas     = "Aplicaciones",
}

function M.build(ctx)
    local st    = ctx.st
    local theme = ctx.palette

    -- ─── SidebarButton ───────────────────────────────────────────
    --
    -- Icono + label siempre visibles. Item activo: fondo accent
    -- sutil + indicador izquierdo. Hover: fondo separator sutil.
    local SidebarButton = setmetatable({}, { __index = Area })
    SidebarButton.__index = SidebarButton
    function SidebarButton.new(opts)
        local self = setmetatable(Area.new(opts), SidebarButton)
        self.id = opts.id
        self.icon = opts.icon
        self.label = opts.label
        self.theme = theme
        self.selected = false
        self._on_section = opts._on_section
        self.min_w, self.max_w = SIDEBAR_W, SIDEBAR_W
        self.min_h, self.max_h = SIDEBAR_ITEM_H, SIDEBAR_ITEM_H
        return self
    end
    function SidebarButton:set_selected(v)
        v = v and true or false
        if self.selected == v then return end
        self.selected = v
        self:damage()
    end
    function SidebarButton:draw(cr)
        local T = self.theme
        local w, h = self:getWidth(), self:getHeight()
        local accent = T.accent_rgb or { 0.9, 0.7, 0.4 }
        local sep    = T.separator_rgb or { 0.3, 0.3, 0.3 }
        local fg     = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local muted  = T.muted_rgb or { 0.5, 0.5, 0.5 }

        if self.selected then
            cairo.set_rgba(cr, accent[1], accent[2], accent[3], 0.18)
            cairo.rounded_rect(cr, self.x0 + 6, self.y0 + 2, w - 12, h - 4, 6)
            cairo.fill(cr)
            cairo.set_rgb(cr, accent[1], accent[2], accent[3])
            cairo.rounded_rect(cr, self.x0 + 2, self.y0 + 8, 3, h - 16, 1.5)
            cairo.fill(cr)
        elseif self.hover then
            cairo.set_rgba(cr, sep[1], sep[2], sep[3], 0.25)
            cairo.rounded_rect(cr, self.x0 + 6, self.y0 + 2, w - 12, h - 4, 6)
            cairo.fill(cr)
        end

        -- Icono
        local surf = Icons.surface(self.icon, SIDEBAR_ICON)
        local ix = self.x0 + 14
        local iy = self.y0 + (h - SIDEBAR_ICON) / 2
        if surf then
            if self.selected then
                cairo.draw_surface_tinted(cr, surf, ix, iy,
                    SIDEBAR_ICON, SIDEBAR_ICON, accent[1], accent[2], accent[3])
            else
                cairo.draw_surface(cr, surf, ix, iy, SIDEBAR_ICON, SIDEBAR_ICON)
            end
        end

        -- Label
        local tx = ix + SIDEBAR_ICON + 12
        local ty = self.y0 + (h - 14) / 2
        local col = self.selected and accent or fg
        pango.draw_text(cr, tx, ty, self.label, "DejaVu Sans 11",
            { r = col[1], g = col[2], b = col[3] })
    end
    function SidebarButton:on_mouse_press(mx, my, button)
        if button == 1 and self._on_section then
            self._on_section(self.id)
        end
    end

    -- Construir lista de botones en orden de st.groups.order
    local sidebar_buttons = {}
    local sidebar_children = {}
    for _, sid in ipairs(st.groups.order) do
        local s = Cat.get(sid)
        if s then
            local label = LABEL_OVERRIDE[sid] or s.label
            local btn = SidebarButton.new {
                id = sid,
                icon = s.icon,
                label = label,
                _on_section = function(id) ctx.on_section_click(id) end,
            }
            btn:set_selected(sid == st.section)
            sidebar_buttons[sid] = btn
            sidebar_children[#sidebar_children + 1] = { widget = btn, weight = 0 }
        end
    end

    local sidebar = W.Group.new {
        orientation = "vertical",
        padding = 8,
        spacing = SIDEBAR_GAP,
        children = sidebar_children,
    }

    -- Fondo del sidebar (color oscurecido, como en bar.theme=kde).
    local SidebarPanel = setmetatable({}, { __index = W.Group })
    SidebarPanel.__index = SidebarPanel
    function SidebarPanel.new(opts)
        local self = setmetatable(W.Group.new(opts), SidebarPanel)
        self.theme = theme
        return self
    end
    function SidebarPanel:draw(cr)
        local T = self.theme
        local bg = T.bg_sidebar_rgb or T.bg_card_rgb or { 0.05, 0.05, 0.06 }
        cairo.set_rgb(cr, bg[1], bg[2], bg[3])
        cairo.rectangle(cr, self.x0, self.y0, self:getWidth(), self:getHeight())
        cairo.fill(cr)
        W.Group.draw(self, cr)
    end

    local sidebar_panel = SidebarPanel.new {
        theme = theme,
        orientation = "vertical",
        padding = 0,
        spacing = 0,
        children = { { widget = sidebar, weight = 1 } },
    }

    -- ─── Input ───────────────────────────────────────────────────

    local input
    input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 13",
        padding_x = 14, padding_y = 8,
        min_height = 40,
        color_bg = theme.bg_focus,
        color_border = nil,
        corner_radius = 6,
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
        children = {
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_width = CONTENT_PAD_H,
            }, weight = 0 },
            { widget = input, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal",
                padding = 0,
                children = {},
                min_width = CONTENT_PAD_H,
            }, weight = 0 },
        },
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

    -- Forward declaration: la variable debe existir ANTES de la
    -- construcción para que el closure de on_click la capture como
    -- upvalue (si no, es global y vale nil al ejecutarse).
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

        local row_x = CONTENT_PAD_H - 8
        local row_w = width - 2 * (CONTENT_PAD_H - 8)
        if is_sel then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.14)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 4)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rounded_rect(cr, row_x, y + 3, row_w, rh - 6, 4)
            cairo.fill(cr)
        end

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

    -- ─── Layout ──────────────────────────────────────────────────

    local content_col = W.Group.new {
        orientation = "vertical",
        padding = 0,
        spacing = 0,
        children = {
            { widget = input_wrap,  weight = 0 },
            { widget = header_wrap, weight = 0 },
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

    local root = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = sidebar_panel, weight = 0 },
            { widget = content_col,   weight = 1 },
        },
    }

    -- Prewarm de iconos en background.
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

        update_section = function()
            for sid, btn in pairs(sidebar_buttons) do
                btn:set_selected(sid == st.section)
            end
            local sec = Cat.get(st.section)
            local label = (st.query == "" and sec)
                          and (LABEL_OVERRIDE[st.section] or sec.label):upper()
                          or "BÚSQUEDA"
            section_label:set_text(label)
            update_footer()
            list:set_items(st.results)
            list.offset = 0
            if list.window then list.window:damage_all() end
        end,

        start = function()
            local sec = Cat.get(st.section)
            if sec and st.query == "" then
                section_label:set_text(
                    (LABEL_OVERRIDE[st.section] or sec.label):upper())
            end
            input:set_focused(true)
        end,

        stop = function()
            icon_cache = {}
            svg.clear_cache()
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
    }
end

return M

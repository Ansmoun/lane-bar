-- themes/win10.lua: launcher estilo Windows 10.
--
-- Estructura de 2 columnas:
--   ┌────────┬──────────────────────────────────────┐
--   │ ☰ 👤   │  🔍 Buscar aplicaciones...            │
--   │        ├──────────────────────────────────────┤
--   │  🏠    │  TODAS LAS APLICACIONES               │
--   │  📄    │  ────────────                         │
--   │  🖼     │  [A]                                  │
--   │  ⚙     │    Adobe Reader                       │
--   │        │    App 1                              │
--   │        │  [B]                                  │
--   │        │    Blender                            │
--   │  ⏻     │    Brave                              │
--   └────────┴──────────────────────────────────────┘
--    Left          Center
--    Rail      (All Apps + Search)
--
-- Left rail colapsado: solo iconos (48px).
-- Left rail expandido (click en ☰): iconos + labels (200px).

local W      = require("lib.widgets")
local G      = require("lib.helpers.graphics")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local svg    = require("lib.svg")
local Icons  = require("lib.icons")
local Area   = require("lib.area")
local Inicio = require("lib.data.inicio")

local M = {}

-- ─── Constantes de layout ────────────────────────────────────────
local RAIL_COLLAPSED = 48
local RAIL_EXPANDED  = 220
local RAIL_ITEM_H    = 44
local RAIL_ICON      = 22
local RAIL_AVATAR    = 32
local RAIL_AVATAR_XL = 72
local ROW_H          = 52
local HEADER_H       = 40
local CONTENT_PAD_H  = 16
local PAD_V          = 10

local SHORTCUTS = {
    { id = "home",   icon = "win10/home",    label = "Inicio",
      cmd = nil },
    { id = "docs",   icon = "win10/docs",    label = "Documentos",
      cmd = "setsid -f /opt/lane-files/run /opt/lane-files/lane-files.lua $HOME/Documentos >/dev/null 2>&1" },
    { id = "pics",   icon = "win10/pics",    label = "Imágenes",
      cmd = "setsid -f /opt/lane-files/run /opt/lane-files/lane-files.lua $HOME/Imágenes >/dev/null 2>&1" },
    { id = "config", icon = "win10/config",  label = "Configuración",
      cmd = "setsid -f /opt/lane/run apps/config.lua >/dev/null 2>&1" },
}

function M.build(ctx)
    local st    = ctx.st
    local theme = ctx.palette

    local state = { rail_expanded = false }

    local username = os.getenv("USER") or "user"
    local avatar_path = Inicio.find_avatar(username)

    -- Pre-escalado: cairo.load_png carga el PNG a su tamaño nativo
    -- (1080px en nuestro caso). Dibujar directo a 72px da pixelado
    -- porque el filtro GOOD en Cairo no re-muestrea tan agresivo.
    -- Solución: renderizar el PNG una vez a un surface de 160px con
    -- filtro BEST, y usar ese surface como fuente.
    local function load_avatar_small(path, target)
        if not path then return nil end
        local big = cairo.load_png(path)
        if not big then return nil end
        local nw = cairo.surface_width(big)
        local nh = cairo.surface_height(big)
        if nw == 0 or nh == 0 then return nil end
        local small = cairo.image_surface_create(target, target,
                                                 cairo.FORMAT.ARGB32)
        local cr2 = cairo.context(small)
        cairo.set_operator(cr2, cairo.OPERATOR.SOURCE)
        cairo.set_filter(cr2, cairo.FILTER.BEST)
        cairo.draw_surface(cr2, big, 0, 0, target, target)
        cairo.destroy_context(cr2)
        cairo.destroy_surface(big)
        return small
    end

    local avatar_surface = load_avatar_small(avatar_path, 160)

    -- ─── Cache de iconos ─────────────────────────────────────────
    local icon_cache = {}
    local function get_surface(name, size)
        if not name then return nil end
        local key = name .. ":" .. size
        if icon_cache[key] ~= nil then return icon_cache[key] or nil end
        local surf = Icons.surface(name, size)
        icon_cache[key] = surf or false
        return surf
    end

    -- ─── HamburgerButton (☰) ─────────────────────────────────────
    local Hamburger = setmetatable({}, { __index = Area })
    Hamburger.__index = Hamburger
    function Hamburger.new(opts)
        local self = setmetatable(Area.new(opts), Hamburger)
        self.theme = theme
        self.min_w, self.max_w = 32, 32
        self.min_h, self.max_h = 32, 32
        return self
    end
    function Hamburger:draw(cr)
        local T = self.theme
        local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local w, h = self:getWidth(), self:getHeight()
        local cx = self.x0 + w / 2
        local cy = self.y0 + h / 2
        cairo.set_rgb(cr, fg[1], fg[2], fg[3])
        cairo.set_line_width(cr, 1.5)
        for i = -1, 1 do
            cairo.move_to(cr, cx - 8, cy + i * 5)
            cairo.line_to(cr, cx + 8, cy + i * 5)
        end
        cairo.stroke(cr)
    end
    function Hamburger:on_mouse_press(mx, my, button)
        if button ~= 1 then return end
        state.rail_expanded = not state.rail_expanded
        -- Solo el RailPanel gestiona la expansión: propaga a sus
        -- hijos y dispara relayout.
        if state.rail_panel then
            state.rail_panel:set_expanded(state.rail_expanded)
        end
    end

    -- ─── RailButton (icono del left rail) ────────────────────────
    local RailButton = setmetatable({}, { __index = Area })
    RailButton.__index = RailButton
    function RailButton.new(opts)
        local self = setmetatable(Area.new(opts), RailButton)
        self.theme = theme
        self.icon = opts.icon
        self.label = opts.label
        self.cmd = opts.cmd
        self.expanded = false
        self.min_h, self.max_h = RAIL_ITEM_H, RAIL_ITEM_H
        self.min_w, self.max_w = RAIL_COLLAPSED, RAIL_EXPANDED
        return self
    end
    function RailButton:set_expanded(v)
        self.expanded = v
        self.min_w = RAIL_COLLAPSED
        self.max_w = v and RAIL_EXPANDED or RAIL_COLLAPSED
        self:damage()
    end
    function RailButton:draw(cr)
        local T = self.theme
        local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local w, h = self:getWidth(), self:getHeight()
        if self.hover then
            local r, g, b = G.hex_to_rgba(T.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rounded_rect(cr, self.x0 + 4, self.y0 + 2, w - 8, h - 4, 4)
            cairo.fill(cr)
        end
        local surf = get_surface(self.icon, RAIL_ICON)
        if self.expanded then
            -- Alineado a la izquierda, como lista.
            local ix = self.x0 + 12
            local iy = self.y0 + (h - RAIL_ICON) / 2
            if surf then
                cairo.draw_surface(cr, surf, ix, iy, RAIL_ICON, RAIL_ICON)
            end
            if self.label then
                local tx = ix + RAIL_ICON + 12
                local ty = self.y0 + (h - 14) / 2
                pango.draw_text(cr, tx, ty, self.label, "DejaVu Sans 11",
                    { r = fg[1], g = fg[2], b = fg[3] })
            end
        else
            if surf then
                local ix = self.x0 + (w - RAIL_ICON) / 2
                local iy = self.y0 + (h - RAIL_ICON) / 2
                cairo.draw_surface(cr, surf, ix, iy, RAIL_ICON, RAIL_ICON)
            end
        end
    end
    function RailButton:on_mouse_press(mx, my, button)
        if button == 1 and self.cmd then
            os.execute(self.cmd)
            if ctx.execute then ctx.execute(nil) end
        end
    end

    -- ─── Búsqueda ────────────────────────────────────────────────

    local input
    input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 12",
        padding_x = 12, padding_y = 8,
        min_height = 36,
        color_bg = theme.bg_focus,
        color_border = nil,
        corner_radius = 4,
        color_text = theme.fg_rgb,
        placeholder = "Buscar aplicaciones...",
        color_placeholder = theme.muted_rgb,
        on_change = function(text) ctx.on_query_change(text) end,
        on_submit = function()
            input:set_focused(false)
            local e = st.results[st.selected]
            if e and e.kind ~= "heading" then
                ctx.execute(e)
                if input.window then input.window:close("lanzado") end
            end
        end,
        on_cancel = function()
            if input.window then input.window:close("escape") end
        end,
        on_up   = function() ctx.on_move_selection(-1) end,
        on_down = function() ctx.on_move_selection(1)  end,
    }
    input.opts.on_focus_request = function() input:set_focused(true) end

    local input_wrap = W.Group.new {
        orientation = "horizontal",
        padding = PAD_V,
        children = {
            { widget = W.Group.new {
                orientation = "horizontal", padding = 0,
                children = {}, min_width = CONTENT_PAD_H,
            }, weight = 0 },
            { widget = input, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal", padding = 0,
                children = {}, min_width = CONTENT_PAD_H,
            }, weight = 0 },
        },
    }

    -- ─── ScrollView con headings + apps ──────────────────────────

    -- El scrollview usa row_height fijo. Para dar cabida a los
    -- headings (que son más altos), uso un solo tamaño y dibujo
    -- distinto según el item.kind. Simplifica el widget genérico.
    local list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 400,
        min_height = ROW_H * 4,
        on_click = function(item)
            if item and item.kind ~= "heading" then
                ctx.execute(item)
                if list.window then list.window:close("launcher ejecutado") end
            end
        end,
    }

    local app_icon_cache = {}
    local function get_app_icon(path)
        if not path then return nil end
        local s = app_icon_cache[path]
        if s ~= nil then return s or nil end
        local ext = (path:match("%.([%w]+)$") or ""):lower()
        local surf
        if ext == "svg" then
            surf = svg.load(path, 32, 32)
        else
            surf = cairo.load_png_cached(path)
        end
        app_icon_cache[path] = surf or false
        return surf
    end

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end

        -- Letter heading
        if item.kind == "heading" then
            local accent = theme.accent_rgb or { 0.9, 0.7, 0.4 }
            local tx = CONTENT_PAD_H
            local ty = y + (rh - 14) / 2
            pango.draw_text(cr, tx, ty, item.letter, "DejaVu Sans Bold 12",
                { r = accent[1], g = accent[2], b = accent[3] })
            -- Línea horizontal suave a la derecha del heading
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rectangle(cr, tx + 20, y + rh / 2, width - tx - 40, 1)
            cairo.fill(cr)
            return
        end

        -- App
        local is_sel = (idx == st.selected)
        local row_x = CONTENT_PAD_H - 8
        local row_w = width - 2 * (CONTENT_PAD_H - 8)

        if is_sel then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.18)
            cairo.rectangle(cr, row_x, y + 2, row_w, rh - 4)
            cairo.fill(cr)
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, row_x, y + 2, 3, rh - 4)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.20)
            cairo.rectangle(cr, row_x, y + 2, row_w, rh - 4)
            cairo.fill(cr)
        end

        -- Icono
        local icon_size = 28
        local icon_x = CONTENT_PAD_H + 8
        local icon_y = y + (rh - icon_size) / 2
        local surface = get_app_icon(item._icon_path)
        if surface then
            cairo.draw_surface(cr, surface, icon_x, icon_y, icon_size, icon_size)
        else
            local r, g, b = G.hex_to_rgba(theme.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.6)
            cairo.rounded_rect(cr, icon_x, icon_y, icon_size, icon_size, 4)
            cairo.fill(cr)
            local first = (item.name or "?"):sub(1, 1):upper()
            local letter = first:match("[A-Z]") and first or "?"
            local r2, g2, b2 = G.hex_to_rgba(theme.fg_normal or "#ebdbb2")
            local lw = pango.measure(letter, "DejaVu Sans Bold 12")
            local _, lh = pango.measure(letter, "DejaVu Sans Bold 12")
            pango.draw_text(cr,
                icon_x + (icon_size - lw) / 2,
                icon_y + (icon_size - lh) / 2,
                letter, "DejaVu Sans Bold 12",
                { r = r2, g = g2, b = b2 })
        end

        -- Texto
        local text_x = icon_x + icon_size + 12
        local text_w = width - text_x - CONTENT_PAD_H
        local title_color = is_sel and (theme.accent or "#8ec07c")
                            or (theme.fg_normal or "#ebdbb2")
        local r, g, b = G.hex_to_rgba(title_color)
        cairo.save(cr)
        cairo.rectangle(cr, text_x, y, text_w, rh / 2); cairo.clip(cr)
        pango.draw_text(cr, text_x, y + 9, item.name or "?", "DejaVu Sans 11",
            { r = r, g = g, b = b })
        cairo.restore(cr)

        local sub = item.comment or ""
        if item.kind == "command" then sub = "Ejecutar: " .. (item.name or "") end
        if sub ~= "" then
            if #sub > 60 then sub = sub:sub(1, 58) .. "..." end
            local r2, g2, b2 = G.hex_to_rgba(theme.muted or "#928374")
            cairo.save(cr)
            cairo.rectangle(cr, text_x, y + rh / 2, text_w, rh / 2); cairo.clip(cr)
            pango.draw_text(cr, text_x, y + 28, sub, "DejaVu Sans 9",
                { r = r2, g = g2, b = b2 })
            cairo.restore(cr)
        end
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical", width = 6, thickness = 2, handle_r = 2,
        step = ROW_H * 3,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    -- ─── Rail (columna izquierda) ────────────────────────────────

    -- Contenedor del rail: maneja el ancho dinámico (colapsado /
    -- expandido). Cuando cambia, dispara invalidate_layout para que
    -- el Group reasigne los rects.
    local rail_buttons = {}
    local RailPanel = setmetatable({}, { __index = W.Group })
    RailPanel.__index = RailPanel
    function RailPanel.new(opts)
        local self = setmetatable(W.Group.new(opts), RailPanel)
        self.theme = theme
        return self
    end
    function RailPanel:set_expanded(v)
        self._expanded = v
        self.min_w = v and RAIL_EXPANDED or RAIL_COLLAPSED
        self.max_w = self.min_w
        for _, btn in ipairs(rail_buttons) do btn:set_expanded(v) end
        if self.avatar_widget then self.avatar_widget:set_expanded(v) end
        if self.power_widget  then self.power_widget:set_expanded(v)  end
        -- Necesario: Group:askMinMax ignora self.min_w. Forzamos
        -- relayout explícito.
        self:invalidate_layout()
    end

    -- Override: Group:askMinMax mira solo los hijos. Necesitamos
    -- que respete el ancho deseado del rail (200 cuando expandido).
    function RailPanel:askMinMax(minw, minh, maxw, maxh)
        local bw, bh, mxw, mxh = W.Group.askMinMax(self, 0, 0, 0, 0)
        local want = self._expanded and RAIL_EXPANDED or RAIL_COLLAPSED
        -- Forzar el ancho deseado por arriba de lo que pidan los hijos.
        if bw < want then bw = want end
        if mxw < want then mxw = want end
        return minw + bw, minh + bh, maxw + mxw, maxh + mxh
    end
    function RailPanel:draw(cr)
        local T = self.theme
        local bg = T.bg_sidebar_rgb or T.bg_card_rgb or { 0.05, 0.05, 0.06 }
        cairo.set_rgb(cr, bg[1], bg[2], bg[3])
        cairo.rectangle(cr, self.x0, self.y0, self:getWidth(), self:getHeight())
        cairo.fill(cr)
        W.Group.draw(self, cr)
    end

    -- Avatar (colapsado o expandido)
    local Avatar = setmetatable({}, { __index = Area })
    Avatar.__index = Avatar
    function Avatar.new(opts)
        local self = setmetatable(Area.new(opts), Avatar)
        self.theme = theme
        self.surface = avatar_surface
        self.expanded = false
        self.username = username
        self.min_h, self.max_h = 56, 88
        self.min_w, self.max_w = RAIL_COLLAPSED, RAIL_EXPANDED
        return self
    end
    function Avatar:set_expanded(v)
        self.expanded = v
        self.min_w = RAIL_COLLAPSED
        self.max_w = v and RAIL_EXPANDED or RAIL_COLLAPSED
        -- El avatar expandido ocupa: 12 (pad top) + 72 (avatar) +
        -- 8 (gap) + 14 (label). Con margen = 114.
        self.min_h = v and 114 or 56
        self.max_h = self.min_h
        self:damage()
    end
    function Avatar:draw(cr)
        local T = self.theme
        local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local accent = T.accent_rgb or { 0.9, 0.7, 0.4 }
        local w, h = self:getWidth(), self:getHeight()

        local size = self.expanded and RAIL_AVATAR_XL or RAIL_AVATAR
        local cx, cy
        if self.expanded then
            cx = self.x0 + w / 2
            cy = self.y0 + 12 + size / 2
        else
            cx = self.x0 + w / 2
            cy = self.y0 + h / 2
        end
        local r = size / 2

        -- Anillo
        cairo.set_rgb(cr, accent[1], accent[2], accent[3])
        cairo.new_path(cr)
        cairo.arc(cr, cx, cy, r + 1, 0, 2 * math.pi)
        cairo.fill(cr)

        -- Interior: imagen o inicial
        cairo.save(cr)
        cairo.new_path(cr)
        cairo.arc(cr, cx, cy, r - 1, 0, 2 * math.pi)
        cairo.clip(cr)
        if self.surface then
            local nw = cairo.surface_width(self.surface)
            local nh = cairo.surface_height(self.surface)
            if nw > 0 and nh > 0 then
                local target = (r - 1) * 2
                local scale = math.max(target / nw, target / nh)
                local dw = nw * scale
                local dh = nh * scale
                cairo.save(cr)
                cairo.set_filter(cr, cairo.FILTER.GOOD)
                cairo.draw_surface(cr, self.surface,
                    cx - dw / 2, cy - dh / 2, dw, dh)
                cairo.restore(cr)
            end
        else
            local bg = T.bg_focus_rgb or { 0.1, 0.1, 0.15 }
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rectangle(cr, cx - r, cy - r, 2 * r, 2 * r)
            cairo.fill(cr)
            local letter = (self.username or "?"):sub(1, 1):upper()
            local px = math.floor(r * 0.8)
            local font = "DejaVu Sans Bold " .. px
            local iw, ih = pango.measure(letter, font)
            pango.draw_text(cr, cx - iw / 2, cy - ih / 2, letter, font,
                { r = 0.95, g = 0.95, b = 0.95 })
        end
        cairo.restore(cr)

        -- Nombre debajo (solo expandido)
        if self.expanded then
            local ty = self.y0 + 12 + size + 8
            local name = self.username
            local nw = pango.measure(name, "DejaVu Sans 11")
            pango.draw_text(cr, self.x0 + (w - nw) / 2, ty,
                name, "DejaVu Sans 11",
                { r = fg[1], g = fg[2], b = fg[3] })
        end
    end

    local avatar_widget = Avatar.new {}

    -- PowerButton (icono de apagado al fondo)
    local PowerButton = setmetatable({}, { __index = Area })
    PowerButton.__index = PowerButton
    function PowerButton.new(opts)
        local self = setmetatable(Area.new(opts), PowerButton)
        self.theme = theme
        self.expanded = false
        self.min_h, self.max_h = RAIL_ITEM_H, RAIL_ITEM_H
        self.min_w, self.max_w = RAIL_COLLAPSED, RAIL_EXPANDED
        return self
    end
    function PowerButton:set_expanded(v)
        self.expanded = v
        self.min_w = RAIL_COLLAPSED
        self.max_w = v and RAIL_EXPANDED or RAIL_COLLAPSED
        self:damage()
    end
    function PowerButton:draw(cr)
        local T = self.theme
        local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
        local w, h = self:getWidth(), self:getHeight()
        if self.hover then
            local r, g, b = G.hex_to_rgba(T.separator or "#504945")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rounded_rect(cr, self.x0 + 4, self.y0 + 2, w - 8, h - 4, 4)
            cairo.fill(cr)
        end
        local surf = get_surface("win10/power", RAIL_ICON)
        if self.expanded then
            local label = "Apagar"
            local lw = pango.measure(label, "DejaVu Sans 11")
            local block_w = RAIL_ICON + 12 + lw
            local bx = self.x0 + (w - block_w) / 2
            local iy = self.y0 + (h - RAIL_ICON) / 2
            if surf then
                cairo.draw_surface(cr, surf, bx, iy, RAIL_ICON, RAIL_ICON)
            end
            local tx = bx + RAIL_ICON + 12
            local ty = self.y0 + (h - 14) / 2
            pango.draw_text(cr, tx, ty, label, "DejaVu Sans 11",
                { r = fg[1], g = fg[2], b = fg[3] })
        else
            if surf then
                local ix = self.x0 + (w - RAIL_ICON) / 2
                local iy = self.y0 + (h - RAIL_ICON) / 2
                cairo.draw_surface(cr, surf, ix, iy, RAIL_ICON, RAIL_ICON)
            end
        end
    end
    function PowerButton:on_mouse_press(mx, my, button)
        if button == 1 then
            -- Invocar el menú de logout de LANE si existe.
            os.execute("setsid -f /opt/lane/run apps/logout.lua >/dev/null 2>&1")
            if ctx.execute then ctx.execute(nil) end
        end
    end

    local power_button = PowerButton.new {}

    -- Construir rail buttons
    local rail_children = {}
    rail_children[#rail_children + 1] = { widget = avatar_widget, weight = 0 }
    rail_children[#rail_children + 1] = { widget = W.Group.new {
        orientation = "horizontal", padding = 0, children = {},
        min_height = 8, max_height = 8,
    }, weight = 0 }

    for _, s in ipairs(SHORTCUTS) do
        local btn = RailButton.new {
            icon = s.icon, label = s.label, cmd = s.cmd,
        }
        rail_buttons[#rail_buttons + 1] = btn
        rail_children[#rail_children + 1] = { widget = btn, weight = 0 }
    end

    -- Spacer flexible para empujar el power al fondo
    rail_children[#rail_children + 1] = { widget = W.Group.new {
        orientation = "vertical", padding = 0, children = {},
        min_height = 10, max_height = 10000,
    }, weight = 1 }

    rail_children[#rail_children + 1] = { widget = power_button, weight = 0 }

    local rail = RailPanel.new {
        theme = theme,
        orientation = "vertical",
        padding = 6,
        spacing = 2,
        children = rail_children,
    }
    rail.min_w, rail.max_w = RAIL_COLLAPSED, RAIL_COLLAPSED
    rail.avatar_widget = avatar_widget
    rail.power_widget = power_button

    -- El hamburger va DENTRO del rail, como primer item, alineado
    -- con el resto. Así no corta el fondo del rail.
    local hamburger = Hamburger.new {}

    -- Nota: rail ya se construyó con sus hijos (avatar, shortcuts,
    -- spacer, power). Insertamos el hamburger al principio.
    table.insert(rail.children, 1, hamburger)
    rail.weights[#rail.weights + 1] = 0
    -- Corregir: el peso debe ir en la posición correspondiente.
    table.remove(rail.weights)
    table.insert(rail.weights, 1, 0)

    -- rail_wrap es simplemente un contenedor para que el layout
    -- horizontal externo no lo expanda. Su ancho lo controla el rail.
    local rail_wrap = rail

    state.rail_wrap = rail_wrap
    state.rail_panel = rail
    state.avatar = avatar_widget
    state.power = power_button
    state.hamburger = hamburger

    -- ─── Layout final ────────────────────────────────────────────

    local content_col = W.Group.new {
        orientation = "vertical",
        padding = 0,
        spacing = 0,
        children = {
            { widget = input_wrap, weight = 0 },
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

    local root = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = rail_wrap,  weight = 0 },
            { widget = content_col, weight = 1 },
        },
    }

    -- ─── Reconstruir la lista con letter headings ────────────────

    -- Devuelve el array de items que va al scrollview: headings
    -- mezclados con apps. Cuando hay query, se muestra la lista
    -- plana sin headings.
    local D = require("lib.data.launcher")

    local function build_list_items()
        if st.query and st.query ~= "" then
            return st.results
        end
        st.results = D.all_entries()

        -- Agrupar por letra.
        local g = { order = {} }
        for _, e in ipairs(st.results) do
            local first = (e.name or "?"):sub(1, 1):upper()
            if not first:match("[A-Z]") then first = "#" end
            if not g[first] then
                g[first] = {}
                g.order[#g.order + 1] = first
            end
            g[first][#g[first] + 1] = e
        end
        table.sort(g.order)

        local out = {}
        for _, letter in ipairs(g.order) do
            out[#out + 1] = { kind = "heading", letter = letter }
            for _, e in ipairs(g[letter]) do
                out[#out + 1] = e
            end
        end
        return out
    end

    -- El controlador actualiza st.selected asumiendo lista plana. Acá
    -- adaptamos: cuando hay headings, la selección debe saltarlos.
    local function skip_headings(list, idx, dir)
        local n = #list
        if n == 0 then return 1 end
        idx = idx + dir
        while idx >= 1 and idx <= n do
            if list[idx].kind ~= "heading" then return idx end
            idx = idx + dir
        end
        -- No hay más items seleccionables en esta dirección.
        return nil
    end

    -- ─── Handle ──────────────────────────────────────────────────

    local function update_footer()
        -- Sin footer en win10 (todo el espacio es la lista).
    end

    return {
        widget = root,

        focus = function()
            if input.window then
                input.window:set_focus_widget(input)
            end
        end,

        update_results = function()
            local items = build_list_items()
            list:set_items(items)
            list.offset = 0
            list.hover_idx = -1
            -- Resetear la selección al primer item seleccionable.
            local first = nil
            for i, it in ipairs(items) do
                if it.kind ~= "heading" then first = i; break end
            end
            st.selected = first or 1
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
            -- No hay secciones en win10. Solo refrescamos.
            local items = build_list_items()
            list:set_items(items)
            list.offset = 0
            if list.window then list.window:damage_all() end
        end,

        start = function()
            input:set_focused(true)
            local items = build_list_items()
            list:set_items(items)
            if list.window then list.window:damage_all() end
        end,

        stop = function()
            icon_cache = {}
            app_icon_cache = {}
            svg.clear_cache()
        end,
    }
end

return M

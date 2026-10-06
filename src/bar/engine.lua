-- Motor de barra. Portado de ui/bar.lua (Awesome).
-- Lee una spec puro dato, monta el arbol de widgets, y aplica
-- separadores segun el modo declarado.

local W = require("lib.widgets")
local Sep = require("bar.separators")
local Styles = require("bar.styles")
local log = require("lib.log")

local M = {}


-- Normaliza una entrada de lista (string o toggle_group).
local function normalize_entry(entry)
    if type(entry) == "string" then
        return { kind = "widget", name = entry }
    end
    if type(entry) == "table" and entry.toggle_group then
        return {
            kind = "group",
            group = entry.toggle_group,
            default = entry.default or "visible",
            widgets = entry.widgets or {},
        }
    end
    return nil
end

local function flatten_list(list)
    local out = {}
    local groups = {}
    for _, entry in ipairs(list or {}) do
        local e = normalize_entry(entry)
        if e and e.kind == "widget" then
            out[#out + 1] = { name = e.name, group = nil }
        elseif e and e.kind == "group" then
            groups[e.group] = {
                default = e.default,
                visible = (e.default == "visible"),
            }
            for _, wname in ipairs(e.widgets) do
                out[#out + 1] = { name = wname, group = e.group }
            end
        end
    end
    return out, groups
end

-- Construye un lado (left/center/right) delegando al estilo.
local function build_side(theme, list, registry, groups, opts, srv)
    opts = opts or {}
    local style_name = opts.style or "arrow"
    local gap        = opts.gap or 12
    local bar_h      = opts.bar_h or 22
    local starts, stops = {}, {}

    local T       = theme or {}
    local bg_hex  = T.bg_rgb and Sep.rgb_to_hex(T.bg_rgb) or "#000000"
    local sep_col = T.separator or "#333333"

    local style_mod = Styles.get(style_name)
    local style = style_mod.new {
        theme = T, bar_h = bar_h, gap = gap,
        bg_hex = bg_hex, sep_color = sep_col,
        font = T.font,
    }

    local instances = {}

    for _, item in ipairs(list) do
        local ctor = registry[item.name]
        if not ctor then
            log.warn("bar", "constructor no encontrado: %s", item.name)
        else
            local ok, res = pcall(ctor, theme, srv)
            if not ok or not res then
                log.error("bar", "constructor %s fallo: %s",
                    item.name, tostring(res))
            else
                instances[item.name] = res
                if type(res) == "table" then
                    if res.start then starts[#starts + 1] = res.start end
                    if res.stop  then stops[#stops  + 1] = res.stop  end
                end

                local visible = true
                if item.group then
                    local g = groups[item.group]
                    if g and not g.visible then visible = false end
                end

                if visible then
                    local wrapper = (type(res) == "table" and res.widget)
                        and res or { widget = res }

                    -- fg: contraste segun fondo del widget, o el
                    -- propio color de telemetria si el estilo lo pide.
                    local fg_mode = style_mod.fg_mode or "contrast"
                    local widget_fg
                    if fg_mode == "self" and wrapper.color then
                        widget_fg = wrapper.color
                    elseif style_name == "underline" then
                        widget_fg = T.fg_normal or "#FEFEFE"
                    elseif wrapper.color then
                        widget_fg = Sep.pick_fg(wrapper.color)
                    else
                        widget_fg = T.fg_normal or "#FEFEFE"
                    end
                    if wrapper.set_fg then wrapper.set_fg(widget_fg) end

                    style:emit {
                        name = item.name,
                        widget = wrapper.widget or wrapper,
                        color = wrapper.color,
                    }
                end
            end
        end
    end

    local children = style:finish()
    local grp = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = children,
    }
    return { group = grp, instances = instances, starts = starts, stops = stops }
end

-- Ajusta el alto de la barra segun el modo de separador.
function M.adjust_height(base_h, style_name)
    local mod = Styles.get(style_name or "arrow")
    return base_h + (mod.height_delta or 0)
end

-- Monta la barra completa.
function M.build(theme, spec, registry, srv)
    spec = spec or {}
    local sep_style = spec.style or spec.separator or "arrow"
    local base_h    = spec.height or 22
    local bar_h     = M.adjust_height(base_h, sep_style)
    local gap       = spec.gap or 12

    local left_list,  left_groups  = flatten_list(spec.left)
    local center_list, center_groups = flatten_list(spec.center)
    local right_list, right_groups = flatten_list(spec.right)

    local groups = {}
    for k, v in pairs(left_groups)   do groups[k] = v end
    for k, v in pairs(center_groups) do groups[k] = v end
    for k, v in pairs(right_groups)  do groups[k] = v end

    local side_opts = {
        style = sep_style,
        gap = gap,
        bar_h = bar_h,
    }

    local style_mod = Styles.get(sep_style)
    local root, instances, starts, stops

    if style_mod.layout == "center" then
        -- Fusiona los tres lados en una sola lista centrada.
        local all = {}
        for _, l in ipairs({ left_list, center_list, right_list }) do
            for _, it in ipairs(l) do all[#all + 1] = it end
        end
        local built = build_side(theme, all, registry, groups, side_opts, srv)
        local spacer = function()
            return W.Text.new { text = "", font = "DejaVu Sans 1" }
        end
        root = W.Group.new {
            orientation = "horizontal",
            spacing = 0, padding = 0,
            children = {
                { widget = spacer(), weight = 1 },
                { widget = built.group, weight = 0 },
                { widget = spacer(), weight = 1 },
            },
        }
        instances = built.instances
        starts = built.starts
        stops = built.stops
    else
        local left_b   = build_side(theme, left_list,   registry, groups, side_opts, srv)
        local center_b = build_side(theme, center_list, registry, groups, side_opts, srv)
        local right_b  = build_side(theme, right_list,  registry, groups, side_opts, srv)

        root = W.Group.new {
            orientation = "horizontal",
            spacing = 0, padding = 0,
            children = {
                { widget = left_b.group,   weight = 0 },
                { widget = center_b.group, weight = 1 },
                { widget = right_b.group,  weight = 0 },
            },
        }

        instances = {}
        for k, v in pairs(left_b.instances)   do instances[k] = v end
        for k, v in pairs(center_b.instances) do instances[k] = v end
        for k, v in pairs(right_b.instances)  do instances[k] = v end

        starts, stops = {}, {}
        for _, s in ipairs(left_b.starts)   do starts[#starts + 1] = s end
        for _, s in ipairs(center_b.starts) do starts[#starts + 1] = s end
        for _, s in ipairs(right_b.starts)  do starts[#starts + 1] = s end
        for _, s in ipairs(left_b.stops)    do stops[#stops + 1] = s end
        for _, s in ipairs(center_b.stops)  do stops[#stops + 1] = s end
        for _, s in ipairs(right_b.stops)   do stops[#stops + 1] = s end
    end

    return {
        widget = root,
        height = bar_h,
        sep_style = sep_style,
        groups = groups,
        instances = instances,
        starts = starts,
        stops = stops,
    }
end

return M

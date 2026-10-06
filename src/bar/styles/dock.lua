local Sep = require("bar.separators")
local cairo = require("lib.cairo")

return {
    name = "dock",
    fg_mode = "self",
    layout = "center",
    rounded = { radius = "pill" },
    override_redirect = true,
    visibility = "smart",
    height_delta = 0,
    defaults = {
        position = "bottom",
        height = 44,
        width = 700,
        x = "center",
        margin = { 0, 0, 12, 0 },
        gap = 16,
    },
    draw_bg = function(cr, w, h, T)
        local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
        local sep = T.separator_rgb or { 0.3, 0.3, 0.3 }
        cairo.save(cr)
        cairo.set_operator(cr, cairo.OPERATOR.SOURCE)
        cairo.set_rgb(cr, bg[1], bg[2], bg[3])
        cairo.rounded_rect(cr, 0.5, 0.5, w - 1, h - 1, h / 2)
        cairo.fill(cr)
        cairo.restore(cr)
        cairo.save(cr)
        cairo.set_operator(cr, cairo.OPERATOR.SOURCE)
        cairo.set_rgb(cr, sep[1], sep[2], sep[3])
        cairo.set_line_width(cr, 1)
        cairo.rounded_rect(cr, 0.5, 0.5, w - 1, h - 1, h / 2)
        cairo.stroke(cr)
        cairo.restore(cr)
    end,
    new = function(opts)
        local children = {}
        local self = {}
        function self:emit(item)
            if #children > 0 and (opts.gap or 0) > 0 then
                children[#children + 1] = {
                    widget = Sep.GapSep(opts.gap),
                    weight = 0,
                }
            end
            children[#children + 1] = { widget = item.widget, weight = 0 }
        end
        function self:finish() return children end
        return self
    end,
}

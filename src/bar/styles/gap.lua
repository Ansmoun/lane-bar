local Sep = require("bar.separators")

return {
    name = "gap",
    height_delta = 0,
    defaults = {
        position = "top",
        width = "screen",
        height = 22,
        margin = { 0, 0, 0, 0 },
    },
    new = function(opts)
        local children = {}
        local current_color = opts.bg_hex
        local self = {}

        function self:emit(item)
            local color = item.color
            if color then
                if current_color ~= color and #children > 0 then
                    children[#children + 1] = {
                        widget = Sep.GapSep(opts.gap),
                        weight = 0,
                    }
                end
                children[#children + 1] = {
                    widget = Sep.ColorBox(item.widget, color),
                    weight = 0,
                }
                current_color = color
            else
                if current_color ~= opts.bg_hex and #children > 0 then
                    children[#children + 1] = {
                        widget = Sep.GapSep(opts.gap),
                        weight = 0,
                    }
                end
                children[#children + 1] = { widget = item.widget, weight = 0 }
                current_color = opts.bg_hex
            end
        end

        function self:finish() return children end
        return self
    end,
}

local Sep = require("bar.separators")

return {
    name = "none",
    height_delta = 0,
    defaults = {
        position = "top",
        width = "screen",
        height = 22,
        margin = { 0, 0, 0, 0 },
    },
    new = function(opts)
        local children = {}
        local self = {}

        function self:emit(item)
            local color = item.color
            if color then
                children[#children + 1] = {
                    widget = Sep.ColorBox(item.widget, color),
                    weight = 0,
                }
            else
                children[#children + 1] = { widget = item.widget, weight = 0 }
            end
        end

        function self:finish() return children end
        return self
    end,
}

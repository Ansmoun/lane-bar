local Sep = require("bar.separators")

return {
    name = "island",
    height_delta = 8,
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
            children[#children + 1] = {
                widget = Sep.IslandBox(item.widget, item.color, 4),
                weight = 0,
            }
        end

        function self:finish() return children end
        return self
    end,
}

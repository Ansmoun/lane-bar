local Sep = require("bar.separators")

return {
    name = "minimal",
    fg_mode = "self",
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

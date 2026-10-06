local M = {}
M.arrow       = require("bar.styles.arrow")
M.glyph       = require("bar.styles.glyph")
M.glyph_thick = require("bar.styles.glyph_thick")
M.gap         = require("bar.styles.gap")
M.none        = require("bar.styles.none")
M.underline   = require("bar.styles.underline")
M.island      = require("bar.styles.island")
M.dock        = require("bar.styles.dock")
M.minimal     = require("bar.styles.minimal")

function M.get(name)
    return M[name] or M.arrow
end
return M

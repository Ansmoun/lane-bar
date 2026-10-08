-- themes/init.lua: loader de temas de la barra.
--
-- Un tema es un módulo que devuelve una tabla compatible con
-- layout.lua:
--   {
--     style      = "dock" | "arrow" | ...   -- separador
--     gap        = <px>
--     height     = <px>                     -- opcional
--     position   = "top" | "bottom" | ...   -- opcional
--     margin     = {...}                    -- opcional
--     left, center, right = { ... }         -- contenido
--     draw_bg    = function(cr, w, h, T)    -- opcional
--   }
--
-- El campo draw_bg del tema tiene prioridad sobre el del estilo
-- (styles/<name>.lua). Así un tema puede override el fondo sin
-- duplicar el estilo entero.
--
-- Resolución del nombre:
--   1. Env var LANE_BAR_THEME (override de debug)
--   2. config.bar.theme (default: "dock")
--   3. Fallback: "dock"
--
-- Si el tema pedido no existe o falla, cae a "dock" y loguea.

local log = require("lib.log")

local M = {}

local DEFAULT = "dock"

function M.resolve_name()
    local env = os.getenv("LANE_BAR_THEME")
    if env and env ~= "" then return env end
    local ok, cfg = pcall(function()
        return require("lib.config").get()
    end)
    if ok and cfg and cfg.bar and cfg.bar.theme then
        return cfg.bar.theme
    end
    return DEFAULT
end

function M.load(name)
    name = name or M.resolve_name()
    local ok, mod = pcall(require, "themes." .. name)
    if ok and type(mod) == "table" and (mod.left or mod.right or mod.center) then
        return mod, name
    end
    if name ~= DEFAULT then
        log.warn("bar", "tema '%s' no carga (%s), usando '%s'",
            tostring(name), tostring(mod), DEFAULT)
        local ok2, mod2 = pcall(require, "themes." .. DEFAULT)
        if ok2 and type(mod2) == "table" then
            return mod2, DEFAULT
        end
    end
    error("themes: no se pudo cargar ningún tema (último intento: "
        .. tostring(name) .. ")")
end

function M.list()
    local here = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = here:match("^(.*)/[^/]+$") or "."
    local p = io.popen("ls -1 '" .. dir .. "'/*.lua 2>/dev/null")
    if not p then return {} end
    local out = {}
    for line in p:lines() do
        local base = line:match("([^/]+)%.lua$")
        if base and base ~= "init" then out[#out + 1] = base end
    end
    p:close()
    table.sort(out)
    return out
end

return M

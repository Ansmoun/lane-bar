-- themes/init.lua: loader de temas visuales del launcher.
--
-- Un tema es un módulo que expone M.build(ctx) -> handle. El
-- controlador (tab.lua) le pasa un ctx con el estado y callbacks,
-- y el tema devuelve un handle con el widget y notificaciones.
--
-- Resolución del nombre:
--   1. Env var LANE_LAUNCHER_THEME (override de debug)
--   2. config.launcher.theme (default: "sidebar")
--   3. Fallback: "sidebar"
--
-- Un tema con error de carga cae al fallback y loguea el motivo,
-- para que un tema roto no tumbe el launcher.

local log = require("lib.log")

local M = {}

local DEFAULT = "sidebar"

-- Nombre activo según env/config. No carga el módulo todavía.
function M.resolve_name()
    local env = os.getenv("LANE_LAUNCHER_THEME")
    if env and env ~= "" then return env end
    local ok, cfg = pcall(function()
        return require("lib.config").get()
    end)
    if ok and cfg and cfg.launcher and cfg.launcher.theme then
        return cfg.launcher.theme
    end
    return DEFAULT
end

-- Carga y devuelve el módulo del tema. Cae a DEFAULT si el pedido
-- no existe o falla al cargar.
function M.load(name)
    name = name or M.resolve_name()
    local ok, mod = pcall(require, "launcher.themes." .. name)
    if ok and type(mod) == "table" and type(mod.build) == "function" then
        return mod, name
    end
    if name ~= DEFAULT then
        log.warn("launcher", "tema '%s' no carga (%s), usando '%s'",
            tostring(name), tostring(mod), DEFAULT)
        local ok2, mod2 = pcall(require, "launcher.themes." .. DEFAULT)
        if ok2 and type(mod2) == "table" then
            return mod2, DEFAULT
        end
    end
    error("themes: no se pudo cargar ningún tema (último intento: "
        .. tostring(name) .. ")")
end

-- Lista de temas disponibles (archivos .lua en este directorio,
-- excluyendo init.lua).
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

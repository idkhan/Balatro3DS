--- Lightweight SFX helpers: load cached sources and play a random pick.
local M = {}

local cache = {}

---@param path string
---@return love.Source|nil
local function get_source(path)
    if not path or path == "" then return nil end
    local cached = cache[path]
    if cached then return cached end
    if not love or not love.audio then return nil end
    local ok, src = pcall(love.audio.newSource, path, "static")
    if ok and src then
        cache[path] = src
        return src
    end
    return nil
end

--- Collect paths from variadic args or a single table of strings.
local function normalize_paths(...)
    local args = { ... }
    if #args == 1 and type(args[1]) == "table" then
        return args[1]
    end
    return args
end

--- Pick one path at random, load (cached), stop + play.
--- Usage: Sfx.play_random("a.ogg", "b.ogg") or Sfx.play_random({ "a.ogg", "b.ogg" })
---@param ... string|string[]
---@return boolean played True if a source was found and :play() was called
function M.play_random(...)
    local paths = normalize_paths(...)
    local n = #paths
    if n == 0 then return false end

    local idx = love.math.random(1, n)
    local path = paths[idx]
    local src = get_source(path)
    if not src or not src.play then return false end
    src:stop()
    src:play()
    return true
end

function M.play(path)
    local src = get_source(path)
    if not src or not src.play then return false end
    src:stop()
    src:play()
    return true
end

--- Drop cached sources (e.g. hot reload). Rarely needed.
function M.clear_cache()
    cache = {}
end

return M

--- Lightweight SFX helpers: load cached sources and play a random pick.
local M = {}

local cache = {}

--- All static SFX paths used in this project (decode at startup via `preload_game_sounds`).
local GAME_SFX_PATHS = {
    "resources/sounds/generic1.ogg",
    "resources/sounds/cardSlide1.ogg",
    "resources/sounds/cardSlide2.ogg",
    "resources/sounds/card1.ogg",
    "resources/sounds/card3.ogg",
    "resources/sounds/chips1.ogg",
    "resources/sounds/chips2.ogg",
    "resources/sounds/coin1.ogg",
    "resources/sounds/coin2.ogg",
    "resources/sounds/coin3.ogg",
    "resources/sounds/coin4.ogg",
    "resources/sounds/coin5.ogg",
    "resources/sounds/coin6.ogg",
    "resources/sounds/coin7.ogg",
    "resources/sounds/multhit1.ogg",
    "resources/sounds/multhit2.ogg",
}

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

--- Load (or no-op if already cached) every path into `cache`. Call from `love.load` to avoid first-play stalls.
---@param ... string|string[]
---@return integer loaded Count of paths successfully opened.
function M.preload(...)
    local paths = normalize_paths(...)
    local ok = 0
    for _, path in ipairs(paths) do
        if path and path ~= "" and get_source(path) then
            ok = ok + 1
        end
    end
    return ok
end

--- Preload the bundled game SFX list (`GAME_SFX_PATHS`). Does not preload music (use `"stream"` separately).
function M.preload_game_sounds()
    return M.preload(GAME_SFX_PATHS)
end

--- Drop cached sources (e.g. hot reload). Rarely needed.
function M.clear_cache()
    cache = {}
end

function M.play_money()
    M.play_random("resources/sounds/coin1.ogg", "resources/sounds/coin2.ogg", "resources/sounds/coin3.ogg", "resources/sounds/coin4.ogg", "resources/sounds/coin5.ogg", "resources/sounds/coin6.ogg", "resources/sounds/coin7.ogg")
end

function M.play_mult()
    M.play("resources/sounds/multhit1.ogg")
end

function M.play_mult2()
    M.play("resources/sounds/multhit2.ogg")
end

function M.play_chips()
    M.play_random("resources/sounds/chips1.ogg", "resources/sounds/chips2.ogg")
end

return M

local path = (...):gsub("%.config", "")
local assert = require(path .. ".libraries.assert")

---@class config
---@field private _console string
---@field private _scale integer
---@field private _emulateJoystick boolean
local config = {}
config.__index = config

config._console = ""
config._scale = 1
config._emulateJoystick = false
config._loaded = false
config._keybinds = {}

-- Switch-specific
config._defaultDocked = false
config._docked = config._defaultDocked

-- Wii U-specific
config._defaultMode = "720p"
config._mode = config._defaultMode

local consoles = {
    ["3ds"]    = "ctr",
    ["switch"] = "hac",
    ["wiiu"]   = "cafe",
}

local wiiu_modes = {
    "1080p",
    "720p",
    "480p"
}

-- Credit: https://shorturl.at/qyLW7
local function find_match(t, f)
    for key, value in pairs(t) do
        if f(key, value) then
            return key
        end
    end
    return nil
end

-- Credit: Ice Baron
local function find_match_value(t, f)
    for key, value in pairs(t) do
        if f(key, value) then
            return value
        end
    end
    return nil
end

-- Credit: https://shorturl.at/csvT6
local function round(v)
    if v < 0 then
        return math.ceil(v - 0.5)
    end
    return math.floor(v + 0.5)
end

-- Credit:https://shorturl.at/kqKMZ
local function title_case(s)
    s = s:gsub("%s%l", string.upper)
    s = s:gsub("^%l", string.upper)

    return s
end

local function clamp(value, low, high)
    value = round(value)
    return math.max(low, math.min(value, high))
end

local function nil_or_whitespace(s)
    return s == nil or #s == 0 or s:match("%s")
end

---Initialize the configuration for later. \
---If args.console is `nil`, disable nest.
---@param args { scale?: integer, console: string, emulateJoystick: boolean, docked?: boolean, mode?: string }
function config.set(args)
    if nil_or_whitespace(args.console) then
        print("!")
        config._loaded = false
        return false
    end

    config._scale   = clamp(args.scale or 1, 1, 3)
    config._console = find_match(consoles, function(key, value)
        if args.console == key or args.console == value then
            return true
        end
    end)
    print(config._console)

    config._emulateJoystick = args.emulateJoystick or true

    if config._console == "switch" then
        config._docked = args.docked or config._defaultDocked
    elseif config._console == "wiiu" then
        config._mode = find_match_value(wiiu_modes, function(_, value)
            if args.mode == value then
                return true
            end
        end) or config._defaultMode
    end

    assert:some(config._console, "Console was not specified.")

    config._loaded = true
    return true
end

---Gets a specific config item
---@param name string
---@return string|integer|love.Joystick
function config.get(name)
    local item = config["_" .. name]
    return assert:some(item, "Config field does not exist or was nil.")
end

function config.getName()
    if config._console == "3ds" then
        return config._console:upper()
    end
    return title_case(config._console)
end

----
--- Keybindings
----

-- Credit: https://shorturl.at/e1249
local function parseSource(source)
    return source:match('(.+):(.+)')
end

-- Credit: https://shorturl.at/dnCIM
local function parseAxis(value)
    return value:match('(.+)([%+%-])')
end

local function getKeybindings()
    if love.filesystem.getInfo("bindings.lua", "file") then
        return love.filesystem.load("bindings.lua")()
    end
    return require(path .. ".data.bindings")
end

function config.parseBindingInfo()
    local data = getKeybindings()

    for key, binding in pairs(data) do
        local source, value = parseSource(binding)

        if source ~= "button" then
            local axis, direction = parseAxis(value)
            config._keybinds[key] = { false, { source = source, value = value, axis = axis, direction = direction or "" } }
        else
            config._keybinds[key] = { true, { source = source, value = value } }
        end
    end
end

function config.getKeybinding(key)
    return config._keybinds[key]
end

return config

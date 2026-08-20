--- Console identification.
---
--- Three different questions get asked around this port and they have three different
--- answers, so they live here rather than being re-derived at each call site:
---
---  * "Is this the 3DS runtime?" — LövePotion sets `love._console` from the CMake define
---    `__CONSOLE__`, which on the 3DS target is the string `"3DS"` (uppercase; see
---    `CMakeLists.txt:42` in the LövePotion checkout). Upstream's own Lua compares it
---    case-insensitively (`include/scripts/nogame.lua:19`), and `nest` reports `"3DS"`
---    too (`nest/config.lua:127-129`), so every comparison here folds case. Comparing
---    against a lowercase `"3ds"` silently answers "no" on hardware, which is how the
---    edition meshes ended up using desktop UV math on-device.
---
---  * "Is this real hardware?" — `nest` claims the same console name while running on
---    desktop LÖVE, so the name alone cannot tell them apart. LövePotion has no
---    `love.graphics.newShader` at all (there is no such function anywhere in its
---    sources), while every desktop LÖVE does; its absence is the reliable signature.
---    This is the question texture geometry cares about, because only the real GPU pads
---    textures to powers of two.
---
---  * "Is this an Old 3DS?" — an Old 3DS has 2 ARM11 cores, a New 3DS has more
---    (3dbrew, "New Nintendo 3DS"). Only meaningful on hardware; desktop and nest are
---    treated as capable so effects can be tuned there.
---
--- Answers are cached after the first call: none of them can change during a run, and
--- they sit on paths that run per frame.

local Console = {}

local NAME_3DS = "3ds"

local is_3ds_cached = nil
local is_hardware_cached = nil
local is_new_3ds_cached = nil

--- Reported console name, lowercased, or nil off-console.
---@return string|nil
function Console.name()
    local raw = love and love._console
    if type(raw) ~= "string" or raw == "" then return nil end
    return raw:lower()
end

--- Whether the 3DS runtime is reporting itself. True under `nest` as well as on hardware.
---@return boolean
function Console.is_3ds()
    if is_3ds_cached == nil then
        is_3ds_cached = (Console.name() == NAME_3DS)
    end
    return is_3ds_cached
end

--- Whether this is a physical 3DS rather than `nest` on desktop. Gate texture geometry,
--- memory budgets and anything else with a hardware-only reason on this.
---@return boolean
function Console.is_hardware()
    if is_hardware_cached == nil then
        is_hardware_cached = Console.is_3ds()
            and not (love and love.graphics and love.graphics.newShader)
    end
    return is_hardware_cached
end

--- Whether the extra CPU budget of a New 3DS (804 MHz, >2 cores) is available. Desktop
--- and `nest` answer true so effects stay visible while tuning them there.
---@return boolean
function Console.is_new_3ds()
    if is_new_3ds_cached == nil then
        if Console.is_hardware() then
            local n = love.system and love.system.getProcessorCount and love.system.getProcessorCount()
            is_new_3ds_cached = (n ~= nil and n ~= 2)
        else
            is_new_3ds_cached = true
        end
    end
    return is_new_3ds_cached
end

--- Drop the cached answers. Tests swap `love` out from under this module; nothing in
--- the game needs it.
function Console.reset_cache()
    is_3ds_cached = nil
    is_hardware_cached = nil
    is_new_3ds_cached = nil
end

return Console

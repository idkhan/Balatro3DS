--- Console identification.
---
--- These three probes gate texture UV math, the ambient audio beds and ZL/ZR. They used
--- to be written out at each call site as `love._console == "3ds"`, which is never true:
--- LövePotion compiles `__CONSOLE__="3DS"` (uppercase) and nest reports the same string.
--- Every one of them therefore took the desktop branch on hardware, which is what
--- squashed edition meshes into the corner of the card.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local Console = require("console")

--- Run `fn` against a swapped-in `love`, with the probe caches cleared either side.
---@param fake table|nil
---@param fn fun()
local function with_love(fake, fn)
    local real = _G.love
    _G.love = fake
    Console.reset_cache()
    local ok, err = pcall(fn)
    _G.love = real
    Console.reset_cache()
    if not ok then error(err, 0) end
end

--- The runtime as it actually presents itself on a console.
---@param cores number|nil
---@return table
local function hardware_love(cores)
    return {
        _console = "3DS",
        graphics = {},
        system = { getProcessorCount = function() return cores end },
    }
end

suite.test("the console name is matched case-insensitively", function()
    bootstrap.load()

    with_love({ _console = "3DS" }, function()
        T.assert_true(Console.is_3ds(), "LövePotion's own __CONSOLE__ define")
    end)
    with_love({ _console = "3ds" }, function()
        T.assert_true(Console.is_3ds(), "lowercase")
    end)
    with_love({ _console = "Switch" }, function()
        T.assert_false(Console.is_3ds(), "another console")
    end)
    with_love({}, function()
        T.assert_false(Console.is_3ds(), "desktop LÖVE sets no console name")
    end)
    with_love({ _console = "" }, function()
        T.assert_false(Console.is_3ds(), "an empty name is not a console")
    end)
end)

suite.test("hardware is told from nest by newShader, not by the name", function()
    bootstrap.load()

    with_love(hardware_love(2), function()
        T.assert_true(Console.is_hardware(), "no newShader on ctr")
    end)
    -- nest claims "3DS" while running on desktop LÖVE.
    with_love({ _console = "3DS", graphics = { newShader = function() end } }, function()
        T.assert_false(Console.is_hardware(), "nest is not hardware")
    end)
    with_love({ graphics = { newShader = function() end } }, function()
        T.assert_false(Console.is_hardware(), "plain desktop")
    end)
end)

suite.test("two ARM11 cores means Old 3DS, and only on hardware", function()
    bootstrap.load()

    with_love(hardware_love(2), function()
        T.assert_false(Console.is_new_3ds(), "Old 3DS")
    end)
    with_love(hardware_love(4), function()
        T.assert_true(Console.is_new_3ds(), "New 3DS")
    end)
    with_love(hardware_love(nil), function()
        T.assert_false(Console.is_new_3ds(), "an unanswerable probe is treated as the weaker console")
    end)
    with_love({ _console = "3DS", graphics = { newShader = function() end } }, function()
        T.assert_true(Console.is_new_3ds(), "nest keeps the effects on for tuning")
    end)
end)

suite.test("the headless stub reads as desktop, not as a console", function()
    local love = bootstrap.load()
    Console.reset_cache()

    T.assert_eq(love._console, "3DS", "the stub reports what LövePotion reports")
    T.assert_true(Console.is_3ds(), "so the name probe fires")
    T.assert_false(Console.is_hardware(), "but the suite is not running on a 3DS")
    T.assert_true(Console.is_new_3ds(), "so nothing is gated off in tests")
end)

return suite

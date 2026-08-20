local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()
local love = bootstrap.load()

local Console = require("console")
local Stereo = require("stereo")

--- `Stereo.supported` is hardware-gated, so exercising `update` means standing in for a
--- console: `Console.is_hardware` reads the absence of `love.graphics.newShader`
--- (`console.lua:56-62`), and the stub models the desktop side by providing one.
--- `bottom_width` stands in for the runtime's answer to `getWidth("bottom")` once stereo is
--- off: 320 on a patched runtime, 400 on one still indexing the screen list by id.
local function with_fake_hardware(depth_source, body, bottom_width)
    local original_shader = love.graphics.newShader
    local original_get, original_set = love.graphics.get3D, love.graphics.set3D
    local original_depth, original_width = love.graphics.getDepth, love.graphics.getWidth

    local calls = {}
    local enabled = true
    love.graphics.newShader = nil
    love.graphics.get3D = function() return enabled end
    love.graphics.set3D = function(v)
        enabled = v
        calls[#calls + 1] = v
    end
    love.graphics.getDepth = function() return depth_source() end
    love.graphics.getWidth = function(name)
        if name == "bottom" then
            -- An unpatched runtime only misreports while stereo is off.
            if enabled then return 320 end
            return bottom_width or 320
        end
        return 400
    end
    Console.reset_cache()
    Stereo.reset()

    local ok, err = pcall(body, calls, function() return enabled end)

    love.graphics.newShader = original_shader
    love.graphics.get3D, love.graphics.set3D = original_get, original_set
    love.graphics.getDepth, love.graphics.getWidth = original_depth, original_width
    Console.reset_cache()
    Stereo.reset()

    if not ok then error(err, 0) end
end

suite.test("the slider at rest turns stereo off", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls, is_on)
        Stereo.update()
        T.assert_eq(is_on(), false, "stereo should switch off at slider zero")
        T.assert_eq(#calls, 1, "exactly one mode change")
    end)
end)

--- The mode change tears down and rebuilds the framebuffers
--- (`renderer_ext.hpp:194-199`), so a slider resting on the boundary must not be able to
--- drive one every frame. That is what the split thresholds buy.
suite.test("a slider dithering on the boundary does not thrash the framebuffers", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls)
        Stereo.update()
        T.assert_eq(#calls, 1, "first call switches off")

        -- Between OFF_THRESHOLD and ON_THRESHOLD: neither edge should fire.
        for _ = 1, 20 do
            depth = Stereo.OFF_THRESHOLD + (Stereo.ON_THRESHOLD - Stereo.OFF_THRESHOLD) * 0.5
            Stereo.update()
            depth = Stereo.OFF_THRESHOLD * 0.5
            Stereo.update()
        end
        T.assert_eq(#calls, 1, "no further mode changes inside the hysteresis band")
    end)
end)

suite.test("pushing the slider up turns stereo back on", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls, is_on)
        Stereo.update()
        T.assert_eq(is_on(), false, "off at rest")

        depth = 0.5
        Stereo.update()
        T.assert_eq(is_on(), true, "on once the slider clears the threshold")

        depth = 0
        Stereo.update()
        T.assert_eq(is_on(), false, "off again when it comes back down")
        T.assert_eq(#calls, 3, "one mode change per real crossing")
    end)
end)

suite.test("the decision is hysteretic in both directions", function()
    -- Rising edge needs to clear ON_THRESHOLD...
    T.assert_eq(Stereo.decide(false, Stereo.ON_THRESHOLD), false, "at the on threshold, stay off")
    T.assert_eq(Stereo.decide(false, Stereo.ON_THRESHOLD + 0.01), true, "past it, switch on")
    -- ...but once on, it only needs to stay above the lower one.
    T.assert_eq(Stereo.decide(true, Stereo.ON_THRESHOLD - 0.01), true, "stay on below the on threshold")
    T.assert_eq(Stereo.decide(true, Stereo.OFF_THRESHOLD), false, "at the off threshold, switch off")
end)

suite.test("a nil or absent slider reading is treated as zero", function()
    T.assert_eq(Stereo.decide(true, nil), false, "nil depth reads as parked")
    T.assert_eq(Stereo.decide(false, nil), false, "and does not switch stereo on")
end)

--- The safety net. `Screen::BOTTOM` is id 2 and, with stereo off, the runtime's screen list
--- has two entries -- so an unpatched `GetScreenInfo(id)` indexes past the end and answers
--- with the 400px left eye. Tooltip wrapping and drag clamping both derive from that width,
--- so the gate must not stay off on a runtime that gets it wrong.
suite.test("the gate backs itself out on a runtime that misreports the bottom width", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls, is_on)
        Stereo.update()
        T.assert_eq(is_on(), true, "stereo is restored after a failed probe")
        T.assert_eq(Stereo.is_disabled(), true, "and the gate disables itself")
        T.assert_deep_eq(calls, { false, true }, "off, probed, back on")

        -- And it stays out of the way from then on, whatever the slider does.
        depth = 0.9
        Stereo.update()
        depth = 0
        Stereo.update()
        T.assert_eq(#calls, 2, "no further mode changes once disabled")
        T.assert_eq(is_on(), true, "stereo left on")
    end, 400)
end)

suite.test("a correct bottom width lets the gate stay off", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls, is_on)
        Stereo.update()
        T.assert_eq(is_on(), false, "stereo stays off on a patched runtime")
        T.assert_eq(Stereo.is_disabled(), false, "the gate stays live")
        T.assert_eq(#calls, 1, "and the probe cost no extra mode change")
    end, 320)
end)

--- The probe runs once, not on every switch off.
suite.test("the width probe only runs on the first switch off", function()
    local depth = 0
    with_fake_hardware(function() return depth end, function(calls)
        Stereo.update()
        for _ = 1, 5 do
            depth = 0.9; Stereo.update()
            depth = 0;   Stereo.update()
        end
        T.assert_eq(#calls, 11, "one initial off plus five on/off pairs, no probe re-entry")
    end, 320)
end)

--- Desktop and `nest` must be left exactly as they are: `nest` names the top screen "left"
--- either way and its `getDepth` stub latches to zero once `set3D(false)` lands
--- (`nest/modules/overrides.lua:88-95`), which would make the parallax paths untestable.
suite.test("nothing happens off hardware", function()
    Console.reset_cache()
    Stereo.reset()
    local touched = false
    local original_set = love.graphics.set3D
    love.graphics.set3D = function() touched = true end
    Stereo.update()
    love.graphics.set3D = original_set
    Console.reset_cache()
    Stereo.reset()

    T.assert_eq(touched, false, "set3D should not be called under the desktop stub")
    T.assert_eq(Stereo.supported(), false, "and the gate should report itself unsupported")
end)

return suite

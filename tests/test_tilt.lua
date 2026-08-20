--- Accelerometer tilt: the pipeline in `tilt.lua`, and how `Game:get_shake_offset` composes it
--- with the gameplay shake.
---
--- The tuning is fixed and was found on hardware, so nothing here asserts a feel. What is testable
--- is that each stage does what it claims: that the angles do not depend on how steeply the console
--- is held, that the neutral tracks, that the deadzone is continuous, and that nothing here can
--- move the board further than its clamp.
local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
local Tilt = require("tilt")

-- The sensor cases reach for `love.joystick` directly, so the stub has to be in place before any of
-- them run rather than at the first `bootstrap.new_game`.
bootstrap.load()

local suite = T.suite("tilt")

--- Gravity vector that reads back as exactly these angles - the inverse of
--- `Tilt.angles_from_gravity`. `scale` stands in for the raw counts the 3DS reports (~512 per g);
--- nothing downstream should care what it is.
local function gravity(roll, pitch, scale)
    scale = scale or 512
    return scale * math.sin(roll),
        scale * math.cos(roll) * math.cos(pitch),
        scale * math.cos(roll) * math.sin(pitch)
end

--- A joystick that answers the sensor calls. `Tilt` reaches the accelerometer through the joystick
--- object because LovePotion's `love.sensor` binding does not return samples; see `tilt.lua`.
local function fake_joystick()
    local js = { enabled = {}, sample = { 0, 512, 0 } }
    function js:setSensorEnabled(sensor, on) self.enabled[sensor] = on and true or false end
    function js:isSensorEnabled(sensor) return self.enabled[sensor] == true end
    function js:hasSensor() return true end
    function js:getSensorData() return self.sample[1], self.sample[2], self.sample[3] end
    return js
end

--- Run `fn` with the sensor present. Restores `love.joystick` afterwards, and clears the module's
--- cached joystick either way: it is a singleton, like `Sfx` and `PerformanceLab`.
local function with_joystick(fn, keep_inactive)
    local original = love.joystick.getJoysticks
    local js = fake_joystick()
    love.joystick.getJoysticks = function() return { js } end
    Tilt.reset_all()
    local ok, err = pcall(function()
        if not keep_inactive then Tilt.set_active(true) end
        fn(js)
    end)
    love.joystick.getJoysticks = original
    Tilt.reset_all()
    if not ok then error(err, 0) end
end

--- Feed one pose for `frames` frames, returning the final offset.
local function settle(js, roll, pitch, frames)
    local ox, oy = 0, 0
    for _ = 1, (frames or 120) do
        js.sample = { gravity(roll, pitch) }
        Tilt.on_sample(js.sample[1], js.sample[2], js.sample[3])
        ox, oy = Tilt.update(1 / 60)
    end
    return ox, oy
end

local RAD = math.pi / 180

--------------------------------------------------------------------------------
-- Angles
--------------------------------------------------------------------------------

suite.test("angles read back whatever pose was built", function()
    for _, pose in ipairs({ { 0, 0 }, { 0.2, -0.9 }, { -0.35, 1.2 }, { 0.7, 0.1 } }) do
        local roll, pitch = Tilt.angles_from_gravity(gravity(pose[1], pose[2]))
        T.assert_near(roll, pose[1], 1e-6, "roll")
        T.assert_near(pitch, pose[2], 1e-6, "pitch")
    end
end)

--- The whole reason for measuring angles rather than raw components: a 3DS is held anywhere from
--- flat on a table to almost upright, and the same wrist roll has to mean the same thing at both.
suite.test("a roll reads the same at any base pitch", function()
    local turn = 10 * RAD
    for _, base in ipairs({ 0, 0.5, 1.0, 1.4 }) do
        local a = select(1, Tilt.angles_from_gravity(gravity(0, base)))
        local b = select(1, Tilt.angles_from_gravity(gravity(turn, base)))
        T.assert_near(b - a, turn, 1e-6, "roll delta at base pitch " .. base)
    end
end)

suite.test("the magnitude of the sample does not matter", function()
    local r1, p1 = Tilt.angles_from_gravity(gravity(0.3, 0.6, 512))
    local r2, p2 = Tilt.angles_from_gravity(gravity(0.3, 0.6, 9.81))
    T.assert_near(r1, r2, 1e-6, "roll is scale free")
    T.assert_near(p1, p2, 1e-6, "pitch is scale free")
end)

suite.test("a zero-length sample has no direction", function()
    T.assert_nil((Tilt.angles_from_gravity(0, 0, 0)), "freefall or a dead read yields no angle")
end)

--------------------------------------------------------------------------------
-- Deadzone and rounding
--------------------------------------------------------------------------------

suite.test("the deadzone is a soft one", function()
    local dz = 0.2
    T.assert_eq(Tilt.soft_deadzone(0.1, dz), 0, "inside the deadzone is rest")
    T.assert_eq(Tilt.soft_deadzone(-0.2, dz), 0, "the edge is still rest")
    -- The point of rescaling: leaving the deadzone starts from zero rather than stepping to 0.2.
    T.assert_near(Tilt.soft_deadzone(0.21, dz), 0.0125, 1e-6, "just past the edge is barely off rest")
    T.assert_near(Tilt.soft_deadzone(0.6, dz), 0.5, 1e-6, "and the range is rescaled to full")
    T.assert_eq(Tilt.soft_deadzone(1.5, dz), 1, "beyond full range clamps")
    T.assert_eq(Tilt.soft_deadzone(-1.5, dz), -1, "in both directions")
end)

suite.test("a zero deadzone passes everything through", function()
    T.assert_near(Tilt.soft_deadzone(0.3, 0), 0.3, 1e-6)
    T.assert_eq(Tilt.soft_deadzone(2, 0), 1, "still clamped")
end)

--- A slow value resting on a pixel boundary would otherwise alternate forever, which on a 240p
--- panel is the board vibrating.
suite.test("rounding holds its pixel until the value has moved off it", function()
    T.assert_eq(Tilt.hysteretic_round(0.5, 0), 0, "half a pixel is not enough to move")
    T.assert_eq(Tilt.hysteretic_round(0.7, 0), 1, "but most of one is")
    T.assert_eq(Tilt.hysteretic_round(0.5, 1), 1, "and it stays there on the way back")
    T.assert_eq(Tilt.hysteretic_round(0.3, 1), 0, "until it has properly left")
end)

--------------------------------------------------------------------------------
-- Pipeline
--------------------------------------------------------------------------------

suite.test("the neutral is wherever the console is being held", function()
    with_joystick(function(js)
        -- An awkward pose, held steady. Nobody holds a 3DS flat, and the effect has to be at rest
        -- in whatever pose it is switched on in.
        local ox, oy = settle(js, 0.25, 0.8, 180)
        T.assert_eq(ox, 0, "no x offset at the calibrated pose")
        T.assert_eq(oy, 0, "no y offset at the calibrated pose")
    end)
end)

suite.test("tilting moves the board against the tilt", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        -- Sampled right after the lean, before the neutral has had time to absorb it.
        local ox = select(1, settle(js, 25 * RAD, 0.7, 30))
        T.assert_true(ox < 0, "rolling right slides the board left")
        -- Cycling the sensor re-takes the neutral, which is the only way back to a known rest.
        Tilt.set_active(false)
        Tilt.set_active(true)
        settle(js, 0, 0.7, 60)
        local ox2 = select(1, settle(js, -25 * RAD, 0.7, 30))
        T.assert_true(ox2 > 0, "and rolling left slides it right")
    end)
end)

suite.test("a tilt inside the deadzone does not move the board", function()
    with_joystick(function(js)
        -- 15% of an 18 degree range is under three degrees; one degree is well inside it.
        settle(js, 0, 0.7, 60)
        local ox, oy = settle(js, 1 * RAD, 0.7, 30)
        T.assert_eq(ox, 0, "a degree of hand tremor is not a lean")
        T.assert_eq(oy, 0)
    end)
end)

suite.test("the offset never exceeds its range", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        -- Far past full deflection, on both axes at once. 4.5 px is the clamp, so 5 is the first
        -- pixel it must never reach.
        local ox, oy = settle(js, 80 * RAD, 0.7 + 80 * RAD, 40)
        T.assert_true(math.abs(ox) <= 5, "x is clamped, got " .. ox)
        T.assert_true(math.abs(oy) <= 5, "y is clamped, got " .. oy)
    end)
end)

suite.test("the board springs toward a new pose instead of snapping", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        -- One frame at full deflection: the spring should have travelled a fraction of the way.
        js.sample = { gravity(30 * RAD, 0.7) }
        Tilt.on_sample(js.sample[1], js.sample[2], js.sample[3])
        local after_one = math.abs(select(1, Tilt.update(1 / 60)))
        local settled = math.abs(select(1, settle(js, 30 * RAD, 0.7, 30)))
        T.assert_true(settled > 0, "it does get there")
        T.assert_true(after_one < settled, "but not in one frame")
    end)
end)

--- The single most important behaviour for anyone not sitting upright at a desk: the effect answers
--- changes in pose, not absolute pose.
suite.test("a held lean becomes the new neutral", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        local held = math.abs(select(1, settle(js, 30 * RAD, 0.7, 30)))
        T.assert_true(held > 0, "the lean registers")
        -- Fifteen seconds of holding the same pose, at a 3 s time constant.
        local later = math.abs(select(1, settle(js, 30 * RAD, 0.7, 900)))
        T.assert_eq(later, 0, "and is absorbed if it is held")
    end)
end)

suite.test("a suspend does not count as one enormous frame", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        local before = select(1, settle(js, 12 * RAD, 0.7, 10))
        -- The HOME menu, or an SD write. Letting this through would drive every exponential to its
        -- target and snap the neutral to a pose the player was never in.
        js.sample = { gravity(12 * RAD, 0.7) }
        Tilt.on_sample(js.sample[1], js.sample[2], js.sample[3])
        local after = select(1, Tilt.update(5.0))
        T.assert_true(math.abs(after - before) <= 1, "the board does not jump across a suspend")
    end)
end)

suite.test("switching the sensor off settles the board rather than dropping it", function()
    with_joystick(function(js)
        settle(js, 0, 0.7, 60)
        local leaning = math.abs(select(1, settle(js, 40 * RAD, 0.7, 30)))
        T.assert_true(leaning > 0, "the board is off centre")

        Tilt.set_active(false)
        T.assert_true(math.abs(select(1, Tilt.update(1 / 60))) > 0,
            "one frame later it is still on its way back")
        local ox
        for _ = 1, 240 do ox = select(1, Tilt.update(1 / 60)) end
        T.assert_eq(ox, 0, "and it does come to rest at centre")
    end)
end)

suite.test("a resting pose does not flicker between pixels", function()
    with_joystick(function(js)
        local last = select(1, settle(js, 0, 0.7, 30))
        -- Hold a lean and watch the committed pixel while the neutral creeps through it. Every
        -- crossing must be a single commit, never an oscillation.
        local flips = 0
        for i = 1, 600 do
            js.sample = { gravity(9 * RAD, 0.7) }
            Tilt.on_sample(js.sample[1], js.sample[2], js.sample[3])
            local ox = select(1, Tilt.update(1 / 60))
            if ox ~= last then
                flips = flips + 1
                last = ox
            end
            T.assert_true(flips <= 6, "the pixel changed " .. flips .. " times by frame " .. i)
        end
    end)
end)

suite.test("with no accelerometer there is nothing to enable and no offset", function()
    local original = love.joystick.getJoysticks
    love.joystick.getJoysticks = function() return {} end
    Tilt.reset_all()
    T.assert_false(Tilt.supported(), "nothing to read")
    T.assert_false(Tilt.set_active(true), "nothing to enable")
    T.assert_eq(select(1, Tilt.update(1 / 60)), 0, "and no offset comes out")
    love.joystick.getJoysticks = original
    Tilt.reset_all()
end)

suite.test("support is reported without powering the sensor", function()
    with_joystick(function(js)
        T.assert_true(Tilt.supported(), "the accelerometer is there")
        T.assert_false(Tilt.is_active(), "but asking did not switch it on")
        T.assert_nil(js.enabled.accelerometer)
    end, true)
end)

--------------------------------------------------------------------------------
-- Game integration
--------------------------------------------------------------------------------

suite.test("the tilt offset only reaches the board when the setting is on", function()
    local g = bootstrap.new_game()
    Tilt.reset_all()
    g.SETTINGS.SCREENSHAKE = 0
    g.SETTINGS.REDUCED_MOTION = false
    g.jiggle, g._jiggle_t, g._room_drift_t = 0, 0, 0
    -- Stand in for a settled lean; `update_shake` is what normally writes these.
    g._tilt_x, g._tilt_y = 4, -3

    g.SETTINGS.TILT = false
    T.assert_true(math.abs(select(1, g:get_shake_offset())) <= 1, "off leaves only the idle drift")

    g.SETTINGS.TILT = true
    local tx, ty = g:get_shake_offset()
    T.assert_true(tx >= 3, "the lean is applied, got " .. tx)
    T.assert_true(ty <= -2, "on both axes, got " .. ty)

    g.SETTINGS.REDUCED_MOTION = true
    T.assert_eq(select(1, g:get_shake_offset()), 0, "reduced motion stills the tilt too")
end)

--- Screenshake keeps its own 0-100 slider as the reference has it; the tilt toggle must not have
--- become a second switch for it.
suite.test("the tilt setting does not gate the gameplay shake", function()
    local g = bootstrap.new_game()
    Tilt.reset_all()
    g.SETTINGS.SCREENSHAKE = 100
    g.SETTINGS.REDUCED_MOTION = false
    g.SETTINGS.TILT = false
    g._tilt_x, g._tilt_y = 0, 0

    local peak = 0
    g.jiggle, g._jiggle_t, g._room_drift_t = 0, 0, 0
    g:shake(3)
    for _ = 1, 12 do
        g:update_shake(0.05)
        local ox, oy = g:get_shake_offset()
        peak = math.max(peak, math.abs(ox), math.abs(oy))
    end
    T.assert_true(peak > 1, "the shake still runs with tilt off")
end)

suite.test("the sensor follows the setting and reduced motion", function()
    local original = love.joystick.getJoysticks
    local js = fake_joystick()
    love.joystick.getJoysticks = function() return { js } end
    Tilt.reset_all()

    local g = bootstrap.new_game()
    g:set_tilt_enabled(false)
    T.assert_false(Tilt.is_active(), "off means the sensor is down")
    g:set_tilt_enabled(true)
    T.assert_true(Tilt.is_active(), "on powers it up")
    T.assert_true(js.enabled.accelerometer, "through the joystick, not love.sensor")
    g:set_reduced_motion(true)
    T.assert_false(Tilt.is_active(), "reduced motion takes it back down")
    g:set_reduced_motion(false)
    T.assert_true(Tilt.is_active(), "and clearing it brings it back")
    g:set_tilt_enabled(false)
    T.assert_false(js.enabled.accelerometer, "an unused sensor is not left powered")

    love.joystick.getJoysticks = original
    Tilt.reset_all()
end)

suite.test("the tilt setting persists", function()
    local g = bootstrap.new_game()
    Tilt.reset_all()

    T.assert_true(g:normalize_settings({}).TILT, "it ships on")
    g:set_tilt_enabled(false)
    T.assert_false(g:snapshot_settings().TILT)
    T.assert_false(g:normalize_settings(g:snapshot_settings()).TILT)
    g:set_tilt_enabled(true)
    T.assert_true(g:normalize_settings(g:snapshot_settings()).TILT)
    -- A settings file from the build that had a tuning table under this key, or any other junk.
    T.assert_true(g:normalize_settings({ TILT = { max_px = 3 } }).TILT, "junk falls back to the default")
end)

--------------------------------------------------------------------------------
-- Settings page
--------------------------------------------------------------------------------

--- The page is drawn twice: the focus ring is decided from rects the same draw publishes, so a
--- control that registers itself after asking whether it is focused can never highlight.
suite.test("the settings page carries both toggles and reaches them by pad", function()
    local original = love.joystick.getJoysticks
    love.joystick.getJoysticks = function() return { fake_joystick() } end
    Tilt.reset_all()

    local g = bootstrap.new_game()
    g.STATE = g.STATES.PAUSED
    g._pause_show_settings = true
    g._pause_settings_tab = "general"
    T.assert_no_error(function() g:draw_bottom_pause() end, "the settings page draws")
    g:draw_bottom_pause()

    local kinds = {}
    for _, t in ipairs(g:build_pause_focus_targets()) do kinds[t.kind] = (kinds[t.kind] or 0) + 1 end
    T.assert_eq(kinds.reduced_motion, 1, "reduced motion is focusable")
    T.assert_eq(kinds.tilt, 1, "and so is tilt")
    T.assert_eq(kinds.back, 1)

    -- Tapping the toggle flips it.
    local was = g:tilt_enabled()
    local r = g._pause_tilt_rect
    g:touchpressed(1, r.x + r.w * 0.5, r.y + r.h * 0.5)
    T.assert_eq(g:tilt_enabled(), not was, "the toggle answers the stylus")

    love.joystick.getJoysticks = original
    Tilt.reset_all()
end)

--- Gated the way the reference gates rumble on `G.F_RUMBLE` (`UI_definitions.lua:2303`) rather than
--- shown and inert.
suite.test("the tilt toggle is hidden where there is no accelerometer", function()
    local original = love.joystick.getJoysticks
    love.joystick.getJoysticks = function() return {} end
    Tilt.reset_all()

    local g = bootstrap.new_game()
    g.STATE = g.STATES.PAUSED
    g._pause_show_settings = true
    g._pause_settings_tab = "general"
    g:draw_bottom_pause()
    g:draw_bottom_pause()
    T.assert_nil(g._pause_tilt_rect, "no toggle without a sensor")
    for _, t in ipairs(g:build_pause_focus_targets()) do
        T.assert_ne(t.kind, "tilt", "and the pad cannot land on one")
    end

    love.joystick.getJoysticks = original
    Tilt.reset_all()
end)

return suite

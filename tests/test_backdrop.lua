--- The backdrop driver.
---
--- The field itself lives in a PICA vertex shader and cannot be exercised here, so what is
--- tested is everything around it: that the timers follow the reference's rules, that palettes
--- ease rather than snap, and that a runtime without the binding degrades to the caller's
--- fallback instead of erroring. The last one matters most -- desktop, nest and this stub all
--- lack `drawBackdrop`, so the unsupported path is the one most people will run.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")
bootstrap.load()

local suite = T.suite()

local function fresh()
    local Backdrop = require("backdrop")
    Backdrop.reset()
    return Backdrop
end

--- The distinction the whole effect rests on: REAL_SHADER always advances, BACKGROUND only in
--- proportion to spin_amount (game.lua:2468). Get this wrong and the menu backdrop rotates,
--- which is exactly what it must not do.
suite.test("the clock starts past the reveal and advances on wall time", function()
    local Backdrop = fresh()
    -- splash.fs hides everything under a slate wash until ~12 s; a cold boot must not sit in
    -- that window looking broken.
    T.assert_true(Backdrop.debug_state().time >= 12, "starts revealed")
    local before = Backdrop.debug_state().time
    for _ = 1, 30 do Backdrop.update(1 / 60) end
    T.assert_true(Backdrop.debug_state().time > before + 0.4,
        "and never pauses, got " .. Backdrop.debug_state().time)
end)

--- The menu palette is splash.fs's, not background.fs's: two colours, G.C.RED and G.C.BLUE.
--- Getting this wrong is what shipped a teal-and-yellow menu.
suite.test("the menu palette is the reference's red and blue", function()
    local Backdrop = fresh()
    local s = Backdrop.debug_state()
    T.assert_true(s.c1[1] > 0.9 and s.c1[2] < 0.5, "colour_1 is G.C.RED, got " .. s.c1[1])
    T.assert_true(s.c2[1] < 0.1 and s.c2[3] > 0.9, "colour_2 is G.C.BLUE, got " .. s.c2[3])
    T.assert_eq(s.vort_speed, 0.4, "vort_speed matches game.lua:1552")
end)

suite.test("an unknown state falls back to the blind palette", function()
    local Backdrop = fresh()
    Backdrop.set_state("no such state", true)
    T.assert_eq(Backdrop.debug_state().c1[1], Backdrop.STATES.blind.c1[1],
        "unknown names must fall back to a real palette, never to black")
end)

--- The two shaders are different fields, not one field recoloured, so the mode has to travel
--- with the palette.
suite.test("selecting an in-run state switches shader mode", function()
    local Backdrop = fresh()
    T.assert_eq(Backdrop.debug_state().mode, Backdrop.MODE_SPLASH, "menu starts on splash.fs")
    Backdrop.set_state("tarot", true)
    T.assert_eq(Backdrop.debug_state().mode, Backdrop.MODE_BACKGROUND,
        "an in-run state moves to background.fs")
    Backdrop.set_menu()
    T.assert_eq(Backdrop.debug_state().mode, Backdrop.MODE_SPLASH, "and back again")
end)

--- The reference eases background colour over 0.6 s rather than cutting.
suite.test("a state change eases rather than snapping", function()
    local Backdrop = fresh()
    Backdrop.set_state("blind", true)
    local before = Backdrop.debug_state().c1[1]
    Backdrop.set_state("standard")

    Backdrop.update(1 / 60)
    local mid = Backdrop.debug_state().c1[1]
    T.assert_true(mid ~= before, "it started moving")
    T.assert_true(math.abs(mid - Backdrop.STATES.standard.c1[1]) > 0.01,
        "but did not arrive in one frame")

    for _ = 1, 120 do Backdrop.update(1 / 60) end
    T.assert_true(math.abs(Backdrop.debug_state().c1[1] - Backdrop.STATES.standard.c1[1]) < 0.001,
        "and lands exactly on the target")
end)

--- game.lua:2468 -- the spin timer advances only in proportion to the spin amount, which is
--- what stops a parked spin from rotating the field.
suite.test("the spin timer only advances with spin", function()
    local Backdrop = fresh()
    Backdrop.set_state("blind", true)
    for _ = 1, 30 do Backdrop.update(1 / 60) end
    T.assert_eq(Backdrop.debug_state().spin_time, 0, "parked spin leaves the timer alone")

    Backdrop.set_spin(1)
    for _ = 1, 120 do Backdrop.update(1 / 60) end
    T.assert_true(Backdrop.debug_state().spin > 0.9, "spin eases in")
    T.assert_true(Backdrop.debug_state().spin_time > 0, "and the timer moves")
end)

--- A boss's colour is per-boss, so it is computed rather than tabulated.
suite.test("a boss colour is derived from the blind's own colour", function()
    local Backdrop = fresh()
    Backdrop.set_boss_colour({ 0.8, 0.2, 0.2 })
    Backdrop.snap()
    local st = Backdrop.debug_state()
    T.assert_eq(st.mode, Backdrop.MODE_BACKGROUND, "boss blinds use background.fs")
    T.assert_true(math.abs(st.c1[1] - 0.8) < 0.001, "colour_1 is the boss colour itself")
    T.assert_true(st.c2[1] > st.c1[1] * 0.7 - 0.001, "colour_2 is lightened")
    T.assert_true(math.abs(st.c3[1] - 0.32) < 0.001, "colour_3 is darkened to 0.4")
end)

--- Committed code has to survive a runtime without the patch: desktop LOVE, nest, and this
--- stub all lack the binding.
suite.test("without the binding it reports unsupported and draws nothing", function()
    local Backdrop = fresh()
    T.assert_eq(Backdrop.is_supported(), false, "the stub has no drawBackdrop")
    T.assert_eq(Backdrop.draw(320), false, "so draw reports it did not paint")
end)

suite.test("with a binding it forwards the parameters splash.fs takes", function()
    local Backdrop = require("backdrop")
    local saved = love.graphics.drawBackdrop
    local seen
    love.graphics.drawBackdrop = function(...) seen = { ... } return true end
    Backdrop.reset()

    local ok, err = pcall(function()
        Backdrop.update(1 / 60)
        T.assert_eq(Backdrop.draw(320), true, "it reports having drawn")
        T.assert_eq(seen[1], 320, "screen width selects the grid")
        T.assert_eq(seen[2], Backdrop.MODE_SPLASH, "the shader mode is forwarded")
        T.assert_eq(seen[4], 0.4, "and the menu's vort_speed")
        T.assert_eq(#seen, 15, "width, mode, four scalars and three colours")
    end)

    love.graphics.drawBackdrop = saved
    Backdrop.reset()
    if not ok then error(err, 0) end
end)

--- A binding that throws must not take the frame down with it.
suite.test("a throwing binding is contained", function()
    local Backdrop = require("backdrop")
    local saved = love.graphics.drawBackdrop
    love.graphics.drawBackdrop = function() error("gpu fell over") end
    Backdrop.reset()

    local ok, err = pcall(function()
        T.assert_eq(Backdrop.draw(320), false, "reports failure rather than propagating")
    end)

    love.graphics.drawBackdrop = saved
    Backdrop.reset()
    if not ok then error(err, 0) end
end)

--- The boot guard: the game must be incapable of hanging on boot twice. A boot that never
--- reaches "proven" leaves "pending" on the card; the next boot reads that as a fatal verdict
--- and refuses the backdrop for this revision. These tests drive the guard through an
--- in-memory filesystem, since the real one costs SD writes.
local function with_guarded_fs(body)
    local Backdrop = require("backdrop")
    local files = {}
    local saved = {
        read = love.filesystem.read, write = love.filesystem.write,
        drawBackdrop = love.graphics.drawBackdrop,
    }
    love.filesystem.read = function(name) return files[name] end
    love.filesystem.write = function(name, data) files[name] = data return true end
    local calls = {}
    love.graphics.drawBackdrop = function(...) calls[#calls + 1] = { ... } return true, "cpu-field ok" end
    Backdrop.reset()

    local ok, err = pcall(body, Backdrop, files, calls)

    love.filesystem.read, love.filesystem.write = saved.read, saved.write
    love.graphics.drawBackdrop = saved.drawBackdrop
    Backdrop.reset()
    if not ok then error(err, 0) end
end

suite.test("a clean boot writes pending, then proven after the proof window", function()
    with_guarded_fs(function(Backdrop, files)
        T.assert_eq(Backdrop.draw(320), true, "first draw goes through")
        T.assert_eq(files["backdrop_state.txt"], "pending " .. Backdrop.REVISION,
            "the sentinel is on the card before anything can hang")

        for _ = 1, Backdrop.PROOF_FRAMES do Backdrop.draw(320) end
        T.assert_eq(files["backdrop_state.txt"], "proven " .. Backdrop.REVISION,
            "surviving the window upgrades it")
        T.assert_true(files["backdrop_trace.txt"]:find("marking proven", 1, true) ~= nil,
            "and the trace closes out")
    end)
end)

suite.test("a boot that died mid-proof disables the backdrop", function()
    with_guarded_fs(function(Backdrop, files)
        files["backdrop_state.txt"] = "pending " .. Backdrop.REVISION
        Backdrop.reset()

        T.assert_eq(Backdrop.draw(320), false, "the guard refuses to draw")
        T.assert_eq(Backdrop.is_guard_tripped(), true, "and says so")
        T.assert_eq(files["backdrop_state.txt"], "failed " .. Backdrop.REVISION,
            "the verdict is recorded")

        Backdrop.reset()
        T.assert_eq(Backdrop.draw(320), false, "and holds on later boots of the same build")
    end)
end)

suite.test("a new revision gets one fresh attempt after a failure", function()
    with_guarded_fs(function(Backdrop, files)
        files["backdrop_state.txt"] = "failed 0-previous"
        Backdrop.reset()
        T.assert_eq(Backdrop.draw(320), true,
            "a failure recorded by an older build must not condemn this one")
    end)
end)

--- A native refusal is not a hang, so it must not burn the guard: the reason is recorded and
--- the next boot is free to try again.
suite.test("a clean decline records its reason and stays retryable", function()
    with_guarded_fs(function(Backdrop, files)
        love.graphics.drawBackdrop = function() return false, "ramp texture init failed" end
        Backdrop.reset()

        T.assert_eq(Backdrop.draw(320), false, "it reports unpainted")
        T.assert_true(files["backdrop_trace.txt"]:find("ramp texture init failed", 1, true) ~= nil,
            "and the trace names the reason, got " .. tostring(files["backdrop_trace.txt"]))
        T.assert_eq(files["backdrop_state.txt"], "declined " .. Backdrop.REVISION,
            "recorded as declined, not pending")

        Backdrop.reset()
        T.assert_eq(Backdrop.draw(320), false, "still declining")
        T.assert_eq(files["backdrop_state.txt"], "declined " .. Backdrop.REVISION,
            "but a decline never escalates to failed")
    end)
end)

suite.test("a proven build skips the proof dance entirely", function()
    with_guarded_fs(function(Backdrop, files)
        files["backdrop_state.txt"] = "proven " .. Backdrop.REVISION
        Backdrop.reset()
        T.assert_eq(Backdrop.draw(320), true, "draws immediately")
        T.assert_eq(files["backdrop_state.txt"], "proven " .. Backdrop.REVISION,
            "without rewriting the sentinel")
    end)
end)

return suite

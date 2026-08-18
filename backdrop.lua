--- The animated background, driven the way the reference game drives its shader.
---
--- The base game paints this with `background.fs`, a fragment shader sampled per pixel, and
--- feeds it seven values that ease per game state (`reference/Balatro/game.lua:2283`): two
--- timers, three colours, a contrast and a spin amount. The PICA200 has no fragment
--- programmability, so the field is evaluated per vertex over an 80x60 grid on the GPU and the
--- three colour weights are resolved per pixel through a ramp texture --
--- `dev/shaders/backdrop.v.pica` has the whole argument. This module owns the parameters; the
--- draw itself is one call into `love.graphics.drawBackdrop`.
---
--- What this replaces: a 1024x1024 sheet of 63 prebaked frames, 2.5 MB on the card and 4 MiB
--- resident, reloaded on every entry to the menu. That is why the backdrop used to exist only
--- on the menu -- there was no room to keep it during a run. There is now.
---
--- Timers follow the reference exactly, and the distinction matters:
---   * REAL_SHADER always advances; it is the warp, and it is the whole of the motion on a menu.
---   * BACKGROUND advances only in proportion to `spin_amount` (`game.lua:2468`), which is zero
---     outside runs. So the menu backdrop genuinely does not rotate, and anything that spins it
---     there is wrong.

local Console = require "console"

local Backdrop = {}

--- Reference palettes, one per state, in the shape `ease_background_colour` sets them:
--- `C` is the base, `L` the highlight, `D` the deep tone (`common_events.lua:333-358`).
--- The two shaders the reference uses, and when.
---
--- `Game:main_menu` builds SPLASH_BACK with `shader = 'splash'` and sends `G.C.RED` and
--- `G.C.BLUE` (`game.lua:1548-1556`). Everything else uses `background.fs` with the three
--- eased `G.C.BACKGROUND` colours plus a contrast (`game.lua:2283-2291`). They are different
--- fields, not one field with different colours.
Backdrop.MODE_SPLASH = 0
Backdrop.MODE_BACKGROUND = 1

--- The menu, from `splash.fs`'s send list. G.C.RED = HEX('FE5F55'), G.C.BLUE = HEX("009dff").
Backdrop.MENU = {
    mode = Backdrop.MODE_SPLASH,
    c1 = { 0.996, 0.373, 0.333 },
    c2 = { 0.000, 0.616, 1.000 },
    vort_speed = 0.4,             -- game.lua:1552
}

--- In-run palettes, resolved from `ease_background_colour_blind` and the brightness factors
--- `ease_background_colour` applies (`common_events.lua:276-360`).
---
--- The mapping is worth stating once because it is not obvious. The shader takes
--- colour_1 = C, colour_2 = L, colour_3 = D (`game.lua:2287-2289`), and the easing function
--- fills those from its arguments:
---
---   * with both a special and a tertiary colour: L = new, C = special, D = tertiary, all
---     applied directly with no brightness factor;
---   * otherwise: L = new * 1.3, C = special or new * 0.9, D = new * 0.7, or new * 0.4 when a
---     special colour was supplied.
---
--- So each entry below is already the post-easing value, which is what the shader actually
--- receives -- deriving it at runtime would mean porting `ease_value` for no benefit.
Backdrop.STATES = {
    -- Small/Big blind and the default in-run state: G.C.BLIND.Small = HEX("50846e").
    blind = {
        c1 = { 0.282, 0.464, 0.388 }, c2 = { 0.408, 0.671, 0.561 },
        c3 = { 0.219, 0.361, 0.302 }, contrast = 1.0,
    },
    -- Tarot pack: G.C.PURPLE against darken(BLACK, 0.2), contrast 1.5.
    tarot = {
        c1 = { 0.031, 0.031, 0.031 }, c2 = { 0.573, 0.408, 0.937 },
        c3 = { 0.012, 0.012, 0.012 }, contrast = 1.5,
    },
    -- Spectral pack: SECONDARY_SET.Spectral against darken(BLACK, 0.2), contrast 2.
    spectral = {
        c1 = { 0.031, 0.031, 0.031 }, c2 = { 0.286, 0.720, 0.976 },
        c3 = { 0.012, 0.012, 0.012 }, contrast = 2.0,
    },
    -- Standard pack: darken(BLACK, 0.2) with G.C.RED as the special colour, contrast 3.
    standard = {
        c1 = { 0.996, 0.373, 0.333 }, c2 = { 0.041, 0.041, 0.041 },
        c3 = { 0.013, 0.013, 0.013 }, contrast = 3.0,
    },
    -- Buffoon pack: G.C.FILTER against BLACK, contrast 2.
    buffoon = {
        c1 = { 0.000, 0.000, 0.000 }, c2 = { 0.000, 0.740, 0.994 },
        c3 = { 0.000, 0.000, 0.000 }, contrast = 2.0,
    },
    -- Planet pack: BLACK, contrast 3.
    planet = {
        c1 = { 0.000, 0.000, 0.000 }, c2 = { 0.000, 0.000, 0.000 },
        c3 = { 0.000, 0.000, 0.000 }, contrast = 3.0,
    },
    -- Shop keeps the blind palette; the reference does not recolour on entering it.
    shop = {
        c1 = { 0.282, 0.464, 0.388 }, c2 = { 0.408, 0.671, 0.561 },
        c3 = { 0.219, 0.361, 0.302 }, contrast = 1.0,
    },
    -- Run won: G.C.BLIND.won = HEX("4F6367"), contrast 1.
    won = {
        c1 = { 0.278, 0.348, 0.363 }, c2 = { 0.402, 0.503, 0.524 },
        c3 = { 0.216, 0.271, 0.282 }, contrast = 1.0,
    },
    -- A boss blind: lighten(mix(boss_col, BLACK, 0.3), 0.1) with boss_col special, contrast 2.
    -- boss_colour varies per boss; this is the common dark-red case and is overwritten by
    -- `set_boss_colour` when the actual blind is known.
    boss = {
        c1 = { 0.482, 0.145, 0.121 }, c2 = { 0.243, 0.093, 0.082 },
        c3 = { 0.193, 0.058, 0.048 }, contrast = 2.0,
    },
    -- The showdown boss, the one state that genuinely is blue and red
    -- (`common_events.lua:352`): BLUE / RED / darken(BLACK, 0.4), applied directly.
    showdown = {
        c1 = { 0.996, 0.373, 0.333 }, c2 = { 0.000, 0.616, 1.000 },
        c3 = { 0.024, 0.024, 0.024 }, contrast = 3.0,
    },
}

--- Live state. `time` is the reference's REAL_SHADER: wall time, always advancing. Colours
--- and contrast ease toward their targets rather than cutting, as `ease_background_colour`
--- does over 0.6 s -- a hard switch on a boss blind reads as a glitch.
local state = {
    mode = Backdrop.MODE_SPLASH,
    time = 12,
    vort_speed = 0.4,
    vort_offset = 0,
    spin_time = 0,
    spin = 0,
    spin_target = 0,
    contrast = 1.0,
    contrast_target = 1.0,
    c1 = { 0.996, 0.373, 0.333 }, c2 = { 0.000, 0.616, 1.000 }, c3 = { 0, 0, 0 },
    t1 = { 0.996, 0.373, 0.333 }, t2 = { 0.000, 0.616, 1.000 }, t3 = { 0, 0, 0 },
}

--- Seconds for a palette change to complete, matching `common_events.lua:299`.
Backdrop.EASE_SECONDS = 0.6

local supported = nil

--- Whether this build can draw the backdrop at all. False on desktop, under the test stub, and
--- on any runtime without the patched binding -- every caller falls back to a flat fill.
--- @return boolean
--- Whether this build can draw the backdrop at all.
---
--- Gated to the New 3DS, and not out of caution. The field is evaluated per vertex on the CPU
--- because a custom vertex program hangs this GPU, and it measures 1.93 ms a call on an
--- 804 MHz New 3DS -- 3.7 ms a frame across both screens. An Old 3DS runs the same ARM11 at
--- 268 MHz without L2, so the identical work is around 11 ms: two thirds of a 16.7 ms frame
--- before the game draws a single card. There is no grid density at which that becomes
--- reasonable, because the cost is the arithmetic itself rather than anything a coarser mesh
--- avoids. The Old 3DS keeps the gradient.
--- @return boolean
function Backdrop.is_supported()
    if supported == nil then
        supported = (love.graphics ~= nil and love.graphics.drawBackdrop ~= nil)
            and Console.is_new_3ds()
    end
    return supported
end

--- Bumped whenever the backdrop's native side changes. The boot guard keys off it, so a build
--- that fixes a hang gets one fresh chance instead of staying disabled forever.
Backdrop.REVISION = "10"

--- Frames of successful drawing before this build is marked proven. 1.5 s: long enough to
--- know the pipeline survived, short enough that a quick quit rarely false-marks a failure.
Backdrop.PROOF_FRAMES = 90

local GUARD_FILE = "backdrop_state.txt"
local TRACE_FILE = "backdrop_trace.txt"

-- nil = not yet decided, true/false = decided for this process.
local guard_enabled = nil
local proof_frames = 0
local proven = false

local function fs()
    return love and love.filesystem or nil
end

local log_lines = {}

--- Append to the on-card log and rewrite it. Read over FTP, so it is deliberately wordy: a
--- reboot is expensive and a line that turns out to be missing costs another one.
local function trace(msg)
    log_lines[#log_lines + 1] = msg
    local f = fs()
    if not (f and f.write) then return end
    pcall(f.write, TRACE_FILE, table.concat(log_lines, "\n") .. "\n")
end

--- The boot guard. The game must be incapable of hanging on boot twice: a sentinel is written
--- before the first draw and only upgraded to "proven" after PROOF_FRAMES survive. A boot that
--- dies in between leaves "pending" on the card, and the next boot reads that as a verdict and
--- refuses the backdrop -- for this REVISION, so a build that changes the native side gets one
--- fresh attempt automatically. A clean refusal is recorded as "declined" instead, which stays
--- retryable, because a call that returned cannot have hung.
---
--- This is kept even though the custom vertex program that hung is gone: the backdrop still
--- reaches straight into the GPU, and a hang here costs a hard reset rather than a crash.
local function read_guard()
    local f = fs()
    if not (f and f.read) then return nil end
    local ok, data = pcall(f.read, GUARD_FILE)
    if not ok or type(data) ~= "string" then return nil end
    return data:match("^(%w+)%s+(%S+)")
end

local function write_guard(status)
    local f = fs()
    if not (f and f.write) then return end
    pcall(f.write, GUARD_FILE, status .. " " .. Backdrop.REVISION)
end

local function guard_allows_draw()
    if guard_enabled ~= nil then return guard_enabled end

    local status, rev = read_guard()
    trace(("boot: revision %s; card says %s rev %s")
        :format(Backdrop.REVISION, tostring(status), tostring(rev)))

    if rev ~= Backdrop.REVISION then
        trace("guard: new build, arming")
        write_guard("pending")
        guard_enabled = true
        return true
    end
    if status == "proven" then
        proven = true
        trace("guard: proven, drawing")
        guard_enabled = true
        return true
    end
    if status == "declined" then
        trace("guard: last boot declined cleanly, retrying")
        write_guard("pending")
        guard_enabled = true
        return true
    end

    trace("guard: last boot never finished -- treating as a hang, backdrop OFF")
    write_guard("failed")
    guard_enabled = false
    return false
end

--- Whether the guard has shut the backdrop off. Surfaced so a settings screen can say so
--- rather than leaving a silently plain background.
function Backdrop.is_guard_tripped()
    return guard_enabled == false
end

--- Test seam; the probe is cached for the process otherwise.
function Backdrop.reset()
    supported = nil
    guard_enabled = nil
    proof_frames = 0
    proven = false
    state.mode = Backdrop.MODE_SPLASH
    state.time = 12
    state.spin, state.spin_target, state.spin_time = 0, 0, 0
    state.vort_offset = 0
    Backdrop.set_menu(true)
end

--- Put the backdrop on the menu shader.
function Backdrop.set_menu(immediate)
    state.mode = Backdrop.MODE_SPLASH
    local p = Backdrop.MENU
    state.vort_speed = p.vort_speed
    for i = 1, 3 do
        state.t1[i], state.t2[i], state.t3[i] = p.c1[i], p.c2[i], 0
    end
    state.contrast_target = 1.0
    if immediate ~= false then Backdrop.snap() end
end

--- Put the backdrop on the in-run shader with one of the reference's state palettes. Unknown
--- names fall back to `blind`, which is what the reference uses whenever no pack or boss
--- applies -- never to nothing, since an undefined palette would render as black.
--- @param name string key into `Backdrop.STATES`
--- @param immediate boolean|nil snap rather than ease
function Backdrop.set_state(name, immediate)
    local p = Backdrop.STATES[name] or Backdrop.STATES.blind
    state.mode = Backdrop.MODE_BACKGROUND
    for i = 1, 3 do
        state.t1[i], state.t2[i], state.t3[i] = p.c1[i], p.c2[i], p.c3[i]
    end
    state.contrast_target = p.contrast or 1.0
    if immediate then Backdrop.snap() end
end

--- A boss blind's colour is per-boss, so it cannot live in a static table. Applies the
--- reference's arithmetic: L = lighten(mix(boss, BLACK, 0.3), 0.1), C = boss, D = boss * 0.4
--- (`common_events.lua:358` with the special-colour brightness rules).
--- @param colour table {r, g, b} the boss's own colour
function Backdrop.set_boss_colour(colour)
    if type(colour) ~= "table" then return Backdrop.set_state("boss") end
    state.mode = Backdrop.MODE_BACKGROUND
    for i = 1, 3 do
        local c = tonumber(colour[i]) or 0
        local mixed = c * 0.7                    -- mix_colours(boss, BLACK, 0.3)
        state.t2[i] = mixed + (1 - mixed) * 0.1  -- lighten(.., 0.1)
        state.t1[i] = c
        state.t3[i] = c * 0.4
    end
    state.contrast_target = 2.0
end

--- Land every eased value on its target at once.
function Backdrop.snap()
    for i = 1, 3 do
        state.c1[i], state.c2[i], state.c3[i] = state.t1[i], state.t2[i], state.t3[i]
    end
    state.contrast = state.contrast_target
end

--- Rotate the whole vortex. `vort_offset` in the reference.
--- @param offset number radians
function Backdrop.set_vort_offset(offset)
    state.vort_offset = tonumber(offset) or 0
end

--- How much the in-run field spirals. The reference raises this during scoring and lets it
--- ease back; at zero the swirl is a pure rotation and only the warp moves.
--- @param amount number 0..1
function Backdrop.set_spin(amount)
    state.spin_target = math.max(0, math.min(1, tonumber(amount) or 0))
end

local function approach(current, target, step)
    local delta = target - current
    if delta > step then return current + step end
    if delta < -step then return current - step end
    return target
end

--- Advance the clocks and ease anything in flight. The reference drives `time` from
--- REAL_SHADER, which is wall time and never pauses, so the field keeps moving behind a modal.
--- `spin_time` advances only in proportion to the spin amount (`game.lua:2468`), which is what
--- keeps a parked spin from rotating the field.
--- @param dt number
function Backdrop.update(dt)
    dt = tonumber(dt) or 0
    state.time = state.time + dt

    state.spin = approach(state.spin, state.spin_target, dt / Backdrop.EASE_SECONDS)
    state.spin_time = state.spin_time + dt * state.spin

    local step = dt / Backdrop.EASE_SECONDS
    state.contrast = approach(state.contrast, state.contrast_target, step * 2)
    for i = 1, 3 do
        state.c1[i] = approach(state.c1[i], state.t1[i], step)
        state.c2[i] = approach(state.c2[i], state.t2[i], step)
        state.c3[i] = approach(state.c3[i], state.t3[i], step)
    end
end

--- Draw it. Returns false when the runtime has no binding, when the boot guard has tripped,
--- or when the call declines -- in every case the caller paints its fallback.
---
--- The binding returns (drawn, reason). A clean decline is recorded as "declined" rather than
--- left as "pending": pending means "a boot started drawing and never came back", and using it
--- for a refusal that returned normally would disable the backdrop for a failure that carries
--- no risk of hanging. Only silence counts as a hang.
--- @param width number screen width, which selects the prebuilt grid
--- @return boolean drawn
function Backdrop.draw(width)
    if not Backdrop.is_supported() then return false end
    if not guard_allows_draw() then return false end

    local first = (proof_frames == 0) and not proven
    if first then trace("calling drawBackdrop") end

    -- The two shaders take different scalars in p1/p2; see the binding's header.
    local p1 = (state.mode == Backdrop.MODE_BACKGROUND) and state.spin_time or state.vort_speed
    local p2 = (state.mode == Backdrop.MODE_BACKGROUND) and state.spin or state.vort_offset

    local ok, drawn, reason = pcall(love.graphics.drawBackdrop, width,
        state.mode, state.time, p1, p2, state.contrast,
        state.c1[1], state.c1[2], state.c1[3],
        state.c2[1], state.c2[2], state.c2[3],
        state.c3[1], state.c3[2], state.c3[3])

    if not ok then
        -- The binding raised rather than returning: `drawn` holds the error.
        trace("ERROR from drawBackdrop: " .. tostring(drawn))
        write_guard("declined")
        guard_enabled = false
        return false
    end

    if not drawn then
        trace("declined: " .. tostring(reason or "no reason given"))
        write_guard("declined")
        guard_enabled = false
        return false
    end

    if first then
        trace("drew frame 1 -- " .. tostring(reason))
    end

    if not proven then
        proof_frames = proof_frames + 1
        if proof_frames >= Backdrop.PROOF_FRAMES then
            proven = true
            write_guard("proven")
            trace(("healthy: %d frames drawn, marking proven"):format(Backdrop.PROOF_FRAMES))
        end
    end
    return true
end

--- Current parameters, for the tests to assert easing without reaching into the module.
function Backdrop.debug_state() return state end

return Backdrop

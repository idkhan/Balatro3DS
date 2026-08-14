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

local Backdrop = {}

--- Reference palettes, one per state, in the shape `ease_background_colour` sets them:
--- `C` is the base, `L` the highlight, `D` the deep tone (`common_events.lua:333-358`).
--- The main menu uses `splash.fs`, not `background.fs`. `Game:main_menu` builds SPLASH_BACK
--- with `shader = 'splash'` and sends exactly two colours -- `G.C.RED` and `G.C.BLUE`
--- (`game.lua:1548-1556`) -- against a slate the shader hardcodes. background.fs, with its
--- three eased colours and its contrast, is the in-run backdrop; porting it and pointing it at
--- the menu was simply the wrong shader.
Backdrop.PALETTES = {
    -- G.C.RED = HEX('FE5F55'), G.C.BLUE = HEX("009dff") (globals.lua:359-360).
    menu = {
        c1 = { 0.996, 0.373, 0.333 },
        c2 = { 0.000, 0.616, 1.000 },
        vort_speed = 0.4,   -- game.lua:1552
    },
}

--- Live state. `time` is the reference's REAL_SHADER: wall time, always advancing.
local state = {
    -- Starts past the reveal, not at zero. splash.fs fades the smoke in over the first twelve
    -- seconds (0.17*min(10, time*1.2 - 4)); in the reference REAL_SHADER has been running
    -- since app launch, through the splash screen, so the menu never shows the early blank.
    -- From a cold boot straight onto our menu it read as a broken slate screen, so the clock
    -- begins where the reveal completes. The swirl terms saturate at time*vort_speed = 6, so
    -- the vortex is in its steady state by then too.
    time = 12,
    vort_speed = 0.4,
    vort_offset = 0,
    c1 = { 0.996, 0.373, 0.333 },
    c2 = { 0.000, 0.616, 1.000 },
}

local supported = nil

--- Whether this build can draw the backdrop at all. False on desktop, under the test stub, and
--- on any runtime without the patched binding -- every caller falls back to a flat fill.
--- @return boolean
function Backdrop.is_supported()
    if supported == nil then
        supported = (love.graphics ~= nil and love.graphics.drawBackdrop ~= nil)
    end
    return supported
end

--- Bumped whenever the backdrop's native side changes. The boot guard keys off it, so a build
--- that fixes a hang gets one fresh chance instead of staying disabled forever.
Backdrop.REVISION = "9"

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
    state.time = 12
    state.vort_offset = 0
    Backdrop.set_palette("menu")
end

--- Point the backdrop at a palette.
--- @param name string key into `Backdrop.PALETTES`
function Backdrop.set_palette(name)
    local p = Backdrop.PALETTES[name] or Backdrop.PALETTES.menu
    for i = 1, 3 do
        state.c1[i], state.c2[i] = p.c1[i], p.c2[i]
    end
    state.vort_speed = p.vort_speed or 0.4
end

--- Rotate the whole vortex. `vort_offset` in the reference; unused on the menu but it is what
--- a state transition would turn.
--- @param offset number radians
function Backdrop.set_vort_offset(offset)
    state.vort_offset = tonumber(offset) or 0
end

--- Advance the clock. The reference drives this from REAL_SHADER, which is wall time and never
--- pauses, so the vortex keeps turning behind a modal.
--- @param dt number
function Backdrop.update(dt)
    state.time = state.time + (tonumber(dt) or 0)
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

    local ok, drawn, reason = pcall(love.graphics.drawBackdrop, width,
        state.time, state.vort_speed, state.vort_offset,
        state.c1[1], state.c1[2], state.c1[3],
        state.c2[1], state.c2[2], state.c2[3])

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

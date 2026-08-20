--- Accelerometer-driven playfield tilt.
---
--- The bottom screen drifts a few pixels against the way the console is being held, so the board
--- reads as a fixed surface being looked at from a slightly different angle rather than an image
--- glued to the panel. It layers on top of the gameplay shake (`Game:get_shake_offset`); neither
--- knows about the other, and each has its own control in the settings, the way the reference keeps
--- screenshake and reduced motion independent (`UI_definitions.lua:2303-2309`).
---
--- 3DS specifics that shape this file:
---
--- * The sensor is reached through the joystick object, not `love.sensor`. LovePotion's
---   `love.sensor` module is wired up but its Lua binding pushes nil instead of the sample
---   (`source/modules/sensor/wrap_sensor.cpp:45-56`), whereas `Joystick:getSensorData` pushes the
---   three floats correctly (`source/objects/joystick/wrap_joystick.cpp:355-371`). So this uses
---   `joystick:setSensorEnabled("accelerometer", true)` and reads from there.
--- * The samples arrive on their own. Once the sensor is enabled the HID poll reads it every frame
---   and pushes a `joysticksensorupdated` event (`platform/ctr/source/utilities/driver/hid_ext.cpp:107-113`),
---   so `Tilt.on_sample` is fed from that callback and polling is only a fallback for the frames
---   where no event turned up.
--- * `hidAccelRead` reports raw counts (~512 per g), not m/s^2. Nothing here depends on the scale:
---   the pipeline works on the *direction* of the measured vector.
---
--- The pipeline, in order: gravity vector -> pose-independent roll/pitch angles -> low-pass ->
--- subtract a slowly-tracking neutral -> soft deadzone -> pixels -> spring -> hysteretic rounding.
local Tilt = {}

-- LovePotion is Lua 5.1, where atan2 is its own function; keep a 5.3+ fallback so the headless
-- suite runs on whatever interpreter is to hand.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local exp, abs, sqrt, floor = math.exp, math.abs, math.sqrt, math.floor
local PI, TWO_PI = math.pi, math.pi * 2

--------------------------------------------------------------------------------
-- Tuning
--
-- Dialled in on hardware. These were sliders on a tuning page while the feel was being found; the
-- page is gone and the values it produced are here.
--------------------------------------------------------------------------------

--- Furthest the board travels, in pixels. Bounded by the fact that the translate sits above touch
--- hit-testing (`main.lua:182`): past a handful of pixels the cards visibly slide out from under
--- the stylus.
local MAX_PX = 4.5
--- Tilt that reaches that full range. A comfortable wrist roll, not a shove.
local RANGE_RAD = 18 * PI / 180
--- Fraction of the range ignored around neutral, rescaled so leaving it is smooth rather than a
--- step. Covers hand tremor and a bus.
local DEADZONE = 0.15
--- Low-pass on the sensor. The intentional signal is far slower than the noise, so this costs
--- nothing perceptible and removes all of the jitter.
local SMOOTH_TAU = 0.120
--- Chase toward the target offset, the same exponential approach the card springs use
--- (`engine/moveable.lua`), so the board settles with the rest of the game's motion.
local SPRING_TAU = 0.090
--- How fast the neutral follows a new resting pose. This is what makes the effect respond to
--- *changes* in how the console is held rather than to absolute pose, so shifting in a chair or
--- lying down never leaves the board pinned off-centre.
local RECENTER_TAU = 3.0

--- The board moves *against* the tilt: leaning the console right slides the playfield left, the way
--- a fixed surface behaves when you look at it from further round. Moving with the tilt reads as the
--- board sloshing about inside the console.
local DIRECTION = -1

--- Below this the measured vector has no usable direction (freefall, or a dead read).
local MIN_VECTOR = 1e-4
--- How long after activation the neutral is allowed to snap to wherever the console is being held.
local CALIBRATE_S = 0.5
--- Neutral-tracking time constant during that window. Fast enough to lock on in half a second.
local CALIBRATE_TAU = 0.08
--- A frame longer than this is a suspend (HOME menu, save write), not a frame. Letting it through
--- would drive every exponential straight to its target and snap the neutral to a pose the player
--- was never in.
local MAX_DT = 0.1
--- Distance the continuous offset must travel past the committed pixel before a new one is
--- committed. Without it a value resting near x.5 alternates between two pixels forever, which on a
--- 240p panel reads as the board vibrating.
local ROUND_HYSTERESIS = 0.6

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state
local function blank_state()
    return {
        joystick = nil,
        active = false,
        sample_x = 0, sample_y = 0, sample_z = 0,
        have_sample = false,
        fresh = false,
        primed = false,
        roll = 0, pitch = 0,
        neutral_roll = 0, neutral_pitch = 0,
        calib_t = 0,
        px_x = 0, px_y = 0,
        out_x = 0, out_y = 0,
    }
end
state = blank_state()

--- Full teardown, including the cached joystick. Test seam.
function Tilt.reset_all()
    state = blank_state()
end

--------------------------------------------------------------------------------
-- Maths
--------------------------------------------------------------------------------

local function wrap_angle(a)
    a = a % TWO_PI
    if a > PI then a = a - TWO_PI end
    return a
end

--- Roll and pitch of the measured gravity vector, in radians.
---
--- Both are angles of the vector rather than components of it, which is what makes them independent
--- of how steeply the console is already being held: a 3DS sits anywhere between flat on a table and
--- straight upright, and a component-wise reading would change meaning across that range.
---
---@return number|nil roll, number|nil pitch
function Tilt.angles_from_gravity(x, y, z)
    x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    local len = sqrt(x * x + y * y + z * z)
    if len < MIN_VECTOR then return nil, nil end
    local ux, uy, uz = x / len, y / len, z / len
    return atan2(ux, sqrt(uy * uy + uz * uz)), atan2(uz, uy)
end

--- Deadzone that scales what is left back up to full range, so the offset leaves zero smoothly
--- instead of stepping to `DEADZONE` the moment it is crossed. A hard deadzone is visible on an
--- effect this small: the board would jump.
---@param v number normalized axis, roughly -1..1
---@param dz number deadzone as a fraction of full range
function Tilt.soft_deadzone(v, dz)
    v = tonumber(v) or 0
    dz = tonumber(dz) or 0
    if dz >= 1 then return 0 end
    local m = abs(v)
    if dz > 0 then
        if m <= dz then return 0 end
        m = (m - dz) / (1 - dz)
    end
    if m > 1 then m = 1 end
    if v < 0 then return -m end
    return m
end

--- Exponential approach coefficient for this frame.
local function approach_k(dt, tau)
    if not tau or tau <= 0 then return 1 end
    return 1 - exp(-dt / tau)
end

--- Nearest integer, but only if the value has travelled far enough from the pixel currently being
--- displayed. See `ROUND_HYSTERESIS`.
---@param value number continuous offset
---@param committed number pixel currently on screen
---@return number
function Tilt.hysteretic_round(value, committed)
    value = tonumber(value) or 0
    committed = tonumber(committed) or 0
    if abs(value - committed) <= ROUND_HYSTERESIS then return committed end
    return (value >= 0) and floor(value + 0.5) or -floor(-value + 0.5)
end

--------------------------------------------------------------------------------
-- Sensor
--------------------------------------------------------------------------------

local function find_joystick()
    if state.joystick then return state.joystick end
    if not (love and love.joystick and love.joystick.getJoysticks) then return nil end
    local ok, list = pcall(love.joystick.getJoysticks)
    if not ok or type(list) ~= "table" then return nil end
    local js = list[1]
    if not js or type(js.setSensorEnabled) ~= "function" then return nil end
    state.joystick = js
    return js
end

--- Whether this system has an accelerometer to read at all. The settings toggle is hidden where it
--- does not, which is how the reference handles a platform-only setting - rumble is gated on
--- `G.F_RUMBLE` rather than shown and inert (`UI_definitions.lua:2303`).
---
--- Deliberately does not power the sensor: this is asked on every settings draw.
---@return boolean
function Tilt.supported()
    return find_joystick() ~= nil
end

--- Power the accelerometer on or off. Kept off unless the setting is on: an unused sensor is a HID
--- read and an event allocation every frame for nothing.
---@param active boolean
---@return boolean active whether the sensor is now on
function Tilt.set_active(active)
    active = active == true
    if active == state.active then return state.active end
    local js = find_joystick()
    if not js then
        state.active = false
        return false
    end
    local ok = pcall(js.setSensorEnabled, js, "accelerometer", active)
    if not ok then
        state.active = false
        return false
    end
    state.active = active
    if active then
        -- A fresh neutral: the console is wherever it is now, not wherever it was when the setting
        -- was last switched off.
        state.primed = false
        state.calib_t = 0
        state.have_sample = false
    end
    return state.active
end

function Tilt.is_active()
    return state.active == true
end

--- Feed a sample from `love.joysticksensorupdated`.
function Tilt.on_sample(x, y, z)
    state.sample_x, state.sample_y, state.sample_z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    state.have_sample = true
    state.fresh = true
end

--- Read the sensor directly. Only used for the frames where no event arrived; on 3DS the HID poll
--- pushes one every frame, so this is effectively a first-frame path.
local function poll_sample()
    local js = state.joystick
    if not js or type(js.getSensorData) ~= "function" then return false end
    local ok, x, y, z = pcall(js.getSensorData, js, "accelerometer")
    if not ok or not x then return false end
    Tilt.on_sample(x, y, z)
    return true
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

--- Advance the pipeline and return the offset in whole pixels.
---
--- Safe to call every frame regardless of the setting: with the sensor off it springs whatever
--- offset was on screen back to zero rather than dropping it, so switching tilt off mid-lean settles
--- instead of snapping.
---@param dt number real seconds
---@return number ox, number oy
function Tilt.update(dt)
    dt = tonumber(dt) or 0
    if dt < 0 then dt = 0 elseif dt > MAX_DT then dt = MAX_DT end
    local spring_k = approach_k(dt, SPRING_TAU)

    if not state.active then
        state.px_x = state.px_x + (0 - state.px_x) * spring_k
        state.px_y = state.px_y + (0 - state.px_y) * spring_k
        state.out_x = Tilt.hysteretic_round(state.px_x, state.out_x)
        state.out_y = Tilt.hysteretic_round(state.px_y, state.out_y)
        return state.out_x, state.out_y
    end

    if not state.fresh then poll_sample() end
    state.fresh = false

    local roll, pitch
    if state.have_sample then
        roll, pitch = Tilt.angles_from_gravity(state.sample_x, state.sample_y, state.sample_z)
    end

    if roll then
        if not state.primed then
            -- First usable sample: start smoothed and neutral both at the current pose so nothing
            -- swings in from zero.
            state.roll, state.pitch = roll, pitch
            state.neutral_roll, state.neutral_pitch = roll, pitch
            state.primed = true
            state.calib_t = 0
        else
            local k = approach_k(dt, SMOOTH_TAU)
            state.roll = state.roll + wrap_angle(roll - state.roll) * k
            state.pitch = state.pitch + wrap_angle(pitch - state.pitch) * k
        end

        state.calib_t = state.calib_t + dt
        -- Fast for the first half second so the effect is usable immediately from whatever pose the
        -- console is in, then slow enough that it only absorbs a player settling into a new position
        -- rather than the lean they are deliberately holding.
        local nk = approach_k(dt, (state.calib_t < CALIBRATE_S) and CALIBRATE_TAU or RECENTER_TAU)
        state.neutral_roll = state.neutral_roll + wrap_angle(state.roll - state.neutral_roll) * nk
        state.neutral_pitch = state.neutral_pitch + wrap_angle(state.pitch - state.neutral_pitch) * nk
    end

    local tx, ty = 0, 0
    if state.primed then
        tx = Tilt.soft_deadzone(wrap_angle(state.roll - state.neutral_roll) / RANGE_RAD, DEADZONE)
            * MAX_PX * DIRECTION
        ty = Tilt.soft_deadzone(wrap_angle(state.pitch - state.neutral_pitch) / RANGE_RAD, DEADZONE)
            * MAX_PX * DIRECTION
    end

    state.px_x = state.px_x + (tx - state.px_x) * spring_k
    state.px_y = state.px_y + (ty - state.px_y) * spring_k
    state.out_x = Tilt.hysteretic_round(state.px_x, state.out_x)
    state.out_y = Tilt.hysteretic_round(state.px_y, state.out_y)
    return state.out_x, state.out_y
end

return Tilt

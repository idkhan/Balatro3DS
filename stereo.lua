--- Stereoscopic 3D gating.
---
--- LövePotion turns stereo on unconditionally when the renderer initialises
--- (`platform/ctr/source/utilities/driver/renderer/renderer_ext.cpp:24`). With it on,
--- `GetScreenInfo` hands the run loop the three-entry `{left, right, bottom}` list
--- (`platform/ctr/source/common/screen_ext.cpp:9-14`) and `love.draw` is called once per
--- entry (`source/modules/love/scripts/callbacks.lua:270-281`), so the whole top screen --
--- scene-graph traversal, transforms, draw submission -- is paid twice every frame. With
--- the 3D slider parked at zero the second pass composites an image the player cannot see.
--- On a 268 MHz ARM11 that is the largest avoidable cost in the frame.
---
--- So: watch the slider, and drop to the two-entry list while it is down. Nothing else
--- changes -- the parallax call sites read `-love.graphics.getDepth()`, which is zero at
--- slider-zero anyway, and they mirror on `screen == "right"`, a name that only exists
--- while stereo is on (`topUI.lua:252`, `collection_ui.lua:705`, `main_menu_ui.lua:245`,
--- `deck_view_ui.lua:938`).
---
--- Two details make the switch delicate:
---
---  * `Set3D` destroys and recreates the framebuffers before and after the `gfxSet3D` call
---    (`platform/ctr/include/utilities/driver/renderer_ext.hpp:107-110`, `:194-199`), so it
---    must never run inside `love.draw`. `Stereo.update` is called from `love.update`,
---    which the run loop runs before it walks the screen list.
---  * The slider is an analogue potentiometer and dithers at rest, so the thresholds are
---    split -- it takes a firmer push to switch stereo on than to keep it on. Without the
---    gap, a slider resting on the boundary would tear down and rebuild the framebuffers
---    every frame.
---
--- `love.graphics.getDepth` is `osGet3DSliderState` with no gating on `gfxIs3D`
--- (`platform/ctr/source/modules/wrap_graphics_ext.cpp:24-28`), so it keeps reporting the
--- true slider position after stereo is switched off. That is what lets this turn back on.
---
--- Hardware only, deliberately. `nest` names the top screen "left" whether or not stereo is
--- on, and its `getDepth` stub returns 0 once `set3D(false)` has been called
--- (`nest/modules/overrides.lua:88-95`), which would latch the effect off and make the
--- parallax paths untestable on desktop.

local Console = require "console"

local Stereo = {}

--- Slider must clear this to switch stereo on...
Stereo.ON_THRESHOLD = 0.04
--- ...and fall below this to switch it back off. The gap is the anti-thrash margin.
Stereo.OFF_THRESHOLD = 0.02

--- What the bottom screen must measure once stereo is off. See `probe_bottom_width`.
Stereo.BOTTOM_WIDTH = 320

local enabled = nil
local probed = false
local disabled = false

--- One-time check, run the first time stereo actually goes off.
---
--- `CheckScreenName` resolves a name to a screen *id*, and `GetScreenInfo(id)` then uses
--- that id as an *index* into the currently active screen list. Those agree only while
--- stereo is on: `Screen::BOTTOM` is 2, and with stereo off the list is the two-entry
--- `altScreenInfo`, so `info[2]` reads past the end and lands on the 400px-wide left eye.
--- An unpatched runtime therefore answers 400 for `getWidth("bottom")` with the slider
--- down, and every layout derived from it -- tooltip wrapping, card and consumable drag
--- clamping -- comes out 80 px too wide.
---
--- `dev/patch_lovepotion.py` fixes that at the source, but the patch needs a runtime
--- rebuild. Rather than trust that, measure: if the width is wrong, put stereo back and
--- stop gating for the rest of the process. Costs one extra mode change, once.
local function probe_bottom_width()
    if not love.graphics.getWidth then return true end
    local ok, width = pcall(love.graphics.getWidth, "bottom")
    if not ok or width == nil then return true end
    return width == Stereo.BOTTOM_WIDTH
end

--- Pure hysteresis decision, split out from the renderer call so it can be tested without one.
---@param current boolean whether stereo is on right now
---@param depth number|nil slider state, 0..1
---@return boolean
function Stereo.decide(current, depth)
    depth = tonumber(depth) or 0
    if current then
        return depth > Stereo.OFF_THRESHOLD
    end
    return depth > Stereo.ON_THRESHOLD
end

--- Whether this build can gate stereo at all.
---@return boolean
function Stereo.supported()
    if not Console.is_hardware() then return false end
    local g = love and love.graphics
    return (g ~= nil) and (g.set3D ~= nil) and (g.getDepth ~= nil)
end

--- Last known stereo state, or nil before the first update.
---@return boolean|nil
function Stereo.is_enabled()
    return enabled
end

--- Poll the slider and switch the renderer if it has crossed a threshold. Call once per
--- frame from `love.update`, never from `love.draw`.
function Stereo.update()
    if disabled or not Stereo.supported() then return end

    if enabled == nil then
        -- The runtime enables stereo at init; ask it rather than assuming, in case a
        -- future runtime changes that.
        if love.graphics.get3D then
            enabled = love.graphics.get3D() and true or false
        else
            enabled = true
        end
    end

    local want = Stereo.decide(enabled, love.graphics.getDepth())
    if want == enabled then return end

    love.graphics.set3D(want)
    enabled = want

    if not want and not probed then
        probed = true
        if not probe_bottom_width() then
            love.graphics.set3D(true)
            enabled = true
            disabled = true
        end
    end
end

--- Whether the gate switched itself off after failing its probe.
---@return boolean
function Stereo.is_disabled()
    return disabled
end

--- Drop the cached state. Tests swap `love` out from under this module; nothing in the
--- game needs it.
function Stereo.reset()
    enabled = nil
    probed = false
    disabled = false
end

return Stereo

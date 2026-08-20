---@class Moveable : Node
Moveable = Node:extend()

---@param args {T: table, container: Node}
function Moveable:init(X,Y,W,H)
    local args = (type(X) == 'table') and X or {T ={X or 0,Y or 0,W or 0,H or 0}}
    Node.init(self, args)

    --The Visible transform is initally set to the same values as the transform T.
    --Note that the VT has an extra 'scale' factor, this is used to manipulate the center-adjusted
    --scale of any objects that need to be drawn larger or smaller
    self.VT = {
        x = self.T.x,
        y = self.T.y,
        w = self.T.w,
        h = self.T.h,
        r = self.T.r,
        scale = self.T.scale
    }

    --To determine location of VT, we need to keep track of the velocity of VT as it approaches T for the next frame
    self.velocity = {x = 0, y = 0, r = 0, scale = 0, mag = 0}
    -- Last touch delta while dragging, used for tilt-in-motion
    self.drag_velocity = { x = 0, y = 0 }
    self.drag_raise_scale = 1.08
end

function Moveable:draw()
    Node.draw(self)
    self:draw_boundingrect()
end

-- Flip pinch. The reference flips a card by squeezing its width to zero, swapping the shown
-- face at the crossing, and widening back out (`reference/Balatro/card.lua:4113-4142` via
-- `Moveable:move_wh`, `engine/moveable.lua:434-445`). The port keeps the pinch as a plain
-- horizontal draw factor rather than animating VT.w, which nothing else reads.
local FLIP_RATE = 6 -- full squash in ~0.15 s, ~0.3 s round trip, matching the reference feel

--- Start (or redirect) a flip. `on_swap` runs once, at the moment the node is edge-on.
function Moveable:start_flip(on_swap)
    if self._flip then
        self._flip.on_swap = on_swap
        self._flip.phase = "in"
        return
    end
    self._flip = { phase = "in", sx = 1, on_swap = on_swap }
end

function Moveable:update_flip(dt)
    local f = self._flip
    if not f then return end
    if f.phase == "in" then
        f.sx = f.sx - FLIP_RATE * dt
        if f.sx <= 0.05 then
            f.sx = 0.05
            if f.on_swap then f.on_swap() end
            f.on_swap = nil
            f.phase = "out"
        end
    else
        f.sx = f.sx + FLIP_RATE * dt
        if f.sx >= 1 then
            self._flip = nil
        end
    end
end

--- Horizontal draw factor for the current flip, 1 when idle.
function Moveable:flip_sx()
    local f = self._flip
    return f and f.sx or 1
end

-- Dissolve / materialise. The reference eases a single scalar - 0 to 1 over 0.7 s to take a
-- card apart, 1 to 0 over 0.6 s to bring one in (`reference/Balatro/card.lua:2130`, `:2183`) -
-- and draws every sprite layer through `dissolve.fs` with it. The card never changes size and
-- never fades as a whole; `Fx.draw_dissolve_cell` is the shader-free stand-in for that mask.
--
-- This lives on Moveable rather than on Card because a destroyed Joker and a used consumable
-- have to come apart the same way a card does, and three copies of these durations would
-- drift apart.
Moveable.DISSOLVE_DURATION = 0.7
Moveable.MATERIALIZE_DURATION = 0.6

-- `card.lua:2133`'s default `dissolve_colours`, the first two of which are what the shader
-- actually reads (`sprite.lua:103-104`): a black leading edge over an orange wash, which is
-- paper catching. Anything with a set of its own overrides this when it starts.
Moveable.DISSOLVE_BURN_1 = { 0.216, 0.259, 0.267 } -- G.C.BLACK, HEX("374244")
Moveable.DISSOLVE_BURN_2 = { 0.992, 0.635, 0.000 } -- G.C.ORANGE, HEX("fda200")

-- Which noise field a lifecycle draws from. The reference seeds this off the card's ID
-- (`sprite.lua:100`), but a Card, a Joker and a Consumable share no stable identity here, and
-- all the seed ever buys is that two nodes coming apart at once do not come apart in step -
-- which a rotating counter buys just as well, and without a lookup.
local lifecycle_seq = 0

--- Begin a dissolve or materialise on this node.
---@param kind string "dissolve" or "materialize"
---@param burn1 table|nil leading-edge colour; defaults to the reference's black
---@param burn2 table|nil wash colour; defaults to the reference's orange
---@param timefac number|nil stretch the tween; the reference passes one per call site
---        (`card.lua:1779` opens a booster pack at 1.5)
function Moveable:begin_lifecycle(kind, burn1, burn2, timefac)
    -- A node can be destroyed while it is still fading in, so a dissolve overrides a
    -- materialise. Only an in-flight dissolve is left alone, to keep one ghost per node.
    local current = self._card_lifecycle
    if current and current.kind == "dissolve" then return end
    lifecycle_seq = lifecycle_seq + 1
    self._card_lifecycle = {
        kind = kind,
        age = 0,
        seed = lifecycle_seq,
        duration = ((kind == "dissolve") and Moveable.DISSOLVE_DURATION or Moveable.MATERIALIZE_DURATION)
            * (tonumber(timefac) or 1),
        -- One colour given means one colour used, which is the shape every materialise takes
        -- (`card.lua:2188-2194` passes a single set colour); only the bare default is a pair.
        burn1 = burn1 or Moveable.DISSOLVE_BURN_1,
        burn2 = burn2 or (burn1 == nil and Moveable.DISSOLVE_BURN_2 or nil),
        -- Restored rather than forced back on: a node parked somewhere unhoverable (a shop
        -- shelf, a collection page) must not become hoverable just by arriving.
        hover_was = self.states and self.states.hover.can,
    }
    -- The reference pops the card at both ends, with its own `juice_up` defaults
    -- (`card.lua:2135`, `card.lua:2196` -> `moveable.lua:252`, amount 0.4, rotation +-0.24).
    -- These two arguments are what this port's mapping needs to land on those numbers.
    if self.juice_up then self:juice_up(1.0, 0.6) end
    -- `card.lua:2186`: a card that has not finished arriving cannot be picked up.
    if self.states then self.states.hover.can = false end
end

--- Advance this node's lifecycle.
---@param dt number
---@return boolean done true once the tween has run out (or was never running)
function Moveable:advance_lifecycle(dt)
    local life = self._card_lifecycle
    if not life then return true end
    life.age = (life.age or 0) + (tonumber(dt) or 0)
    if life.age >= life.duration then
        -- A materialise hands the node back to the player; a dissolve is about to be
        -- unlinked, and its caller has already shut interaction off for good.
        if life.kind ~= "dissolve" and self.states then
            self.states.hover.can = life.hover_was ~= false
        end
        self._card_lifecycle = nil
        return true
    end
    return false
end

--- The reference's `dissolve` scalar for this node: 0 whole, 1 gone. Nil while idle, which
--- is the flag every draw site tests before reaching for the mask pass.
---@return number|nil
function Moveable:lifecycle_dissolve()
    local life = self._card_lifecycle
    if not life then return nil end
    local duration = math.max(0.001, tonumber(life.duration) or Moveable.DISSOLVE_DURATION)
    local p = math.min(1, math.max(0, (tonumber(life.age) or 0) / duration))
    if life.kind == "dissolve" then return p end
    return 1 - p
end

--- Burn colours for the running lifecycle, or nil while idle.
---@return table|nil burn1, table|nil burn2
function Moveable:lifecycle_burn()
    local life = self._card_lifecycle
    if not life then return nil, nil end
    return life.burn1, life.burn2
end

--- Noise variant seed for the running lifecycle; 0 while idle.
---@return number
function Moveable:lifecycle_seed()
    local life = self._card_lifecycle
    return life and life.seed or 0
end

function Moveable:touchpressed(id, x, y)
    if not self.states.drag.can then return end
    
    self.states.drag.is = true
    self.click_offset.x = x - self.VT.x
    self.click_offset.y = y - self.VT.y
    -- Raise instantly rather than springing up; `move_scale` holds it there for the duration of
    -- the drag and springs it back down on release. Any in-flight scale velocity is dropped so
    -- the jump does not get a wobble on top of it.
    self.VT.scale = (self.T.scale or 1) * (self.drag_raise_scale or 1.08)
    self.velocity.scale = 0
end

function Moveable:touchmoved(id, x, y, dx, dy)
    if not self.states.drag.is then return end
    
    self.VT.x = x - self.click_offset.x
    self.VT.y = y - self.click_offset.y
    self.drag_velocity.x = dx
    self.drag_velocity.y = dy
end

function Moveable:touchreleased(id, x, y)
    self.states.drag.is = false
    self.drag_velocity.x = 0
    self.drag_velocity.y = 0
end

--- Motion physics, ported from the original's `move_xy` / `move_scale` / `move_r`.
---
--- The original does not lerp toward the target, it integrates a velocity that is itself
--- exponentially smoothed toward `35 * displacement`. That carryover is why its cards
--- overshoot and settle instead of decelerating into position and stopping dead.
---
--- Continuous form of the xy filter: `v' = 50*(35*dx - v)`, i.e. omega = sqrt(1750) = 41.8 rad/s
--- with zeta = 0.60. Underdamped on purpose: ~10% overshoot, ~0.19 s ringing period.
---
--- Rate constants (50 / 60 / 190 / 35) are per-second and therefore carry over from the
--- original unchanged. The two that are *not* unitless are `max_vel` and the rotation gain:
--- the original works in tile units, so both need a px-per-unit conversion.
---
--- The conversion is screen-relative rather than card-relative. The original's playfield is
--- `TILE_W = 20` units across and the port's is the 320 px bottom screen, so a unit is 16 px.
--- That makes every screen-space property identical to the original: a saturated node crosses
--- the screen in the same 0.29 s, the velocity clamp engages at the same tenth-of-a-screen
--- displacement, and the lean peaks at the same angle. Scaling by card width
--- instead (the port's cards are 2.2x larger relative to the screen than the original's) would
--- make long moves about twice as fast, which is the snappy-but-flat feel we are moving away
--- from. This is the one number to change if the motion wants to be quicker overall.
local PX_PER_UNIT = 320 / 20 -- port screen width over the original's TILE_W

local SPRING_DRIVE = 35            -- desired velocity, in displacements per second
local RATE_XY = 50                 -- how fast xy velocity chases that desired velocity
local RATE_SCALE = 60
local RATE_R = 190                 -- rotation is nearly unfiltered; it tracks the lean directly
local MAX_VEL = 70 * PX_PER_UNIT   -- px/s ceiling on spring velocity
local TILT_PER_PX = 0.015 / PX_PER_UNIT -- radians of lean per px/s of horizontal velocity

--- Below these the node is close enough to snap and stop; without them a node ticks the full
--- update path forever, chasing a target it can never exactly reach.
local EPS_XY = 0.01 * PX_PER_UNIT  -- 0.16 px, comfortably sub-pixel
local EPS_SCALE = 0.001
local EPS_R = 0.001

--- Long frames are stepped as if they were 1/20 s. A hitch then drops motion rather than
--- teleporting every node across the screen.
local MOVE_DT_CAP = 1 / 20

--- Smoothing coefficients for the current frame. Every Moveable in a frame is stepped with the
--- same dt, so caching on dt means the three `math.exp` calls happen once per frame rather than
--- once per node.
local coef_dt = -1
local exp_xy, exp_scale, exp_r, max_vel = 0, 0, 0, 0

--- @param dt number -- already clamped to MOVE_DT_CAP
local function update_coefficients(dt)
    if dt == coef_dt then return end
    coef_dt = dt

    -- `G.exp_times` is declared in globals.lua but never populated. If something starts filling
    -- it in per frame (as the original's game loop does) it wins; otherwise we derive our own.
    local g = G and G.exp_times
    if g and (g.xy or 0) > 0 and (g.scale or 0) > 0 and (g.r or 0) > 0 and (g.max_vel or 0) > 0 then
        exp_xy, exp_scale, exp_r, max_vel = g.xy, g.scale, g.r, g.max_vel
        return
    end

    -- exp(-rate*dt) is the exact per-frame retention of a continuous decay, so the filters
    -- behave the same at 30 and 60 fps. The linear `min(1, k*dt)` this replaces did not.
    exp_xy = math.exp(-RATE_XY * dt)
    exp_scale = math.exp(-RATE_SCALE * dt)
    exp_r = math.exp(-RATE_R * dt)
    max_vel = MAX_VEL * dt -- px this frame, not px per second
end

--- Clamp a per-frame velocity to `max_vel` without changing its direction.
--- The sqrt is behind the magnitude test, so it only runs on nodes that are actually flying.
local function clamp_velocity(v)
    local sq = v.x * v.x + v.y * v.y
    if sq > max_vel * max_vel then
        local mag = math.sqrt(sq)
        v.x = max_vel * v.x / mag
        v.y = max_vel * v.y / mag
    end
end

--- Trigger "juice", ported from the original's `Moveable:juice_up` / `move_juice`.
---
--- The original does not play a scripted pop. It squashes the card on the spot, then drives
--- the scale spring with a decaying sine - 50.8 rad/s (8.1 Hz) under a cubic falloff for scale,
--- 40.8 rad/s under a square falloff for rotation - and lets the spring's own lag round the
--- corners off. Because the drive is a *target* rather than the rendered value, the same
--- 0.4 s curve reads as a hard pop at high amplitude and a nudge at low amplitude, which is
--- how one function covers everything from a hover tick to a joker firing.
---
--- The port keeps that curve but carries it in a dedicated offset instead of folding it into
--- `VT.scale`: the port's cards draw from their top-left corner, so a scale that moves has to
--- be re-centred at draw time (see `Card:draw`), and layout scale changes must stay separate
--- from the pop. The filter is identical, so for a card sitting at a fixed `T.scale` - which
--- is every card that is juicing - the rendered result is the same number.
local JUICE_DURATION = 0.4
local JUICE_SCALE_FREQ = 50.8
local JUICE_R_FREQ = 40.8

--- Randomness for the jiggle direction, 0..1. Deliberately not `math.random`: the run reseeds
--- that stream for reproducibility, and an animation must never advance it.
local function juice_jitter()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end

--- Start (or restart) the trigger animation on this node.
---
--- The arguments are the original's `Card:juice_up`, not its `Moveable:juice_up`: the caller
--- passes a 0..1 strength and the scale-down to a real amplitude happens here. Every juicing
--- node in this port is a card, a joker or a consumable, so the two layers the original keeps
--- apart collapse into one. Call sites therefore port across verbatim - `juice_up()` is the
--- generic pop, `juice_up(0.6, 0.1)` is what every scoring trigger uses, `juice_up(0.7)` is a
--- joker effect landing on a card.
--- @param scale number|nil trigger strength; 0.11 amplitude when omitted
--- @param rot_amount number|nil rotation strength; a random +-0.16 rad when omitted
function Moveable:juice_up(scale, rot_amount)
    local sign = juice_jitter() > 0.5 and 1 or -1
    local amount = scale and scale * 0.4 or 0.11
    local rot_amt = rot_amount and 0.4 * sign * rot_amount or sign * 0.16
    self.juice = {
        t = 0,
        scale_amt = amount,
        r_amt = rot_amt,
    }
    -- The original's `VT.scale = 1 - 0.6*amount`: the card is caught mid-squash and springs
    -- out of it, so the pop has something to push against instead of starting flat.
    self.juice_off = -0.6 * amount
    self.juice_vel = 0
    self.juice_scale = 1 + self.juice_off
    self.juice_r = 0
end

--- Advance the juice curve. `juice_scale` is nil while idle, which is the flag draw code tests.
---
--- Only touches the `juice*` fields, so anything with a table to keep state in can borrow it -
--- `TopUI` runs its counter pops through here rather than keeping a second copy of the curve.
function Moveable:update_juice(dt)
    local j = self.juice
    if not j then return end
    if dt > MOVE_DT_CAP then dt = MOVE_DT_CAP end
    update_coefficients(dt) -- cached on dt; a no-op when `Moveable:update` already ran it

    local t = j.t + dt
    j.t = t

    local target_scale, target_r = 0, 0
    if t < JUICE_DURATION then
        local decay = 1 - t / JUICE_DURATION
        target_scale = j.scale_amt * math.sin(JUICE_SCALE_FREQ * t) * decay * decay * decay
        target_r = j.r_amt * math.sin(JUICE_R_FREQ * t) * decay * decay
    elseif math.abs(self.juice_off) < EPS_SCALE and math.abs(self.juice_vel) < EPS_SCALE then
        -- The original drops `juice` outright at the end and lets the spring carry whatever
        -- offset is left home; hold on until that has actually happened so the pop never
        -- ends on a hard cut.
        self.juice = nil
        self.juice_scale = nil
        self.juice_r = nil
        self.juice_off, self.juice_vel = 0, 0
        return
    end

    self.juice_vel = exp_scale * self.juice_vel + (1 - exp_scale) * (target_scale - self.juice_off)
    self.juice_off = self.juice_off + self.juice_vel
    self.juice_scale = 1 + self.juice_off
    -- Doubled at the point of use, as in the original: `move_r` folds in `juice.r*2` while
    -- `move_scale` takes `juice.scale` straight. It filters this at 190/s, a lag of well under
    -- a frame, so here it is used raw.
    self.juice_r = 2 * target_r
end

--- Spring VT toward T. `velocity.x/y` are in px per frame, not px per second, so they can be
--- added to VT directly; that is also what `move_r` divides back out to get the lean.
---@param dt number
function Moveable:move_xy(dt)
    local v = self.velocity
    local dx = self.T.x - self.VT.x
    local dy = self.T.y - self.VT.y

    -- Sitting exactly on the target means either we are at rest (the common case for most nodes
    -- most frames) or something outside assigned `VT = T` to place the node instantly. Game code
    -- does that in a dozen places, so drop any carried velocity rather than springing away from
    -- a position that was just set deliberately. Landing exactly on the target by accident is a
    -- measure-zero float coincidence, so nothing legitimate is lost.
    if dx == 0 and dy == 0 then
        v.x, v.y = 0, 0
        return
    end

    v.x = exp_xy * v.x + (1 - exp_xy) * dx * SPRING_DRIVE * dt
    v.y = exp_xy * v.y + (1 - exp_xy) * dy * SPRING_DRIVE * dt
    clamp_velocity(v)

    self.VT.x = self.VT.x + v.x
    self.VT.y = self.VT.y + v.y

    if math.abs(self.VT.x - self.T.x) < EPS_XY and math.abs(v.x) < EPS_XY then
        self.VT.x = self.T.x
        v.x = 0
    end
    if math.abs(self.VT.y - self.T.y) < EPS_XY and math.abs(v.y) < EPS_XY then
        self.VT.y = self.T.y
        v.y = 0
    end
end

--- Spring VT.scale toward T.scale, plus the drag raise. The original folds `juice.scale` in
--- here; the port instead composites the baked juice curve at draw time (see `Card:draw`), so
--- adding it here as well would apply the pop twice.
---@param dt number
function Moveable:move_scale(dt)
    local des_scale = self.T.scale
    if self.states.drag.is then des_scale = des_scale * (self.drag_raise_scale or 1) end

    local v = self.velocity
    if des_scale == self.VT.scale and math.abs(v.scale) <= EPS_SCALE then return end

    -- No explicit dt: (1 - exp_scale) already carries it.
    v.scale = exp_scale * v.scale + (1 - exp_scale) * (des_scale - self.VT.scale)
    self.VT.scale = self.VT.scale + v.scale

    if math.abs(self.VT.scale - des_scale) < EPS_SCALE and math.abs(v.scale) < EPS_SCALE then
        self.VT.scale = des_scale
        v.scale = 0
    end
end

--- Lean into horizontal motion. `vel.x` is px this frame, so `vel.x/dt` is px per second, and
--- the node straightens on its own as the spring runs out of velocity - no explicit easing.
--- `juice.r` is deliberately left out for the same reason as in `move_scale`.
---@param dt number
---@param vel table -- per-frame velocity driving the lean; usually `self.velocity`
function Moveable:move_r(dt, vel)
    local v = self.velocity
    -- Settled and not moving sideways: skip the divide. Most nodes are here most frames.
    if vel.x == 0 and v.r == 0 and self.VT.r == self.T.r then return end

    local des_r = self.T.r + TILT_PER_PX * vel.x / dt

    if des_r ~= self.VT.r or math.abs(v.r) > EPS_R then
        v.r = exp_r * v.r + (1 - exp_r) * (des_r - self.VT.r)
        self.VT.r = self.VT.r + v.r
    end

    if math.abs(self.VT.r - self.T.r) < EPS_R and math.abs(v.r) < EPS_R then
        self.VT.r = self.T.r
        v.r = 0
    end
end

--- Is this node completely at rest?
---
--- Most nodes on most frames are, and the individual helpers below already early-out for
--- them -- but a settled node still made four method calls and around thirty table reads to
--- learn that there was nothing to do. On hardware a method call is 0.65 us and a table field
--- read is a few tenths, so fifty settled nodes were costing a millisecond of the frame to
--- confirm that nothing had moved.
---
--- Every condition mirrors the early-out of the helper it stands in for, so this can only
--- skip work those helpers would themselves have skipped:
---
---   `move_xy`     returns when VT is exactly on T -- zeroing velocity on the way, which is
---                 why velocity has to be zero here rather than merely small.
---   `move_scale`  returns when VT.scale is on its target and |velocity.scale| is within
---                 EPS_SCALE; the target is T.scale only while the node is not being dragged.
---   `move_r`      returns when there is no sideways velocity, no rotational velocity and VT.r
---                 is on T.r.
---   `update_juice`/`update_flip` return when their animation table is absent.
---
--- `update_coefficients` is deliberately not run: it is a cache shared by every node in the
--- frame, and every path that reads it -- the three movers, `clamp_velocity`, and
--- `update_juice` for the callers that drive it directly -- refreshes it first.
---
--- The order is chosen for the moving case: a node in flight fails on velocity or position
--- within the first few reads and never pays for the rest.
local function at_rest(self)
    local v = self.velocity
    if v.x ~= 0 or v.y ~= 0 or v.r ~= 0 then return false end
    if self.juice or self._flip then return false end

    local VT, T = self.VT, self.T
    if VT.x ~= T.x or VT.y ~= T.y or VT.r ~= T.r or VT.scale ~= T.scale then return false end

    local vs = v.scale
    if vs > EPS_SCALE or vs < -EPS_SCALE then return false end

    -- Last, because it is three reads deep and a dragged node has almost always failed one of
    -- the position tests already.
    return not self.states.drag.is
end

function Moveable:update(dt)
    if at_rest(self) then return end

    -- Motion runs on real time, never on the game-speed-scaled `dt` the caller passes for
    -- logic. The original is explicit about this: its event queue reads a clock that game
    -- speed stretches, but `move()` always gets `real_dt` and `move_juice` reads
    -- `TIMERS.REAL` (`game.lua:2622`). A hand at 4x deals and scores four times as fast; the
    -- cards themselves still fly and pop at exactly the same rate.
    dt = (G and G.real_dt) or dt

    local move_dt = dt < MOVE_DT_CAP and dt or MOVE_DT_CAP
    update_coefficients(move_dt)
    -- After the coefficients: the pop is driven through the same scale filter as `move_scale`.
    self:update_juice(move_dt)
    self:update_flip(move_dt)

    local v = self.velocity
    if self.states.drag.is then
        -- The finger owns VT while dragging (see `touchmoved`) - putting a spring between the
        -- two would cost the 1:1 feel. We only borrow the touch delta as this frame's velocity,
        -- which gives the lean below and, on release, throws the node with the flick.
        v.x = self.drag_velocity.x
        v.y = self.drag_velocity.y
        clamp_velocity(v)
        -- Same retention as the xy filter, so a finger that stops moving straightens the node
        -- over ~60 ms at any framerate.
        self.drag_velocity.x = self.drag_velocity.x * exp_xy
        self.drag_velocity.y = self.drag_velocity.y * exp_xy
    else
        self:move_xy(move_dt)
    end

    self:move_scale(move_dt)
    self:move_r(move_dt, v)
end

--- Push the transform a card-shaped sprite is drawn under, flattened.
---
--- The chain every card draw used to build by hand was
---
---     translate(x, y) scale(s, s) translate(w/2, h/2) rotate(r) scale(f, 1) translate(-w/2, -h/2)
---
--- which is eight graphics calls with the push and pop, measured at 17.1 us on a New 3DS --
--- and `Card:draw` builds it twice, once for the shadow and once for the card. Six of those
--- calls are avoidable arithmetic:
---
---     scale(s,s) after translate(w/2,h/2) is translate(s*w/2, s*h/2) before it, and a uniform
---     scale commutes with a rotation, so the whole thing is
---
---       translate(x + s*w/2, y + s*h/2) rotate(r) scale(s*f, s) translate(-w/2, -h/2)
---
--- and when there is no rotation the two centring translates cancel outright, leaving
---
---       translate(x + s*w*(1-f)/2, y) scale(s*f, s)
---
--- which is what an unrotated card -- almost every card, almost every frame -- actually needs.
--- The result is the same matrix to the bit in both cases; this is algebra, not an
--- approximation.
---
--- Caller pops.
---@param x number top-left of the sprite, before scaling
---@param y number
---@param w number unscaled sprite width; the rotation and flip pivot is its centre
---@param h number
---@param s number uniform scale about the top-left
---@param r number rotation about the sprite centre
---@param flip_sx number horizontal pinch about the sprite centre, 1 when not flipping
function Moveable.push_sprite_transform(x, y, w, h, s, r, flip_sx)
    local g = love.graphics
    g.push()

    if r == 0 then
        local sx = s * flip_sx
        g.translate(x + s * w * (1 - flip_sx) * 0.5, y)
        if sx ~= 1 or s ~= 1 then g.scale(sx, s) end
        return
    end

    g.translate(x + s * w * 0.5, y + s * h * 0.5)
    g.rotate(r)
    g.scale(s * flip_sx, s)
    g.translate(-w * 0.5, -h * 0.5)
end

--- Push `translate(px, py) rotate(r) scale(sx, sy) translate(-px, -py)`, flattened.
---
--- The rotate-and-scale-about-a-point shape jokers and consumables use. Without a rotation it
--- collapses to `translate(px*(1-sx), py*(1-sy)) scale(sx, sy)`, and with no scale either it
--- collapses to nothing at all -- which is the common case for a joker sitting in its slot.
---
--- Caller pops.
function Moveable.push_pivot_transform(px, py, r, sx, sy)
    local g = love.graphics
    g.push()

    if r == 0 then
        if sx == 1 and sy == 1 then return end
        g.translate(px * (1 - sx), py * (1 - sy))
        g.scale(sx, sy)
        return
    end

    g.translate(px, py)
    g.rotate(r)
    g.scale(sx, sy)
    g.translate(-px, -py)
end

function Moveable:draw_boundingrect()
    if not G or not G.DEBUG then return end
    local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
    
    local draw_x = self.VT.x + self.collision_offset.x
    local draw_y = self.VT.y + self.collision_offset.y
    
    if self.states.collide.is then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(0, 1, 0, 1)
    end
    
    love.graphics.push()
    
    local cx = draw_x + (self.VT.w * self.VT.scale) / 2
    local cy = draw_y + (self.VT.h * self.VT.scale) / 2
    
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.VT.r)
    love.graphics.translate(-cx, -cy)
    
    love.graphics.rectangle(
        "line",
        draw_x,
        draw_y,
        self.VT.w * self.VT.scale,
        self.VT.h * self.VT.scale
    )
    
    love.graphics.pop()
    love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end
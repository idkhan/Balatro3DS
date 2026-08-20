--- Lightweight pooled primitive particles for short UI bursts.
---
--- Texture particles would consume scarce 3DS VRAM, so this deliberately draws only
--- points and rectangles. The pool is bounded: effects may shed particles under load
--- rather than allocating during a frame on the Old 3DS's 268 MHz ARM11.

local Particles = {}

local DEFAULT_CAPACITY = 96
local WHITE = { 1, 1, 1, 1 }

--- Randomness for particle variety, 0..1. Deliberately not `math.random`: the run reseeds
--- that stream for reproducibility, and an animation must never advance it.
local function pick_random()
    if love and love.math and love.math.random then return love.math.random() end
    return 0.5
end
local capacity = 0
local active = {}
local active_count = 0
local free = {}

local function new_particle()
    return {
        x = 0, y = 0, vx = 0, vy = 0, gravity = 0,
        age = 0, lifetime = 0,
        w = 1, h = 1, base_w = 1, base_h = 1,
        colour = WHITE, fade = true, grow = false, point = false,
    }
end

--- Experimental batched draw. **This is slower on hardware. Do not turn it on.**
---
--- The idea was sound and the measurement settled it against us. Every particle is an
--- axis-aligned filled rectangle, and an untextured Mesh collapses seventy of them into one
--- draw -- the same PRIMITIVE path a rectangle takes (`drawcommand.tcc` defaults the format,
--- and Mesh only switches to TEXTURE when it has a texture, `mesh.cpp:212`), with the
--- per-vertex colour particles need. What it costs is marshalling 420 vertices out of Lua
--- tables across the C boundary every frame, and on a New 3DS that is the more expensive half
--- by a wide margin:
---
---     70 ordinary rectangles     1.027 ms
---     this mesh path             2.733 ms
---     Mesh:setVertices alone     0.871 ms
---     drawing an already-built mesh   0.161 ms
---
--- The draw itself is nearly free; building it is 2.5 ms. So this stays off, and it is kept
--- only as the thing the number above refers to -- `benchmark.lua`'s `particles_mesh_70`
--- against `particles_rect_70` is the whole argument, and deleting the path would delete the
--- ability to re-run it after a runtime change.
---
--- The rectangle path is also no longer what it was when this was written. The coalescing
--- flush in the ctr renderer merges adjacent compatible commands, and seventy untextured
--- rectangles with nothing between them are one run -- so they now cost seventy cheap
--- DrawCommands and ONE GPU submission, natively, with no Lua vertex tables at all. That is
--- the shape this was reaching for, arrived at from the other end.
---
--- `Particles.set_batched(true)` still flips it, for measurement.
local batch_mesh, batch_verts, batch_submit
local batch_supported = nil
local batch_submit_len = 0
local batch_live = 0
local batching = false

--- Rebuild the vertex pool and drop the mesh, so the next draw sizes both to `capacity`.
local function reset_batch()
    if batch_mesh and batch_mesh.release then pcall(function() batch_mesh:release() end) end
    batch_mesh, batch_verts, batch_submit = nil, nil, nil
    batch_submit_len, batch_live = 0, 0
    -- Availability is a property of the runtime, not the pool, so a probe result survives.
end

--- Lazily build the mesh at `capacity * 6` vertices. Returns false once, permanently, on a
--- runtime without `newMesh` or the `Mesh:setVertices` binding (which this port patches in;
--- upstream declares it and never wrote it).
local function ensure_batch()
    if batch_supported == false then return false end
    if batch_mesh then return true end
    if capacity <= 0 then return false end
    if not (love.graphics and love.graphics.newMesh) then
        batch_supported = false
        return false
    end

    local verts = {}
    for i = 1, capacity * 6 do
        -- {x, y, u, v, r, g, b, a}. The uv pair stays zero for the life of the mesh; an
        -- untextured mesh never reads it.
        verts[i] = { 0, 0, 0, 0, 1, 1, 1, 1 }
    end

    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "dynamic")
    if not ok or type(mesh) ~= "table" and type(mesh) ~= "userdata" then
        batch_supported = false
        return false
    end
    if type(mesh.setVertices) ~= "function" then
        if mesh.release then pcall(function() mesh:release() end) end
        batch_supported = false
        return false
    end

    batch_mesh, batch_verts, batch_submit = mesh, verts, {}
    batch_submit_len, batch_live = 0, 0
    batch_supported = true
    return true
end

local function write_vertex(v, x, y, r, g, b, a)
    v[1] = x; v[2] = y
    v[5] = r; v[6] = g; v[7] = b; v[8] = a
end

--- Draw every active particle as one mesh. Returns false if the batch is unavailable, so
--- the caller can fall back without having drawn anything.
local function draw_batched()
    if not ensure_batch() then return false end

    local verts = batch_verts
    for i = 1, active_count do
        local particle = active[i]
        local colour = particle.colour
        local alpha = tonumber(colour[4]) or 1
        if particle.fade then
            alpha = alpha * (1 - particle.age / particle.lifetime)
        end
        local r, g, b = colour[1] or 1, colour[2] or 1, colour[3] or 1
        local x0, y0 = particle.x - particle.w * 0.5, particle.y - particle.h * 0.5
        local x1, y1 = x0 + particle.w, y0 + particle.h
        local o = (i - 1) * 6
        write_vertex(verts[o + 1], x0, y0, r, g, b, alpha)
        write_vertex(verts[o + 2], x1, y0, r, g, b, alpha)
        write_vertex(verts[o + 3], x1, y1, r, g, b, alpha)
        write_vertex(verts[o + 4], x0, y0, r, g, b, alpha)
        write_vertex(verts[o + 5], x1, y1, r, g, b, alpha)
        write_vertex(verts[o + 6], x0, y1, r, g, b, alpha)
    end

    local live = active_count * 6
    local write = live
    local has_range = type(batch_mesh.setDrawRange) == "function"
    if not has_range and batch_live > live then
        -- Without a draw range the mesh always renders its whole buffer, so last frame's
        -- tail has to be collapsed to zero-area triangles. Only the slots that just died
        -- are rewritten, so a steady burst costs nothing extra.
        for i = live + 1, batch_live do
            write_vertex(verts[i], 0, 0, 0, 0, 0, 0)
        end
        write = batch_live
    end

    -- `setVertices` reads `#` off this table, so it has to be exactly as long as the run
    -- being written. Entries alias the pool; nothing is allocated per frame.
    local submit = batch_submit
    for i = 1, write do submit[i] = verts[i] end
    for i = write + 1, batch_submit_len do submit[i] = nil end
    batch_submit_len = write

    batch_mesh:setVertices(submit)
    if has_range then batch_mesh:setDrawRange(1, live) end
    batch_live = active_count * 6

    -- Mesh colour comes from the vertices; setColor would be ignored. Reset white anyway so
    -- the surrounding draw state matches the per-rectangle path exactly.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(batch_mesh)
    return true
end

--- Forget whether the batched draw is available, so the next draw probes again. The answer
--- cannot change on a console, so nothing in the game needs this; tests that hide
--- `love.graphics.newMesh` do, or the probe latches off for every later test.
function Particles.reset_batch_probe()
    batch_supported = nil
    reset_batch()
end

--- Turn the batched draw on or off. Off by default; see `draw_batched`.
--- Turn the experimental mesh path on. It is slower on hardware -- see the note above the
--- batch state -- so this exists for `benchmark.lua` and for re-measuring after a runtime
--- change, not for shipping.
function Particles.set_batched(enabled)
    batching = enabled and true or false
end

--- @return boolean enabled, boolean|nil supported
function Particles.batched()
    return batching, batch_supported
end

--- Clear active particles and preallocate up to `max_particles`.
--- This is intended for a state transition or test setup, never a frame path.
function Particles.reset(max_particles)
    capacity = math.max(0, math.floor(tonumber(max_particles) or DEFAULT_CAPACITY))

    for i = active_count, 1, -1 do
        free[#free + 1] = active[i]
        active[i] = nil
    end
    active_count = 0

    while #free > capacity do
        free[#free] = nil
    end
    while #free < capacity do
        free[#free + 1] = new_particle()
    end

    reset_batch()
end

--- Emit one primitive particle.
--- @param spec table x, y, vx, vy, gravity, lifetime, colour/color, fade, shape, w/h or size
--- @return table|nil particle, string|nil error
function Particles.emit(spec)
    if type(spec) ~= "table" then return nil, "invalid_spec" end
    local lifetime = tonumber(spec.lifetime) or tonumber(spec.life)
    if not lifetime or lifetime <= 0 then return nil, "invalid_lifetime" end

    local particle = free[#free]
    if not particle then return nil, "pool_exhausted" end
    free[#free] = nil

    local size = tonumber(spec.size) or 1
    particle.x = tonumber(spec.x) or 0
    particle.y = tonumber(spec.y) or 0
    particle.vx = tonumber(spec.vx) or 0
    particle.vy = tonumber(spec.vy) or 0
    particle.gravity = tonumber(spec.gravity) or 0
    particle.age = 0
    particle.lifetime = lifetime
    particle.base_w = tonumber(spec.w) or size
    particle.base_h = tonumber(spec.h) or size
    -- `grow` particles start at nothing; anything else is full size on its first frame.
    particle.grow = spec.grow == true
    particle.w = particle.grow and 0 or particle.base_w
    particle.h = particle.grow and 0 or particle.base_h
    -- The reference picks each particle's colour out of the emitter's whole list
    -- (`reference/Balatro/engine/particles.lua:92`), which is what stops a burst reading as
    -- one flat puff. A single `colour` is still accepted; most callers only have one.
    local list = spec.colours
    if list and #list > 0 then
        particle.colour = list[math.floor(pick_random() * #list) + 1] or list[1]
    else
        particle.colour = spec.colour or spec.color or WHITE
    end
    particle.fade = spec.fade ~= false
    particle.point = spec.shape == "point"

    active_count = active_count + 1
    active[active_count] = particle
    return particle
end

--------------------------------------------------------------------------------
-- Dissolve shedding
--
-- The reference does not fire one salvo when a card is destroyed. `Card:start_dissolve`
-- attaches a `Particles` emitter to the card with `fill = true` and a 7 ms timer
-- (`reference/Balatro/card.lua:2136-2145`), so shards keep coming from random points
-- across the card's whole area for as long as the tween runs and the card sheds rather
-- than puffs. The rate here is much slower than the reference's: this pool is 96 slots
-- for the whole game, and five cards can be destroyed at once (Immolate, a discard of
-- five glass cards), where the reference allocates an emitter per card.
--------------------------------------------------------------------------------

-- Rate and speed were both settled by eye against the shader running beside it: a shard every
-- 36 ms over a 0.7 s dissolve is about twenty per card, enough to read as shedding without
-- crowding a 96-slot pool when five cards go at once.
local SHED_INTERVAL = 0.036
--- Shards outlive most of the tween they came from, which is what stops a dissolve
--- ending on an empty screen.
local SHED_LIFETIME = 0.49
--- Peak size, reached at half life. The reference's shards are 0.1 game units against a card
--- roughly 3.5 units wide, so on a 71 px card that is about three pixels.
local SHED_SIZE = 3
--- The reference's shards do not fall. They set off in a random direction at
--- `speed * 0.7 * random` and bleed 7% of that a second (`engine/particles.lua:84`, `:126`),
--- which reads as embers hanging around the card rather than debris dropping out of it. That
--- is most of the difference between a card burning and a card breaking, so gravity is zero
--- here and the spread is the whole circle. The speed is above the reference's ~28 px/s
--- equivalent because a 240p screen swallows anything slower, and again by eye from there.
local SHED_SPEED_MIN, SHED_SPEED_MAX = 23, 60
local SHED_SPEC = {
    x = 0, y = 0, vx = 0, vy = 0, gravity = 0,
    lifetime = SHED_LIFETIME, w = SHED_SIZE, h = SHED_SIZE,
    colour = nil, colours = nil, fade = false, grow = true,
}

--- Shed shards from a rectangle for one frame of a dissolve.
---
--- `state` is any table the caller already keeps per dissolving node - the lifecycle table
--- itself, in practice - and only its `shed` field is touched. Passing it in rather than
--- reading a node keeps this module ignorant of Moveable, which is what lets both the
--- hand's ghost list and Game's use it.
---@param state table accumulates into `state.shed`
---@param dt number
---@param cx number rect centre x
---@param cy number rect centre y
---@param w number rect width
---@param h number rect height
---@param colours table a list of shard tints, one picked per shard, or a single colour
---@return table|nil particle the shard emitted this frame, if the timer came due
function Particles.shed_dissolve(state, dt, cx, cy, w, h, colours)
    if type(state) ~= "table" then return end
    local t = (state.shed or SHED_INTERVAL) + (tonumber(dt) or 0)
    -- One shard a frame at most: a long frame must not dump the pool into a single card.
    if t < SHED_INTERVAL then
        state.shed = t
        return
    end
    state.shed = t - SHED_INTERVAL
    -- A caller with one colour and a caller with a palette both land here; `emit` picks per
    -- shard when it is given a list.
    if colours and type(colours[1]) == "table" then
        SHED_SPEC.colours, SHED_SPEC.colour = colours, nil
    else
        SHED_SPEC.colours, SHED_SPEC.colour = nil, colours
    end
    SHED_SPEC.x = cx + (pick_random() - 0.5) * (w or 0)
    SHED_SPEC.y = cy + (pick_random() - 0.5) * (h or 0)
    local angle = pick_random() * math.pi * 2
    local speed = SHED_SPEED_MIN + pick_random() * (SHED_SPEED_MAX - SHED_SPEED_MIN)
    SHED_SPEC.vx = math.cos(angle) * speed
    SHED_SPEC.vy = math.sin(angle) * speed
    return Particles.emit(SHED_SPEC)
end

--- Advance every active particle without allocating or removing table entries.
function Particles.update(dt)
    dt = tonumber(dt) or 0
    if dt <= 0 then return end

    local i = active_count
    while i >= 1 do
        local particle = active[i]
        particle.age = particle.age + dt
        if particle.age >= particle.lifetime then
            active[i] = active[active_count]
            active[active_count] = nil
            active_count = active_count - 1
            free[#free + 1] = particle
            if i > active_count then i = active_count end
        else
            particle.vy = particle.vy + particle.gravity * dt
            particle.x = particle.x + particle.vx * dt
            particle.y = particle.y + particle.vy * dt
            if particle.grow then
                -- The reference's particle scale is a triangle that peaks at half life and
                -- is clamped there (`engine/particles.lua:117`), so a shard swells in and
                -- shrinks out rather than blinking on at full size and fading.
                local p = particle.age / particle.lifetime
                local e = 2 * (p < 1 - p and p or 1 - p)
                if e > 1 then e = 1 end
                particle.w = particle.base_w * e
                particle.h = particle.base_h * e
            end
            i = i - 1
        end
    end
end

--- Draw the active pool. Particles retain their caller-owned colour table.
---
--- The colour is only pushed when it actually changes. Particles arrive in bursts that share
--- a colour table and are emitted on the same frame, so they also age together and the alpha
--- the fade computes matches -- measured across a saturated 70-particle pool, 96% of the
--- setColor calls asked for exactly what was already set, and that held as the burst decayed.
--- setColor is pure state (it writes four floats into the graphics state, `graphics.tcc:998`),
--- so skipping the repeats cannot change a pixel; it just stops crossing into C++ 68 times a
--- frame to write the same value.
function Particles.draw()
    if active_count == 0 then return end
    if batching and draw_batched() then return end
    local lr, lg, lb, la
    for i = 1, active_count do
        local particle = active[i]
        local colour = particle.colour
        local alpha = tonumber(colour[4]) or 1
        if particle.fade then
            alpha = alpha * (1 - particle.age / particle.lifetime)
        end
        local r, g, b = colour[1] or 1, colour[2] or 1, colour[3] or 1
        if r ~= lr or g ~= lg or b ~= lb or alpha ~= la then
            love.graphics.setColor(r, g, b, alpha)
            lr, lg, lb, la = r, g, b, alpha
        end
        if particle.point and love.graphics.points then
            love.graphics.points(particle.x, particle.y)
        else
            love.graphics.rectangle("fill", particle.x - particle.w * 0.5,
                particle.y - particle.h * 0.5, particle.w, particle.h)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--- @return integer
function Particles.count()
    return active_count
end

Particles.reset(DEFAULT_CAPACITY)

return Particles

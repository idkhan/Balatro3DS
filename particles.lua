--- Lightweight pooled primitive particles for short UI bursts.
---
--- Texture particles would consume scarce 3DS VRAM, so this deliberately draws only
--- points and rectangles. The pool is bounded: effects may shed particles under load
--- rather than allocating during a frame on the Old 3DS's 268 MHz ARM11.

local Particles = {}

local DEFAULT_CAPACITY = 96
local WHITE = { 1, 1, 1, 1 }
local capacity = 0
local active = {}
local active_count = 0
local free = {}

local function new_particle()
    return {
        x = 0, y = 0, vx = 0, vy = 0, gravity = 0,
        age = 0, lifetime = 0,
        w = 1, h = 1,
        colour = WHITE, fade = true, point = false,
    }
end

--- Optional batched draw.
---
--- Every particle is an axis-aligned filled rectangle, and each `love.graphics.rectangle`
--- becomes its own DrawCommand in the runtime -- a heap allocation plus a vertex copy per
--- particle. On a saturated pool that is 70 of the roughly 150 draw commands the whole frame
--- issues, all on the burst frames most likely to drop one.
---
--- An untextured Mesh collapses them into one. It is the same PRIMITIVE draw path a
--- rectangle takes (`drawcommand.tcc:33` defaults the format, and Mesh only switches to
--- TEXTURE when it has a texture, `mesh.cpp:212`), and per-vertex colour is exactly what
--- particles need -- Mesh ignores `setColor`, which is why the fallback path cannot be
--- expressed this way round.
---
--- Off by default: the reduction in draw commands is certain, but it is paid for by
--- marshalling six vertices per particle out of Lua tables, and which side wins is a
--- question only a hardware profile can answer. `Particles.set_batched(true)` flips it.
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
        local x0, y0 = particle.x, particle.y
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
    particle.w = tonumber(spec.w) or size
    particle.h = tonumber(spec.h) or size
    particle.colour = spec.colour or spec.color or WHITE
    particle.fade = spec.fade ~= false
    particle.point = spec.shape == "point"

    active_count = active_count + 1
    active[active_count] = particle
    return particle
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
            love.graphics.rectangle("fill", particle.x, particle.y, particle.w, particle.h)
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

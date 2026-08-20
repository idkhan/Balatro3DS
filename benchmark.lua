--- On-device performance benchmark.
---
--- Everything in this port's performance work eventually runs into the same wall: the
--- failures that matter only happen on a 268 MHz ARM11 with PUC Lua 5.1 and a PICA200, and
--- a host LuaJIT measurement does not predict any of them. This module answers the
--- questions that decide the remaining work, on the actual machine, and writes the numbers
--- somewhere they can be read back.
---
--- What it is built to answer:
---
---  * What does one draw command cost? That single constant decides every batching
---    question -- particles, panels, text -- and it is the thing the desktop stub cannot
---    show. `rect_fill_square` against `mesh_draw_only` is the whole argument.
---  * What does a *rounded* rect cost over a square one? That is the price of the corner
---    fan, and it sizes the prebaked-panel idea.
---  * Is the frame fill-rate bound or call bound? `fill_full_screen` against
---    `fill_quarter_screen` separates them: if time scales with area it is fill rate, if it
---    barely moves it is per-call overhead. That decides whether the shadow overdraw on the
---    top screen is worth attacking.
---  * Does batching particles into one mesh actually win? `particles_rect_70` against
---    `particles_mesh_70`, with `mesh_setvertices_420` isolating the marshalling cost that
---    is the whole risk.
---  * How slow is Lua here really? The `lua_*` cases calibrate the interpreter so host
---    numbers can be scaled, and they size the LuaJIT question.
---  * How expensive is a texture load? That is the hitch a mid-frame atlas load causes and
---    the thing a loader thread on the second core would move off the main thread.
---  * What does a texture *switch* cost? The ctr renderer queues same-texture draws and only
---    flushes to `C3D_DrawArrays` plus `C3D_TexBind` when the bound texture changes
---    (`renderer_ext.cpp:189-205`), and `Card:draw` alternates face/rank/seal atlases per
---    card. If the switch is expensive, sorting a hand's layers by atlas is a free win.
---  * Does a SpriteBatch beat individual draws? A batch renders all its sprites as one
---    DrawCommand (`spritebatch.cpp:248`), which is the only batching primitive this backend
---    has now that canvases are ruled out. Both the static case (draw a prefilled batch) and
---    the rebuild case (clear+add every frame, the moving-card scenario) are measured,
---    because the rebuild's Lua-side `add` calls are the whole risk.
---  * Does a TextBatch beat `print`? Every `print` re-shapes the string in C++
---    (`font.cpp:451`); a TextBatch shapes once at `set`. The top screen issues 33 text
---    calls a frame, most of them static labels.
---  * Is the frame CPU-bound or GPU-bound overall? `frame_time_60` samples wall dt plus
---    citro3d's own `C3D_GetProcessingTime`/`C3D_GetDrawingTime` across 60 real frames.
---    If GPU time is a sliver of frame time, every remaining fight is on the ARM11.
---  * Can a second thread help? `love.thread` compiles on ctr, but nothing in the runtime
---    calls `APT_SetAppCpuTimeLimit`, so a worker may just contend with the main thread on
---    the appcore. The roundtrip case gives the loader-latency floor; the busy-spinner case
---    runs known CPU work next to a spinning thread, and the ratio against `lua_arith_1k`
---    says which core the OS actually put it on.
---
--- Timing is `love.timer.getTime`, which on 3DS reads `svcGetSystemTick` and converts to
--- milliseconds as a double (`platform/ctr/source/modules/timer_ext.cpp:15-19`), so it
--- resolves well below a microsecond. Every case still runs enough repetitions to swamp
--- the call overhead of the timer itself.
---
--- Cases run one per frame so the run never blocks long enough to look like a hang, and
--- draw-phase cases run from inside `love.draw` because that is the only place graphics
--- calls are meaningful -- outside a frame they are building commands nobody submits.

local Console = require "console"

local Benchmark = {}

--- Where the report is written. PhysFS is anchored at `sdmc:/3ds/lovepotion.3dsx` by the
--- runtime patch, so this lands in `sdmc:/3ds/save/<identity>/`.
Benchmark.REPORT_FILE = "benchmark.txt"

local running = false
local finished = false
local index = 1
local results = {}
local stepped_this_frame = false
local page = 1
local report_text = nil
local write_status = nil

--------------------------------------------------------------------------------
-- timing
--------------------------------------------------------------------------------

local function now()
    return love.timer.getTime()
end

--- Microseconds per repetition. `reps` is chosen per case so the run lands in the tens of
--- milliseconds: long enough that timer granularity and loop overhead are noise, short
--- enough that no single frame stalls for a visible beat.
local function time_us(fn, reps, warmup)
    for i = 1, (warmup or math.min(reps, 8)) do fn(i) end
    local t0 = now()
    for i = 1, reps do fn(i) end
    local elapsed = now() - t0
    return (elapsed / reps) * 1000000
end

--------------------------------------------------------------------------------
-- shared fixtures
--------------------------------------------------------------------------------

local fx = {}

local function fixture_image(game)
    if fx.image then return fx.image end
    local atlas = game.ensure_asset_atlas_loaded and game:ensure_asset_atlas_loaded("chips")
    if atlas and atlas.image then
        fx.image = atlas.image
        fx.quad = game.atlas_cell_quad and select(1, game:atlas_cell_quad(atlas, 0)) or nil
    end
    return fx.image
end

local function fixture_font(game)
    local P = game.FONTS and game.FONTS.PIXEL
    return P and (P.SMALL or P.MEDIUM), P and (P.MEDIUM or P.SMALL)
end

local LOREM = "The quick brown fox jumps over the lazy dog and keeps running"

--------------------------------------------------------------------------------
-- cases
--------------------------------------------------------------------------------
--
-- `phase` says where the case may run: "draw" cases issue graphics calls and must be inside
-- love.draw; "cpu" cases are pure Lua or asset work and run from update; a "frame" case
-- samples across real frames rather than looping inside one.
-- `unit` is what the number means: "us" is microseconds per repetition, "ms" total.
--
-- `verts` is MANDATORY for any draw case that submits geometry: it is the number of vertices
-- one repetition puts into the frame's vertex buffer, and the runner uses it to decide how
-- many repetitions may share a frame. See VERTEX_BUDGET below for why a wrong value here is
-- a memory-corrupting crash rather than a bad number. The counts are:
--
--   square fill rect        4      (TRIANGLE_FAN, graphics.tcc Polygon)
--   rounded fill rect       (p+2)*4 where p = max(CalculateEllipsePoints/4, 1); a radius of
--                           4 gives p=2 -> 16, a radius of 8 gives p=3 -> 20
--   line rect               ~24     (polyline, miter joins)
--   textured quad           4      (texture_ext.cpp:338)
--   one glyph               6      (font.cpp:368)
--   SpriteBatch draw        6 per sprite in the batch (spritebatch.cpp:248)
--   Mesh draw               its own vertex count
--
-- `own_buffer` is the one legitimate way to draw without declaring `verts`: a case that
-- submits through its own VBO never enters the shared frame budget at all. It has to be
-- stated rather than inferred, because the failure mode of a wrongly-omitted `verts` is a
-- corrupted heap rather than a bad number.

local CASES = {}

local function case(group, name, phase, reps, run, opts)
    opts = opts or {}
    CASES[#CASES + 1] = {
        group = group, name = name, phase = phase, reps = reps, run = run,
        unit = opts.unit or "us", setup = opts.setup, teardown = opts.teardown,
        note = opts.note, available = opts.available, count_draws = opts.count_draws,
        verts = opts.verts or 0, own_buffer = opts.own_buffer,
    }
end

-- ---------------------------------------------------------------- primitives
-- The per-draw-command constant. Everything else is measured against these two.

case("primitive", "rect_fill_square", "draw", 300, function(i)
    love.graphics.rectangle("fill", (i % 64), 8, 8, 8)
end, { verts = 4 })

case("primitive", "rect_fill_round4", "draw", 300, function(i)
    love.graphics.rectangle("fill", (i % 64), 8, 8, 8, 4, 4)
end, { verts = 16, note = "minus rect_fill_square = cost of the corner fan" })

case("primitive", "rect_fill_round8", "draw", 300, function(i)
    love.graphics.rectangle("fill", (i % 64), 8, 24, 24, 8, 8)
end, { verts = 20 })

case("primitive", "rect_line_square", "draw", 300, function(i)
    love.graphics.rectangle("line", (i % 64), 8, 8, 8)
end, { verts = 24 })

case("primitive", "setColor", "draw", 3000, function(i)
    love.graphics.setColor(1, 1, 1, (i % 8) / 8)
end, { note = "the call this port dedupes in particles.lua" })

case("primitive", "push_translate_pop", "draw", 1500, function(i)
    love.graphics.push()
    love.graphics.translate(i % 8, 0)
    love.graphics.pop()
end)

case("primitive", "newQuad", "draw", 1500, function()
    love.graphics.newQuad(0, 0, 8, 8, 128, 128)
end, { note = "allocation; the blind chip path used to do this every frame" })

-- ---------------------------------------------------------------- textured / text

case("texture", "image_quad_draw", "draw", 300, function(i)
    love.graphics.draw(fx.image, fx.quad, (i % 64), 8)
end, { verts = 4, available = function() return fx.image ~= nil and fx.quad ~= nil end })

case("text", "print_short", "draw", 300, function(i)
    love.graphics.print("Score", (i % 64), 8)
end, { verts = 30 })

case("text", "printf_wrapped", "draw", 150, function(i)
    love.graphics.printf(LOREM, (i % 32), 8, 280, "left")
end, {
    verts = 360,
    count_draws = true,
    note = "glyphs batch by sheet, so this should be near one draw command",
})

case("text", "setFont", "draw", 1500, function(i)
    local a, b = fixture_font(_G.G)
    love.graphics.setFont((i % 2 == 0) and a or b or a)
end)

case("text", "textbatch_draw_short", "draw", 300, function(i)
    love.graphics.draw(fx.textbatch, (i % 64), 8)
end, {
    -- Shaped once here, at set time; print_short re-shapes per call (font.cpp:451). The
    -- delta, times the top screen's ~33 mostly-static labels, is what caching them saves.
    setup = function(game)
        if fx.textbatch or not love.graphics.newTextBatch then return end
        local font = fixture_font(game)
        if not font then return end
        local ok, batch = pcall(love.graphics.newTextBatch, font, "Score")
        if ok and batch then fx.textbatch = batch end
    end,
    available = function() return fx.textbatch ~= nil end,
    verts = 30,
    count_draws = true,
    note = "pre-shaped text; the delta under print_short is per-call shaping",
})

-- ---------------------------------------------------------------- transforms
-- Card:draw brackets each of its two passes in a seven-op push/translate/scale/rotate
-- chain; love.graphics.draw can take x/y/r/sx directly and build the matrix once in C++.
-- These two against image_quad_draw say whether flattening the chain is worth the refactor.

-- DynaText draws one glyph at a time -- `text:sub(i, i)`, `font:getWidth(glyph)` and a
-- transformed `print` per character -- so a nine-character headline is nine of the 52 us
-- `print_short` measures plus nine font-metric lookups. The static case is the same string
-- every frame with no animation enabled, which is the shape a cached decomposition helps; the
-- animated case adds the float/rotation sine per glyph on top.

local function dyna_fixture(key, config)
    if fx[key] then return fx[key] end
    local ok, DynaText = pcall(require, "dyna_text")
    if not ok then return nil end
    fx.dyna = DynaText
    fx[key] = DynaText.new(config)
    return fx[key]
end

case("text", "dynatext_static_9", "draw", 150, function()
    fx.dyna.draw(fx.dyna_static, "Game Over", 8, 8, 200, "left")
end, {
    setup = function() dyna_fixture("dyna_static", {}) end,
    available = function() return fx.dyna ~= nil and fx.dyna_static ~= nil end,
    verts = 54,
    note = "nine glyphs, no animation: this one should fall straight through to printf",
})

case("text", "dynatext_animated_9", "draw", 100, function()
    fx.dyna.draw(fx.dyna_animated, "Game Over", 8, 8, 200, "left")
end, {
    setup = function()
        dyna_fixture("dyna_animated", { float_amount = 2, rotation_amount = 0.08 })
    end,
    available = function() return fx.dyna ~= nil and fx.dyna_animated ~= nil end,
    verts = 54,
    count_draws = true,
    note = "nine per-glyph transformed prints; the glyph loop's real cost",
})

case("transform", "transform_chain_card", "draw", 300, function(i)
    love.graphics.push()
    love.graphics.translate(i % 8, 150)
    love.graphics.scale(1, 1)
    love.graphics.translate(35.5, 47.5)
    love.graphics.rotate(0.05)
    love.graphics.scale(1, 1)
    love.graphics.translate(-35.5, -47.5)
    love.graphics.pop()
end, { note = "the seven-op chain Card:draw runs twice per card, without the draw" })

case("transform", "image_draw_args_rotated", "draw", 300, function(i)
    love.graphics.draw(fx.image, fx.quad, (i % 64), 8, 0.05, 1, 1)
end, {
    available = function() return fx.image ~= nil and fx.quad ~= nil end,
    verts = 4,
    note = "rotation as draw args; minus image_quad_draw = the C++ matrix cost of r ~= 0",
})

-- ---------------------------------------------------------------- batching
-- The ctr renderer only flushes queued vertices when the bound texture changes; a flush is
-- one C3D_DrawArrays plus a C3D_TexBind. Card:draw interleaves face/rank/seal atlases, so a
-- full hand pays ~25 of those switches a frame. These four cases price the switch and both
-- SpriteBatch strategies against plain draws.

case("batching", "image_draw_20_one_texture", "draw", 40, function(i)
    local img, quad = fx.image, fx.quad
    for k = 1, 20 do love.graphics.draw(img, quad, ((i + k * 3) % 64), 8) end
end, {
    available = function() return fx.image ~= nil and fx.quad ~= nil end,
    verts = 80,
    count_draws = true,
    note = "20 draws, one texture; the renderer queues these without flushing",
})

case("batching", "image_draw_20_two_textures", "draw", 40, function(i)
    local a, b, quad = fx.image, fx.image2, fx.quad
    for k = 1, 20 do
        love.graphics.draw((k % 2 == 0) and a or b, quad, ((i + k * 3) % 64), 8)
    end
end, {
    -- A second copy of the same sheet: identical pixels, distinct GPU handle, so the only
    -- difference from the case above is the per-draw flush and rebind.
    setup = function()
        if fx.image2 then return end
        local ok, img = pcall(love.graphics.newImage, "resources/textures/1x/chips.png",
            { dpiscale = 1, mipmaps = false })
        if ok and img then fx.image2 = img end
    end,
    available = function() return fx.image ~= nil and fx.image2 ~= nil and fx.quad ~= nil end,
    verts = 80,
    count_draws = true,
    note = "alternating textures; minus the case above, /20, = one texture switch",
})

local function fixture_spritebatch(game)
    if fx.batch then return fx.batch end
    if not (love.graphics.newSpriteBatch and fixture_image(game) and fx.quad) then return nil end
    local ok, batch = pcall(love.graphics.newSpriteBatch, fx.image, 64)
    if not ok or not batch then return nil end
    for k = 1, 20 do batch:add(fx.quad, k * 3, 8) end
    fx.batch = batch
    return batch
end

case("batching", "spritebatch_draw_20_static", "draw", 200, function()
    love.graphics.draw(fx.batch)
end, {
    setup = function(game) fixture_spritebatch(game) end,
    available = function() return fx.batch ~= nil end,
    verts = 120,
    count_draws = true,
    note = "20 sprites, one command; the ceiling for prebaked panels and idle cards",
})

case("batching", "spritebatch_rebuild_20", "draw", 40, function(i)
    local batch, quad = fx.batch, fx.quad
    batch:clear()
    for k = 1, 20 do batch:add(quad, ((i + k * 3) % 64), 8 + k) end
    love.graphics.draw(batch)
end, {
    setup = function(game) fixture_spritebatch(game) end,
    available = function() return fx.batch ~= nil and fx.quad ~= nil end,
    verts = 120,
    count_draws = true,
    note = "clear+add+draw every rep; the moving-card cost, Lua add calls included",
})

-- The batching cases proper. These are the ones the renderer change is judged on, and they
-- are sized so the run count is unambiguous rather than so the timing is precise: 40 quads is
-- one submission if the coalescing works and 40 if it does not, and the "gpu submits" row of
-- the probe says which happened without any interpretation.

case("batching", "batch_quads_60_one_texture", "draw", 30, function(i)
    local img, quad = fx.image, fx.quad
    for k = 1, 60 do love.graphics.draw(img, quad, ((i + k) % 64), (k % 8) * 4) end
end, {
    available = function() return fx.image ~= nil and fx.quad ~= nil end,
    verts = 240,
    count_draws = true,
    note = "60 fan quads, no barrier between them: should be ONE gpu submit",
})

case("batching", "batch_rects_60_untextured", "draw", 30, function(i)
    for k = 1, 60 do
        love.graphics.rectangle("fill", ((i + k) % 64), (k % 8) * 4, 6, 6)
    end
end, {
    verts = 240,
    count_draws = true,
    note = "60 untextured fans; the particle shape, without particles",
})

case("batching", "batch_rects_60_recoloured", "draw", 30, function(i)
    for k = 1, 60 do
        love.graphics.setColor(1, (k % 8) / 8, 0.5, 1)
        love.graphics.rectangle("fill", ((i + k) % 64), (k % 8) * 4, 6, 6)
    end
    love.graphics.setColor(1, 1, 1, 1)
end, {
    verts = 240,
    count_draws = true,
    note = "colour is per vertex, so it must NOT break the run; compare submits above",
})

case("batching", "batch_alternating_20", "draw", 40, function(i)
    local a, b, quad = fx.image, fx.image2, fx.quad
    for k = 1, 20 do
        love.graphics.draw((k % 2 == 0) and a or b, quad, ((i + k * 3) % 64), 8)
    end
end, {
    setup = function()
        if fx.image2 then return end
        local ok, img = pcall(love.graphics.newImage, "resources/textures/1x/chips.png",
            { dpiscale = 1, mipmaps = false })
        if ok and img then fx.image2 = img end
    end,
    available = function() return fx.image ~= nil and fx.image2 ~= nil and fx.quad ~= nil end,
    verts = 80,
    count_draws = true,
    note = "a texture barrier every draw; submits MUST stay at 20 or the merge is unsafe",
})

case("batching", "batch_barrier_scissor", "draw", 30, function(i)
    for k = 1, 20 do
        if k == 10 then
            love.graphics.setScissor(0, 0, 320, 120)
            love.graphics.setScissor()
        end
        love.graphics.rectangle("fill", ((i + k) % 64), 8, 6, 6)
    end
end, {
    verts = 80,
    count_draws = true,
    note = "one state change mid-run; submits should be 3, not 1 and not 20",
})

-- ---------------------------------------------------------------- fill rate
-- If time scales with area these are fill-rate bound and the top screen's shadow overdraw
-- is worth attacking; if they barely differ the cost is per-call and it is not.

case("fillrate", "fill_full_screen", "draw", 40, function()
    love.graphics.rectangle("fill", 0, 0, 320, 240)
end, { verts = 4 })

case("fillrate", "fill_quarter_screen", "draw", 40, function()
    love.graphics.rectangle("fill", 0, 0, 160, 120)
end, { verts = 4, note = "a quarter of the pixels; compare against fill_full_screen" })

case("fillrate", "fill_full_screen_x4", "draw", 20, function()
    for _ = 1, 4 do love.graphics.rectangle("fill", 0, 0, 320, 240) end
end, { verts = 16, note = "four layers of overdraw" })

-- ---------------------------------------------------------------- particles
-- The open question: batching trades 70 draw commands for marshalling 420 vertices.

local Particles = require "particles"
local Backdrop = require "backdrop"

local function fill_particles(n)
    Particles.reset(96)
    for i = 1, n do
        Particles.emit({
            x = (i * 3) % 300, y = (i * 7) % 220, w = 3, h = 3, lifetime = 600,
            colour = { (i % 3) / 3, 0.5, 0.8, 1 },
        })
    end
end

case("particles", "particles_rect_70", "draw", 40, function()
    Particles.draw()
end, {
    setup = function() fill_particles(70); Particles.set_batched(false) end,
    verts = 280,
    count_draws = true,
    note = "one draw command per particle",
})

case("particles", "particles_mesh_70", "draw", 40, function()
    Particles.draw()
end, {
    available = function()
        local _, supported = Particles.batched()
        return supported ~= false
    end,
    setup = function() fill_particles(70); Particles.set_batched(true); Particles.draw() end,
    teardown = function() Particles.set_batched(false); Particles.reset(96) end,
    verts = 420,
    count_draws = true,
    note = "should be one; compare both numbers against particles_rect_70",
})

case("particles", "mesh_setvertices_420", "draw", 60, function()
    if fx.bench_mesh then fx.bench_mesh:setVertices(fx.bench_verts) end
end, {
    setup = function()
        if not love.graphics.newMesh then return end
        local verts = {}
        for i = 1, 420 do verts[i] = { i % 300, i % 200, 0, 0, 1, 1, 1, 1 } end
        local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "dynamic")
        if ok and mesh and type(mesh.setVertices) == "function" then
            fx.bench_mesh, fx.bench_verts = mesh, verts
        end
    end,
    available = function() return fx.bench_mesh ~= nil end,
    note = "the marshalling cost that decides the batching question",
})

case("particles", "mesh_draw_only", "draw", 300, function()
    love.graphics.draw(fx.bench_mesh)
end, {
    setup = function()
        if fx.bench_mesh or not love.graphics.newMesh then return end
        local verts = {}
        for i = 1, 420 do verts[i] = { i % 300, i % 200, 0, 0, 1, 1, 1, 1 } end
        local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "dynamic")
        if ok then fx.bench_mesh, fx.bench_verts = mesh, verts end
    end,
    available = function() return fx.bench_mesh ~= nil end,
    verts = 420,
    count_draws = true,
    note = "one draw command for 420 vertices",
})

-- ---------------------------------------------------------------- lua
-- Calibrates the interpreter so host numbers can be scaled, and sizes the LuaJIT question.

case("lua", "lua_arith_1k", "cpu", 200, function()
    local acc = 0
    for i = 1, 1000 do acc = acc + i * 2 - 1 end
    return acc
end, { note = "per 1000 numeric ops" })

case("lua", "lua_table_rw_1k", "cpu", 200, function()
    local t = fx.scratch
    for i = 1, 1000 do t.x = t.x + i; t.y = t.x end
end, { setup = function() fx.scratch = { x = 0, y = 0 } end, note = "per 1000 field ops" })

case("lua", "lua_call_1k", "cpu", 200, function()
    local f = fx.noop
    for i = 1, 1000 do f(i) end
end, { setup = function() fx.noop = function(a) return a end end, note = "per 1000 calls" })

case("lua", "lua_method_call_1k", "cpu", 200, function()
    local o = fx.obj
    for i = 1, 1000 do o:get(i) end
end, {
    setup = function() fx.obj = { get = function(self, a) return a end } end,
    note = "per 1000 method calls",
})

case("lua", "lua_pcall_1k", "cpu", 200, function()
    local f = fx.noop_p
    for i = 1, 1000 do pcall(f, i) end
end, {
    setup = function() fx.noop_p = function(a) return a end end,
    note = "per 1000; minus lua_call_1k = what each pcall guard in a hot path costs",
})

case("lua", "lua_global_read_1k", "cpu", 200, function()
    local acc = 0
    for i = 1, 1000 do acc = acc + BENCH_GLOBAL.x end
    return acc
end, {
    setup = function() _G.BENCH_GLOBAL = { x = 1 } end,
    teardown = function() _G.BENCH_GLOBAL = nil end,
    note = "global plus field read; what caching G in a local saves per 1000 touches",
})

case("lua", "lua_string_format_100", "cpu", 200, function()
    for i = 1, 100 do local _ = string.format("%d/%d", i, 52) end
end, { note = "per 100; the joker tooltip path was full of these" })

case("lua", "lua_concat_100", "cpu", 200, function()
    for i = 1, 100 do local _ = "Currently X" .. i .. " Mult" end
end, { note = "per 100" })

case("lua", "lua_table_alloc_100", "cpu", 200, function()
    for i = 1, 100 do local _ = { x = i, y = i } end
end, { note = "per 100 allocations" })

case("lua", "math_sin_cos_100", "cpu", 200, function()
    local s = 0
    for i = 1, 100 do s = s + math.sin(i) + math.cos(i) end
    return s
end, { note = "per 100 pairs; the rounded-rect patch removed ~1500 of these a frame" })

case("lua", "math_exp_100", "cpu", 200, function()
    local s = 0
    for i = 1, 100 do s = s + math.exp(-i / 100) end
    return s
end, { note = "per 100; the spring integrator's coefficient path" })

-- The GC step ladder. `Game:update` runs one of these every frame, and the size is the one
-- knob that trades average cost against spike size. A step is not linear in its argument --
-- below some size it is dominated by the fixed cost of entering the collector -- so the whole
-- ladder is measured rather than two points of it.

case("lua", "gc_step_8", "cpu", 200, function()
    collectgarbage("step", 8)
end, { note = "the smallest useful step; per-frame floor" })

case("lua", "gc_step_16", "cpu", 200, function()
    collectgarbage("step", 16)
end)

case("lua", "gc_step_32", "cpu", 200, function()
    collectgarbage("step", 32)
end)

case("lua", "gc_step_48", "cpu", 200, function()
    collectgarbage("step", 48)
end)

case("lua", "gc_step_64", "cpu", 200, function()
    collectgarbage("step", 64)
end)

case("lua", "gc_step_96", "cpu", 200, function()
    collectgarbage("step", 96)
end)

case("lua", "gc_step_160", "cpu", 200, function()
    collectgarbage("step", 160)
end, { note = "the incremental step Game:update runs" })

case("lua", "gc_full_collect", "cpu", 5, function()
    collectgarbage("collect")
end, { unit = "ms", note = "the pause a blocking collect would cost" })

-- ---------------------------------------------------------------- asset loading
-- The hitch a mid-frame atlas load causes, and what a second-core loader would move.

local function timed_load(path)
    local ok, image = pcall(love.graphics.newImage, path, { dpiscale = 1, mipmaps = false })
    if ok and image and image.release then pcall(function() image:release() end) end
    return ok
end

case("load", "newImage_chips_120px", "cpu", 3, function()
    timed_load("resources/textures/1x/chips.png")
end, { unit = "ms" })

case("load", "newImage_joker_70x94", "cpu", 3, function()
    timed_load("resources/textures/1x/Jokers/Jokers1_1.png")
end, { unit = "ms" })

case("load", "newImage_consumable", "cpu", 3, function()
    timed_load("resources/textures/1x/Consumables/000.png")
end, { unit = "ms" })

case("load", "newImage_enhancers_2MiB", "cpu", 2, function()
    timed_load("resources/textures/1x/Enhancers.png")
end, { unit = "ms", note = "720x380, 1024x512 resident" })

case("load", "newImage_blindchips_4MiB", "cpu", 2, function()
    timed_load("resources/textures/1x/BlindChips.png")
end, { unit = "ms", note = "the load draw_blind_chip_sprite used to pay mid-frame" })

--- The biggest single asset in the game and the one the player waits on most often: the menu
--- backdrop is a 1024x1024 sheet of 63 frames, 2.5 MB on the card and 4 MiB resident, loaded
--- on every entry to the home screen and freed on every exit (`game.lua:7360`, `:7378`,
--- `:1697`). Everything else in this group is an atlas the player meets once mid-run; this
--- one is the front door.
case("load", "newImage_menu_backdrop", "cpu", 2, function()
    timed_load("resources/textures/1x/menu.png")
end, { unit = "ms", note = "1024x1024, 63 frames; reloaded every time the menu opens" })

-- ---------------------------------------------------------------- engine
-- The spring integrator runs per node per frame. `moveable.lua` early-outs a settled node,
-- so the gap between these two cases is what that early-out is worth on a real board.

local function make_moveables(n, moving)
    local list = {}
    for i = 1, n do
        local m = Moveable(i % 300, i % 200, 20, 28)
        if moving then
            m.T.x, m.T.y = m.VT.x + 40, m.VT.y + 30
            m.T.scale = 1.2
        end
        list[i] = m
    end
    return list
end

-- Both cases rewrite the target every tick, so the only difference between them is whether
-- the node has anywhere to move. Without that the "moving" set converges during the warmup
-- repetitions and both cases end up timing the early-out.

case("engine", "moveable_update_50_moving", "cpu", 400, function()
    local list = fx.moving
    for i = 1, 50 do
        local m = list[i]
        m.T.x = m.VT.x + 40
        m.T.y = m.VT.y + 30
        m:update(1 / 60)
    end
end, {
    setup = function() fx.moving = make_moveables(50, true) end,
    available = function() return _G.Moveable ~= nil end,
    note = "50 nodes in flight; the spring path with no early-out",
})

case("engine", "moveable_update_50_settled", "cpu", 400, function()
    local list = fx.settled
    for i = 1, 50 do
        local m = list[i]
        m.T.x = m.VT.x
        m.T.y = m.VT.y
        m:update(1 / 60)
    end
end, {
    setup = function() fx.settled = make_moveables(50, false) end,
    available = function() return _G.Moveable ~= nil end,
    note = "50 nodes at rest; the gap to the case above is what the early-out saves",
})

-- Idle collision. `Game:check_collisions` runs every frame whether or not anything is being
-- dragged, and the not-dragging branch used to walk every node to clear a flag that was
-- already clear. This case runs it against a board-sized node list with nothing held, so its
-- cost should be independent of the list length once the release frame has passed.

local function collision_stub(game, n)
    local nodes = make_moveables(n, false)
    for _, node in ipairs(nodes) do node.states.collide.can = true end
    -- Its own collision state, not the running game's: `check_collisions` writes to both the
    -- nudge list and the active flag, and inheriting them through __index would have the
    -- benchmark shoving the player's cards around.
    return setmetatable({
        nodes = nodes,
        dragging = nil,
        _collidables_buf = {},
        _collision_nudged = {},
        _collision_active = false,
    }, { __index = game })
end

case("engine", "collision_idle_50", "cpu", 400, function()
    fx.collide_idle:check_collisions(1 / 60)
end, {
    setup = function(game)
        fx.collide_idle = collision_stub(game, 50)
        -- One dragging frame and one release, so the case times the settled idle state
        -- rather than the transition.
        fx.collide_idle.dragging = fx.collide_idle.nodes[1]
        pcall(function() fx.collide_idle:check_collisions(1 / 60) end)
        fx.collide_idle.dragging = nil
        pcall(function() fx.collide_idle:check_collisions(1 / 60) end)
    end,
    available = function() return _G.Moveable ~= nil and fx.collide_idle ~= nil end,
    note = "nothing held; should not scale with the node count",
})

case("engine", "collision_drag_50", "cpu", 200, function()
    fx.collide_drag:check_collisions(1 / 60)
end, {
    setup = function(game)
        fx.collide_drag = collision_stub(game, 50)
        fx.collide_drag.dragging = fx.collide_drag.nodes[1]
    end,
    available = function() return _G.Moveable ~= nil and fx.collide_drag ~= nil end,
    note = "one node held against 49 collidables; the path that has to stay correct",
})

case("engine", "collision_rect_50", "cpu", 400, function()
    local list = fx.rects
    for i = 1, 50 do list[i]:get_collision_rect() end
end, {
    setup = function() fx.rects = make_moveables(50, false) end,
    available = function() return _G.Moveable ~= nil end,
    note = "allocates a table per call; the form the scan used to use",
})

case("engine", "collision_bounds_50", "cpu", 400, function()
    local list = fx.rects
    for i = 1, 50 do list[i]:get_collision_bounds() end
end, {
    setup = function() fx.rects = fx.rects or make_moveables(50, false) end,
    available = function()
        return _G.Moveable ~= nil and Moveable.get_collision_bounds ~= nil
    end,
    note = "four scalars, no allocation; the gap to the case above is the garbage",
})

-- ---------------------------------------------------------------- composite
-- Whole objects rather than primitives, so the numbers can be laid against a 16.7 ms budget
-- directly. The atlases are warmed in setup and the load lands in the warmup repetitions,
-- not the timed ones.

case("composite", "card_draw_8", "draw", 60, function()
    local cards = fx.cards
    for i = 1, #cards do cards[i]:draw() end
end, {
    setup = function(game)
        if game.warm_atlases then game:warm_atlases({ "centers", "cards_2" }) end
        if not _G.Card then return end
        local cards = {}
        for i = 1, 8 do
            cards[i] = Card((i - 1) * 36, 150, 71, 95,
                { rank = 2 + i, suit = "Spades" }, nil, { face_up = true })
        end
        fx.cards = cards
    end,
    available = function() return fx.cards ~= nil end,
    verts = 320,
    count_draws = true,
    note = "a full hand; the bottom screen's main cost",
})

case("composite", "joker_draw_5", "draw", 60, function()
    local jokers = fx.jokers
    for i = 1, #jokers do jokers[i]:draw() end
end, {
    setup = function(game)
        if not (_G.Joker and _G.JOKER_DEFS) then return end
        local def
        for _, candidate in pairs(JOKER_DEFS) do
            if candidate and candidate.id then def = candidate break end
        end
        if not def then return end
        local jokers = {}
        for i = 1, 5 do
            jokers[i] = Joker((i - 1) * 44, 20, Joker.SPRITE_W, Joker.SPRITE_H, def, {})
        end
        fx.jokers = jokers
    end,
    available = function() return fx.jokers ~= nil end,
    verts = 240,
    count_draws = true,
    note = "five jokers, each loading its own sprite on the first pass",
})

--- The backdrop, which is the one thing in this game whose cost lives entirely on the CPU
--- despite being a graphics feature: the field is evaluated per vertex on the ARM11 because a
--- custom vertex program hangs this GPU, and only the colour resolution happens on the GPU.
--- Grid density is the fidelity knob and this number is what sizes it.
---
--- `verts` is zero deliberately. The backdrop draws from its own vertex buffer through
--- C3D_DrawElements, so it never touches the shared 24576-vertex frame budget this runner
--- exists to protect -- which is also why it can afford thousands of vertices at all.
case("composite", "backdrop_frame", "draw", 30, function()
    Backdrop.draw(320)
end, {
    available = function()
        return Backdrop.is_supported ~= nil and Backdrop.is_supported()
    end,
    own_buffer = true,
    count_draws = true,
    note = "field on the CPU plus one indexed draw; scales linearly with grid density",
})

-- The same call with the New 3DS worker turned off, so the pair prices what moving the field
-- to core 2 is worth. The difference between these two IS the main-thread saving: the drawn
-- output is identical either way, because the worker computes the same numbers into the same
-- buffer and the main thread does the same promotion and the same single indexed draw.
--
-- The worker is put back in teardown whatever happens, including if the case throws: leaving
-- the backdrop synchronous for the rest of the session would silently change every later
-- composite number.
case("composite", "backdrop_frame_sync", "draw", 30, function()
    Backdrop.draw(320)
end, {
    setup = function()
        if Backdrop.set_worker then Backdrop.set_worker(false) end
    end,
    teardown = function()
        if Backdrop.set_worker then Backdrop.set_worker(true) end
    end,
    available = function()
        return Backdrop.is_supported ~= nil and Backdrop.is_supported()
            and Backdrop.set_worker ~= nil and love.graphics.setBackdropWorker ~= nil
    end,
    own_buffer = true,
    note = "the same field, computed on the main thread; minus backdrop_frame = the saving",
})

--- The stereo saving, measured. With the 3D slider up the runtime hands the run loop a
--- three-entry screen list and the whole top screen is built twice a frame; with it parked
--- the gate in `stereo.lua` drops that second pass. This reproduces the call mix a real top
--- screen issues -- counted off `TopUI:draw` on a full board: 28 rounded rects, 86 setColor,
--- 33 text calls, 23 setFont, 16 transforms -- so its result is what the gate saves per frame.
case("composite", "topui_pass_synthetic", "draw", 40, function()
    local font_a, font_b = fixture_font(_G.G)
    for i = 1, 28 do
        love.graphics.setColor(0.2, 0.3, 0.4, 1)
        love.graphics.rectangle("fill", (i * 7) % 300, (i * 5) % 180, 40, 18, 4, 4)
        love.graphics.setColor(1, 1, 1, 1)
    end
    for i = 1, 16 do
        love.graphics.push()
        love.graphics.translate(i, 0)
        love.graphics.pop()
    end
    for i = 1, 33 do
        love.graphics.setColor(1, 1, 1, 1)
        if i % 2 == 0 then
            love.graphics.setFont(font_a or font_b)
            love.graphics.print("1,234", (i * 9) % 280, (i * 6) % 200)
        else
            love.graphics.setFont(font_b or font_a)
            love.graphics.printf("Blind", (i * 9) % 260, (i * 6) % 200, 60, "left")
        end
    end
end, {
    verts = 1500,
    count_draws = true,
    note = "the per-pass cost the stereo gate removes when the slider is down",
})

-- ---------------------------------------------------------------- state changes

case("state", "setLineWidth", "draw", 3000, function(i)
    love.graphics.setLineWidth((i % 2) + 1)
end, { note = "28 of these a frame come from fill-mode rounded rects that never read it" })

case("state", "setBlendMode_switch", "draw", 600, function(i)
    love.graphics.setBlendMode((i % 2 == 0) and "add" or "alpha")
end, {
    teardown = function() love.graphics.setBlendMode("alpha") end,
    note = "edition passes switch this per card",
})

case("state", "setScissor", "draw", 600, function(i)
    love.graphics.setScissor(0, 0, 100 + (i % 8), 100)
    love.graphics.setScissor()
end, { note = "set plus clear" })

-- ---------------------------------------------------------------- audio

case("audio", "sfx_update", "cpu", 600, function()
    if Sfx and Sfx.update then Sfx.update(1 / 60) end
end, {
    available = function() return _G.Sfx ~= nil and _G.Sfx.update ~= nil end,
    note = "runs every frame; crossfade arithmetic plus two ambient pcalls",
})

case("audio", "sfx_play", "cpu", 60, function()
    Sfx.play("chips1", 1, 0.15)
end, {
    available = function() return _G.Sfx ~= nil and _G.Sfx.play ~= nil end,
    note = "pooled voice acquisition; audible, that is the cue firing",
})

-- ---------------------------------------------------------------- threads
-- love.thread compiles on ctr, but the runtime never calls APT_SetAppCpuTimeLimit, so where
-- the OS actually schedules a worker is an open question these two cases settle. Every wait
-- has a timeout so a wedged worker strands a case, never the console.

-- Desktop LÖVE threads start bare and must require the module themselves; LövePotion
-- auto-requires it (luathread.cpp:30), where this is a no-op.
local THREAD_ECHO = [[
require("love.thread")
local req = love.thread.getChannel("bench_req")
local rsp = love.thread.getChannel("bench_rsp")
while true do
    local v = req:demand(5)
    if v == nil or v == "quit" then break end
    rsp:push(v)
end
]]

case("thread", "thread_channel_roundtrip", "cpu", 30, function(i)
    -- A worker that dies mid-case would otherwise cost a full timeout on every remaining
    -- repetition, which at thirty of them reads as a hung console rather than a slow case.
    -- One silent round trip retires the rest.
    if fx.thread_dead then return end
    fx.thread_req:push(i)
    if fx.thread_rsp:demand(0.5) == nil then fx.thread_dead = true end
end, {
    setup = function()
        if fx.thread_echo ~= nil or not (love.thread and love.thread.newThread) then return end
        local ok, thread = pcall(love.thread.newThread, THREAD_ECHO)
        if not ok or not thread then return end
        if not pcall(function() thread:start() end) then return end
        fx.thread_req = love.thread.getChannel("bench_req")
        fx.thread_rsp = love.thread.getChannel("bench_rsp")
        fx.thread_req:push("ping")
        -- No pong inside a second means no worker; report skipped, not a hang.
        if fx.thread_rsp:demand(1) ~= nil then fx.thread_echo = thread end
    end,
    available = function() return fx.thread_echo ~= nil end,
    teardown = function()
        if fx.thread_req then pcall(function() fx.thread_req:push("quit") end) end
    end,
    note = "push+demand round trip; the latency floor of an async atlas loader",
})

--- Bounded on its own, not just by the stop channel. The main thread's priority relative to
--- a std::thread worker is not something this port controls, so a spinner that only ever
--- exits when told to is one missed teardown away from a console that never comes back. The
--- cap is roughly a second of ARM11 work, which outlasts the case either way.
local THREAD_SPIN = [[
require("love.thread")
local stop = love.thread.getChannel("bench_stop")
for _ = 1, 2000 do
    if stop:getCount() > 0 then break end
    local x = 0
    for i = 1, 5000 do x = x + i end
end
]]

case("thread", "lua_arith_1k_busy_thread", "cpu", 200, function()
    local acc = 0
    for i = 1, 1000 do acc = acc + i * 2 - 1 end
    return acc
end, {
    setup = function()
        if fx.thread_spin ~= nil or not (love.thread and love.thread.newThread) then return end
        pcall(function() love.thread.getChannel("bench_stop"):clear() end)
        local ok, thread = pcall(love.thread.newThread, THREAD_SPIN)
        if not ok or not thread then return end
        if pcall(function() thread:start() end) then fx.thread_spin = thread end
    end,
    available = function() return fx.thread_spin ~= nil end,
    teardown = function()
        pcall(function() love.thread.getChannel("bench_stop"):push(1) end)
    end,
    note = "same work as lua_arith_1k beside a spinning thread; the ratio is core contention",
})

-- ---------------------------------------------------------------- fonts
-- There is no rasterizer cache on ctr: every newFont linearAllocs its own copy of the whole
-- glyph sheet, about 513 KB here, even from the same file.

case("font", "newFont", "cpu", 2, function()
    local ok, font = pcall(love.graphics.newFont, "resources/fonts/m6x11plus.ttf", 16)
    if ok and font and font.release then pcall(function() font:release() end) end
end, { unit = "ms", note = "no cache; each call copies the whole glyph sheet" })

-- ---------------------------------------------------------------- storage
-- SD write latency, which is the bulk of what a save costs. Deliberately a scratch file:
-- timing the real save would risk the player's profile for a number a scratch write gives
-- just as well.

case("storage", "write_8kb", "cpu", 3, function()
    love.filesystem.write("benchmark_scratch.bin", fx.payload)
end, {
    setup = function() fx.payload = string.rep("balatro3ds", 820) end,
    available = function()
        return love.filesystem ~= nil and love.filesystem.write ~= nil and fx.payload ~= nil
    end,
    unit = "ms",
    note = "roughly a save's worth of bytes",
})

case("storage", "fs_getInfo", "cpu", 100, function()
    love.filesystem.getInfo("benchmark_scratch.bin")
end, {
    available = function()
        return love.filesystem ~= nil and love.filesystem.getInfo ~= nil
    end,
    note = "one stat against the SD card; the cost of checking a file per frame",
})

case("storage", "read_8kb", "cpu", 5, function()
    love.filesystem.read("benchmark_scratch.bin")
end, {
    available = function() return love.filesystem ~= nil and love.filesystem.read ~= nil end,
    unit = "ms",
})

-- ---------------------------------------------------------------- frame
-- Last, and unlike everything above it: a "frame" case spans real frames instead of looping
-- inside one. It samples the wall time between consecutive bottom-screen draws plus
-- citro3d's own processing/drawing clocks, which is the one measurement that says whether
-- the whole frame is CPU-bound or GPU-bound. If c3d drawing time is a sliver of frame time,
-- the PICA200 is idling and every remaining fight is on the ARM11.

case("frame", "frame_time_60", "frame", 60, function() end, {
    unit = "ms",
    note = "wall time per frame on this screen; c3d rows split CPU submit from GPU execute",
})

--------------------------------------------------------------------------------
-- runner
--------------------------------------------------------------------------------

--- The renderer's counters for the LAST COMPLETED frame.
---
--- Reading counters inside the frame that issued the draws does not work, and the first
--- version of this suite reported "70 draw commands, 0 gpu submits" for the particle case
--- because of it. The renderer queues commands and only submits them on a texture change, at a
--- state barrier or at Present, so a mid-frame read sees the previous flush. The runtime now
--- latches the whole counter set at Present, and everything here is a delta between two
--- finished frames.
---
--- Returns nil on a runtime without the patch (desktop, the headless stub), which is the
--- caller's signal to skip the probe rather than report zeroes.
local function batch_stats()
    if not love.graphics.getBatchStats then return nil end
    local ok, stats = pcall(love.graphics.getBatchStats)
    if not ok or type(stats) ~= "table" then return nil end
    return stats
end

--- Logical draw commands issued so far this frame, from the stock LOVE counter. Still useful
--- as a cross-check: it is incremented at queue time, so unlike the submit count it is correct
--- to read mid-frame.
local function draw_call_count()
    local ok, stats = pcall(love.graphics.getStats)
    if not ok or type(stats) ~= "table" then return nil end
    return tonumber(stats.drawcalls)
end

--- The counters a probe reports, in the order they are written to the report.
local PROBE_FIELDS = {
    { key = "logical", label = "  ^ draw commands", unit = "cmds" },
    { key = "submits", label = "  ^ gpu submits", unit = "cmds" },
    { key = "runs", label = "  ^ batch runs", unit = "cmds" },
    { key = "maxrun", label = "  ^ longest run", unit = "cmds", absolute = true },
    { key = "texbinds", label = "  ^ texture binds", unit = "cmds" },
    { key = "barriers", label = "  ^ state barriers", unit = "cmds" },
    { key = "verts", label = "  ^ vertices", unit = "cmds" },
    { key = "allocs", label = "  ^ heap commands", unit = "cmds" },
}

local function record(c, value, status)
    results[#results + 1] = {
        group = c.group, name = c.name, value = value, unit = c.unit, note = c.note,
        status = status,
    }
end

--- The ceiling this suite crashed into on its first hardware run, and the reason every draw
--- case has to declare `verts`.
---
--- The ctr renderer keeps ONE vertex buffer for the whole frame: `VERTEX_BUFFER_SIZE` is
--- `6 * MAX_OBJECTS` = 24576 vertices (`renderer_ext.hpp:31-33`), `FlushVertices` memcpys
--- each command's vertices into it at a running offset with no bounds check at all
--- (`renderer_ext.cpp:151`), and that offset is reset only by `Present`
--- (`renderer_ext.cpp:222`). The budget is therefore per FRAME and shared by both screens,
--- not per draw call.
---
--- A case that loops three hundred times inside a single frame runs off the end of a
--- linearAlloc'd buffer and into whatever the linear heap placed after it. Nothing faults at
--- the write; the console dies later, wherever the clobbered allocation is next used, which
--- is why the abort landed about twenty cases in rather than at the offending case. The
--- arithmetic was not close: `spritebatch_draw_20_static` asked for 208 * 120 = 24960
--- vertices in one frame, and `mesh_draw_only` for 129600.
---
--- So the runner spends a case's repetitions across as many frames as it takes to stay under
--- budget, which keeps the repetition counts (and so the timing quality) intact. Half the
--- buffer is the budget: the benchmark screen's own panel, the top screen and the
--- draw-command probe all draw into the same frame and none of them are counted here.
--- Two thirds of the buffer rather than half, because merging a run of fans takes them apart
--- into independent triangles and a four-vertex quad becomes six. A case's declared `verts` is
--- its unmerged cost, so the budget has to carry the 1.5x that batching can add on top.
local VERTEX_BUDGET = 8000

--- Progress through the case at `index`, for the cases that span frames. nil between cases.
local step = nil

--- How many repetitions may share one frame without overrunning the vertex buffer. A case
--- with no geometry (state setters, pure Lua) is unbounded.
local function reps_per_frame(c)
    if not c.verts or c.verts <= 0 then return c.reps end
    return math.max(1, math.floor(VERTEX_BUDGET / c.verts))
end

--- Run setup once and settle whether the case can run at all. Returns false when the case
--- was skipped, having already advanced the index.
local function begin_case(game, c)
    step = { done = 0, elapsed = 0, failed = false, stage = "warm" }
    if c.setup then pcall(c.setup, game) end
    if c.available then
        local ok, yes = pcall(c.available, game)
        if not ok or not yes then
            if c.teardown then pcall(c.teardown, game) end
            record(c, nil, "skipped")
            step = nil
            index = index + 1
            return false
        end
    end
    return true
end

--- What one repetition of the case actually cost the renderer, as a delta between two
--- finished frames.
---
--- Three frames are needed and the order matters. The counters can only be read for a frame
--- that has already presented, so:
---
---   frame A  draw the benchmark UI and nothing else.
---   frame B  read A's counters as the baseline, then run the case once.
---   frame C  read B's counters; B minus A is the case.
---
--- The benchmark's own panel draws identically in A and B, so it cancels. A single-frame
--- before/after read cannot work here at all: at the moment the case finishes, its commands
--- are still queued and the counter still describes the previous flush.
---
--- `maxrun` is reported absolutely rather than as a delta -- it is a high-water mark, not a
--- total, and the difference of two high-water marks means nothing.
local function record_probe(c, base, after)
    for _, field in ipairs(PROBE_FIELDS) do
        local a, b = base[field.key], after[field.key]
        if type(a) == "number" and type(b) == "number" then
            local value = field.absolute and b or (b - a)
            if value ~= 0 or field.key == "logical" or field.key == "submits" then
                record({ group = c.group, name = field.label, unit = field.unit }, value)
            end
        end
    end
end

--- Record the timing. Deliberately separate from releasing the index, and deliberately before
--- the probe: results are written in call order, so a case whose detail rows were recorded
--- first had every one of them printed under the name of the case above it. Which is how the
--- first report read "particles_rect_70 ... 1 draw command".
local function record_timing(c)
    local value = nil
    if not step.failed and step.done > 0 then
        value = (step.elapsed / step.done) * (c.unit == "ms" and 1000 or 1000000)
    end
    record(c, value)
end

--- Release the index and put back whatever the case set up.
local function end_case(game, c)
    if c.teardown then pcall(c.teardown, game) end
    step = nil
    index = index + 1
end

--- Time `n` repetitions and fold them into the running total.
local function time_chunk(c, n)
    local from = step.done + 1
    local t0 = now()
    local ok = pcall(function() for i = from, from + n - 1 do c.run(i) end end)
    step.elapsed = step.elapsed + (now() - t0)
    if ok then step.done = step.done + n else step.failed = true end
end

--- A CPU case submits no geometry, so it still runs start to finish inside one frame.
local function run_cpu_case(game, c)
    if not begin_case(game, c) then return end
    -- The "ms" cases are deliberately not warmed: at two or three repetitions the cold
    -- first call is the number being asked for, not noise to be discarded.
    if c.unit ~= "ms" then
        if not pcall(function() for i = 1, math.min(c.reps, 8) do c.run(i) end end) then
            step.failed = true
        end
    end
    if not step.failed then time_chunk(c, c.reps) end
    record_timing(c)
    end_case(game, c)
end

--- A draw case runs a warmup frame, then as many timed chunks as the vertex budget allows,
--- then the draw-command probe -- one stage per frame, holding the index until it is done.
local function step_draw_case(game, c)
    if not step and not begin_case(game, c) then return end
    local per_frame = reps_per_frame(c)

    if step.stage == "warm" then
        local warm = math.min(c.reps, 8, per_frame)
        if not pcall(function() for i = 1, warm do c.run(i) end end) then step.failed = true end
        step.stage = step.failed and "done" or "time"
        return
    end

    if step.stage == "time" then
        time_chunk(c, math.min(per_frame, c.reps - step.done))
        if step.failed or step.done >= c.reps then
            record_timing(c)
            step.stage = (c.count_draws and not step.failed and batch_stats()) and "probe_idle"
                or "done"
        end
        return
    end

    -- The three probe frames. See record_probe for why it cannot be done in one.
    if step.stage == "probe_idle" then
        step.stage = "probe_run"
        return
    end

    if step.stage == "probe_run" then
        step.probe_base = batch_stats()
        if not pcall(c.run, 1) then step.probe_base = nil end
        step.stage = "probe_read"
        return
    end

    if step.stage == "probe_read" then
        local after = batch_stats()
        if step.probe_base and after then record_probe(c, step.probe_base, after) end
        step.stage = "done"
        return
    end

    end_case(game, c)
end

--- Step a "frame" case: one sample per real frame instead of a loop inside one. The first
--- visit only takes a baseline timestamp; each later visit adds the wall dt since the last
--- and the citro3d clocks getStats captured at the previous present. When `reps` samples
--- are in, the case records its rows and releases the index.
local function step_frame_case(game, c)
    local s = fx.frame_probe
    if not s then
        fx.frame_probe = { t = now(), n = 0, dt = 0, cpu = 0, gpu = 0, c3d_n = 0 }
        return
    end
    local t = now()
    s.dt, s.t, s.n = s.dt + (t - s.t), t, s.n + 1
    local ok, stats = pcall(love.graphics.getStats)
    if ok and type(stats) == "table" and stats.cputime then
        s.cpu = s.cpu + stats.cputime
        s.gpu = s.gpu + (stats.gputime or 0)
        s.c3d_n = s.c3d_n + 1
    end
    if s.n < c.reps then return end
    record(c, (s.dt / s.n) * 1000)
    if s.c3d_n > 0 then
        -- Already milliseconds: these come from C3D_GetProcessingTime/C3D_GetDrawingTime
        -- (`renderer_ext.cpp:227-228`), which citro3d returns in ms, unlike
        -- love.timer.getTime's seconds. Scaling them cost a first reading of "6469 ms of
        -- GPU time in a 16.7 ms frame".
        record({ group = c.group, name = "  ^ c3d processing", unit = "ms" }, s.cpu / s.c3d_n)
        record({ group = c.group, name = "  ^ c3d drawing", unit = "ms" }, s.gpu / s.c3d_n)
    end
    fx.frame_probe = nil
    index = index + 1
end

--------------------------------------------------------------------------------
-- environment
--------------------------------------------------------------------------------

local function boolstr(v)
    if v == nil then return "?" end
    return v and "yes" or "no"
end

--- Facts that make the numbers interpretable, plus a few that are themselves worth knowing
--- -- notably the bottom-screen width, which is the regression the screen-id patch fixes and
--- which only misreports while stereo is off.
local function environment_lines(game)
    local L = {}
    local function add(k, v) L[#L + 1] = string.format("%-24s %s", k, tostring(v)) end

    add("console", love._console or "?")
    add("hardware", boolstr(Console.is_hardware()))
    add("new 3ds", boolstr(Console.is_new_3ds()))
    add("cpu cores", love.system and love.system.getProcessorCount
        and love.system.getProcessorCount() or "?")

    local stereo_on = love.graphics.get3D and love.graphics.get3D()
    add("stereo on", boolstr(stereo_on))
    -- "yes" here means the gate turned stereo off, measured getWidth("bottom") as 400 and
    -- put it back for the rest of the process: the runtime is missing the screen-lookup
    -- patch, and the top screen is being drawn twice a frame for nothing.
    local ok_stereo, Stereo = pcall(require, "stereo")
    if ok_stereo and Stereo.is_disabled then
        add("stereo gate gave up", boolstr(Stereo.is_disabled()))
    end
    add("3d slider", love.graphics.getDepth and string.format("%.2f", love.graphics.getDepth()) or "?")
    add("screens", table.concat(love.graphics.getScreens and love.graphics.getScreens() or {}, ","))
    -- 320 is correct. 400 means the runtime is indexing the screen list by id and the
    -- screen-lookup patch is missing from this build.
    add("bottom width", love.graphics.getWidth and love.graphics.getWidth("bottom") or "?")

    -- PUC Lua 5.1 against LuaJIT is a 2-10x interpreter gap; which one this build carries
    -- is the denominator under every lua_* number above.
    add("lua", _VERSION .. (rawget(_G, "jit") and " (LuaJIT)" or " (PUC)"))
    add("love.thread", boolstr(love.thread ~= nil))
    add("love.image", boolstr(love.image ~= nil))
    add("newSpriteBatch", boolstr(love.graphics.newSpriteBatch ~= nil))
    add("newTextBatch", boolstr(love.graphics.newTextBatch ~= nil))

    -- Whether CPU-side image decode exists at all on this build. If it does, a worker
    -- thread can decode while the main thread draws, and only the GPU upload stays on the
    -- frame; if it does not, an async loader has nothing to move.
    if love.image and love.image.newImageData then
        local ok, data = pcall(love.image.newImageData, "resources/textures/1x/Consumables/000.png")
        add("newImageData decode", ok and data and "yes" or "no")
        if ok and data and data.release then pcall(function() data:release() end) end
    else
        add("newImageData decode", "no module")
    end

    local mesh_ok, mesh = false, nil
    if love.graphics.newMesh then
        mesh_ok, mesh = pcall(love.graphics.newMesh,
            { { 0, 0, 0, 0, 1, 1, 1, 1 }, { 1, 0, 0, 0, 1, 1, 1, 1 }, { 1, 1, 0, 0, 1, 1, 1, 1 } },
            "triangles", "dynamic")
    end
    add("newMesh", boolstr(mesh_ok and mesh ~= nil))
    add("Mesh:setVertices", boolstr(mesh_ok and mesh and type(mesh.setVertices) == "function"))
    add("Mesh:setDrawRange", boolstr(mesh_ok and mesh and type(mesh.setDrawRange) == "function"))
    if mesh_ok and mesh and mesh.release then pcall(function() mesh:release() end) end

    local stats_ok, stats = pcall(love.graphics.getStats)
    if stats_ok and type(stats) == "table" then
        add("texture memory", string.format("%.2f MiB", (stats.texturememory or 0) / 1048576))
        add("draw calls (menu)", stats.drawcalls or "?")
        -- Deliberately not `stats.drawcallsbatched`: that counts commands as the flush
        -- consumes them, which is the same number as drawcalls whether or not they were
        -- merged. The renderer's own counter is the one that says how many C3D draws happened.
        local batch = batch_stats()
        if batch then
            add("gpu submits (last frame)", batch.submits or "?")
            add("logical draws (last frame)", batch.logical or "?")
            add("longest run (last frame)", batch.maxrun or "?")
            add("state barriers (last frame)", batch.barriers or "?")
            add("heap commands (last frame)", batch.allocs or "?")
            add("vertex high water", string.format("%s / %s",
                tostring(batch.vhigh), tostring(batch.vcapacity)))
            -- Non-zero here means geometry was DROPPED rather than written past the end of the
            -- frame's vertex buffer. It is the safe failure, but it is still a failure.
            add("prevented overflows", batch.overflows or 0)
        end
        -- citro3d reports these in milliseconds already; see step_frame_case.
        if stats.cputime then add("cputime (menu)", string.format("%.3f ms", stats.cputime)) end
        if stats.gputime then add("gputime (menu)", string.format("%.3f ms", stats.gputime)) end
    end
    return L
end

--------------------------------------------------------------------------------
-- report
--------------------------------------------------------------------------------

--- Which build produced this file.
---
--- A before/after pair of reports is worth nothing if the two cannot be told apart, and the
--- fields that silently change every number below are exactly the ones nobody writes down: the
--- commit, whether the runtime itself was built optimised, which set of runtime patches it
--- carries, and whether the two A/B switches this pass added were on. `format` is bumped
--- whenever a case is renamed or its meaning changes, so an old report cannot be diffed
--- against a new one by accident.
local REPORT_FORMAT = 2

local function build_lines(game)
    local L = {}
    local function add(k, v) L[#L + 1] = string.format("%-24s %s", k, tostring(v)) end

    add("report format", REPORT_FORMAT)

    local ok_flags, Flags = pcall(require, "build_flags")
    if ok_flags and type(Flags) == "table" then
        add("game commit", Flags.commit or "(unpackaged tree)")
        add("build target", Flags.target or "?")
        add("build stamp", Flags.timestamp or (Flags.release and "release" or "-"))
    end

    local info = nil
    if love.graphics.getRuntimeInfo then
        local ok, got = pcall(love.graphics.getRuntimeInfo)
        if ok and type(got) == "table" then info = got end
    end

    if info then
        add("runtime patches", info.patch_version or "?")
        add("runtime build", string.format("%s %s", tostring(info.runtime_build),
            tostring(info.runtime_opt)))
        add("runtime compiled", info.runtime_compiled or "?")
        add("apt cpu time limit", tostring(info.cpu_time_limit) .. "%")
    else
        -- No binding means the runtime predates this optimisation pass, so nothing below
        -- that depends on it is comparable with a report that has it.
        add("runtime patches", "ABSENT (pre-optimisation runtime)")
    end

    local ok_flags, PerfFlags = pcall(require, "perf_flags")
    if ok_flags and type(PerfFlags) == "table" and PerfFlags.state then
        local flags = PerfFlags.state()
        add("perf flags from", flags.source or "?")
    end

    local stats = batch_stats()
    if stats then
        local MODES = { [0] = "off", [1] = "on (expand to triangles)", [2] = "on (indexed)" }
        add("renderer batching", MODES[stats.batching] or tostring(stats.batching))
        add("vertex buffer", string.format("%d verts", stats.vcapacity or 0))
        add("index buffer", string.format("%d indices", stats.icapacity or 0))
    end

    local ok_backdrop, Backdrop = pcall(require, "backdrop")
    if ok_backdrop and type(Backdrop) == "table" and Backdrop.worker_status then
        add("backdrop worker", Backdrop.worker_status())
    end

    return L
end

local function build_report(game)
    local out = {}
    out[#out + 1] = "Balatro3DS benchmark"
    out[#out + 1] = string.rep("=", 52)
    out[#out + 1] = ""
    out[#out + 1] = "-- build --"
    for _, line in ipairs(build_lines(game)) do out[#out + 1] = line end
    out[#out + 1] = ""
    out[#out + 1] = "-- environment --"
    for _, line in ipairs(environment_lines(game)) do out[#out + 1] = line end
    out[#out + 1] = ""

    local group = nil
    for _, r in ipairs(results) do
        if r.group ~= group then
            group = r.group
            out[#out + 1] = ""
            out[#out + 1] = "-- " .. group .. " --"
        end
        local value = r.value and string.format(
                r.unit == "cmds" and "%10.0f %s" or "%10.3f %s", r.value, r.unit)
            or (r.status == "skipped" and "    skipped" or "     failed")
        out[#out + 1] = string.format("%-26s %s", r.name, value)
        if r.note then out[#out + 1] = string.format("%-26s   (%s)", "", r.note) end
    end

    out[#out + 1] = ""
    out[#out + 1] = string.rep("=", 52)
    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function Benchmark.start(game)
    running, finished = true, false
    index, results, page = 1, {}, 1
    report_text, write_status = nil, nil
    fx = {}
    fixture_image(game)
end

--- The frame vertex budget and every case's schedule against it, for the harness test that
--- proves no case can overrun the buffer. Returns the budget and a list of
--- `{ name, phase, verts, chunk, count_draws }`, where `chunk` is how many repetitions of
--- that case may share one frame.
function Benchmark.vertex_budget()
    local list = {}
    for i, c in ipairs(CASES) do
        list[i] = {
            name = c.name, phase = c.phase, verts = c.verts,
            chunk = reps_per_frame(c), count_draws = c.count_draws,
            own_buffer = c.own_buffer,
        }
    end
    return VERTEX_BUDGET, list
end

function Benchmark.is_running() return running end
function Benchmark.is_finished() return finished end
function Benchmark.results() return results end
function Benchmark.report() return report_text end

function Benchmark.progress()
    return math.min(index - 1, #CASES), #CASES
end

function Benchmark.current_name()
    local c = CASES[index]
    return c and (c.group .. " / " .. c.name) or "done"
end

--- Put back everything the suite disturbed. The composite cases warm `centers` and
--- `cards_2` -- 4 MiB between them -- and leaving those resident would undo the free that
--- returning to the menu just did; the storage cases leave a scratch file on the card.
local function cleanup(game)
    Particles.set_batched(false)
    Particles.reset(96)
    if love.graphics and love.graphics.setBlendMode then
        pcall(love.graphics.setBlendMode, "alpha")
    end
    if love.graphics and love.graphics.setColor then
        pcall(love.graphics.setColor, 1, 1, 1, 1)
    end
    if game and game.unload_asset_atlas then
        game:unload_asset_atlas("centers")
        game:unload_asset_atlas("cards_2")
    end
    if love.filesystem and love.filesystem.remove then
        pcall(love.filesystem.remove, "benchmark_scratch.bin")
    end
    if fx.bench_mesh and fx.bench_mesh.release then
        pcall(function() fx.bench_mesh:release() end)
    end
    for _, name in ipairs({ "image2", "batch", "textbatch" }) do
        local obj = fx[name]
        if obj and obj.release then pcall(function() obj:release() end) end
    end
    -- Belt and braces for the workers: their demand timeouts already bound their lives, but
    -- a run aborted between setup and teardown should not leave one spinning for seconds.
    if love.thread and love.thread.getChannel then
        pcall(function() love.thread.getChannel("bench_req"):push("quit") end)
        pcall(function() love.thread.getChannel("bench_stop"):push(1) end)
    end
    _G.BENCH_GLOBAL = nil
    fx = {}
end

local function finish(game)
    running, finished = false, true
    report_text = build_report(game)
    cleanup(game)
    if love.filesystem and love.filesystem.write then
        local ok, err = pcall(love.filesystem.write, Benchmark.REPORT_FILE, report_text)
        write_status = ok and ("wrote " .. Benchmark.REPORT_FILE) or ("write failed: " .. tostring(err))
    else
        write_status = "no filesystem"
    end
end

function Benchmark.write_status() return write_status end

--- Run the next case if it is a CPU case. One case per frame, so the run never blocks long
--- enough to read as a hang.
function Benchmark.update(game, dt)
    stepped_this_frame = false
    if not running then return end
    local c = CASES[index]
    if not c then finish(game) return end
    if c.phase == "cpu" then
        run_cpu_case(game, c)
        stepped_this_frame = true
    end
end

--- Run the next case if it is a draw case. Must be called from inside `love.draw`, on the
--- bottom screen only: graphics calls outside a frame build commands nobody submits, and
--- running once per screen would time the case twice.
function Benchmark.draw_step(game)
    if not running or stepped_this_frame then return end
    local c = CASES[index]
    if not c then finish(game) return end
    if c.phase == "draw" then
        step_draw_case(game, c)
        stepped_this_frame = true
    elseif c.phase == "frame" then
        step_frame_case(game, c)
        stepped_this_frame = true
    end
end

--- Frames the run needs beyond one per case. A "frame" case holds the index for a baseline
--- frame plus `reps` sampled ones; a draw case holds it for a warmup frame, one frame per
--- timed chunk and a final frame that records. The harness test uses this to prove that no
--- case is stranded and that no frame runs two cases.
---
--- This is also the honest cost of the vertex budget: a suite that used to be one frame per
--- case is now however many frames the geometry needs, which at 60 Hz is still a couple of
--- seconds. Cheaper than a prefetch abort.
function Benchmark.extra_frames()
    local extra = 0
    for _, c in ipairs(CASES) do
        if c.phase == "frame" then
            extra = extra + c.reps
        elseif c.phase == "draw" then
            -- warmup + ceil(reps / per_frame) timed chunks + the recording frame, plus the
            -- three probe frames when the case counts draws, minus the one frame every case
            -- is already allotted.
            local per_frame = c.verts > 0
                and math.max(1, math.floor(VERTEX_BUDGET / c.verts)) or c.reps
            extra = extra + 1 + math.ceil(c.reps / per_frame) + 1 - 1
            if c.count_draws then extra = extra + 3 end
        end
    end
    return extra
end

--------------------------------------------------------------------------------
-- results paging
--------------------------------------------------------------------------------

Benchmark.LINES_PER_PAGE = 13

function Benchmark.lines(game)
    if not report_text then return {} end
    local lines = {}
    for line in (report_text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

function Benchmark.page_count(game)
    local n = #Benchmark.lines(game)
    return math.max(1, math.ceil(n / Benchmark.LINES_PER_PAGE))
end

function Benchmark.page() return page end

function Benchmark.turn_page(game, delta)
    local count = Benchmark.page_count(game)
    page = math.max(1, math.min(count, page + delta))
    return page
end

return Benchmark

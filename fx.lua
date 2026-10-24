--- Shader-replacement effects.
---
--- The reference game draws editions (foil/holo/polychrome), the gold seal shine and the
--- score flames with GLSL fragment shaders. The PICA200 has no programmable fragment
--- stage, and the 3DS runtime exposes exactly one texture-combiner configuration —
--- texel x vertex colour (`platform/ctr/include/utilities/driver/vertex_ext.hpp` in
--- LövePotion) — plus framebuffer blend modes. This module re-expresses those shaders
--- with the two levers that do exist:
---
---  * Per-vertex colours on a `love.graphics.newMesh` strip, Gouraud-interpolated by
---    the GPU. Texture filtering is forced NEAREST on the 3DS, so a gradient texture
---    would band; vertex interpolation does not go through the sampler and stays smooth.
---  * A second additive pass of the same texture. The runtime's `add` blend multiplies
---    source by its own alpha, so the art's transparent rounded corners mask the
---    overlay to the card silhouette with no stencil (stencil is unreachable on ctr).
---
--- Mesh texcoords on the ctr backend are only V-flipped, never rescaled, and sample the
--- physical (power-of-two padded) texture. `Image:getDimensions()` reports the *source*
--- size on hardware — a t3x carries the padded size in `width_log2`/`height_log2` and the
--- source size in its subtexture header, and LövePotion reads the latter
--- (`t3xhandler.cpp:51`) — so mesh UVs must divide by the padded size, not the reported
--- one. Quads get that rescale for free (`texture_ext.cpp:291`); meshes do not.
---
--- `Mesh:setVertices` is a Balatro3DS runtime binding (dev/patch_lovepotion.py) —
--- upstream ctr never implemented it. Every animated pass rewrites one cached mesh per
--- vertex count instead of allocating a fresh Mesh; the vertex tables are pooled too,
--- so the steady state of a pass is allocation-free on the Lua side.

local Console = require("console")

local Fx = {}

--- Animation clock, safe under the headless stub.
---@return number
function Fx.time()
    return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

--------------------------------------------------------------------------------
-- Colour math
--------------------------------------------------------------------------------

--- Hue (0..1, wraps) to fully saturated RGB. HSV with s = v = 1.
---@param h number
---@return number r, number g, number b
function Fx.hue_rgb(h)
    h = h % 1
    local x = 1 - math.abs((h * 6) % 2 - 1)
    if h < 1 / 6 then return 1, x, 0 end
    if h < 2 / 6 then return x, 1, 0 end
    if h < 3 / 6 then return 0, 1, x end
    if h < 4 / 6 then return 0, x, 1 end
    if h < 5 / 6 then return x, 0, 1 end
    return 1, 0, x
end

--- Smoothstep band profile: 1 at `center`, easing to 0 at `center +- half_width`.
---@param x number
---@param center number
---@param half_width number
---@return number
function Fx.band(x, center, half_width)
    local d = math.abs(x - center)
    if d >= half_width then return 0 end
    local k = 1 - d / half_width
    return k * k * (3 - 2 * k)
end

--------------------------------------------------------------------------------
-- The interference field
--
-- Holo and polychrome both rotate hue through the same three-part field
-- (`holo.fs:105-118`, `polychrome.fs:110-123`) at different scales: 250 for holo's
-- fine grain, 50 for polychrome's large slow blobs.
--
-- Every card on screen samples it at the same instant, so it is built once per frame
-- into a shared table rather than per card. That is what makes the dense grid
-- affordable on an Old 3DS: the per-card cost drops to a table read plus a hue lookup,
-- within ~1 us of the flat version it replaces. Per-card variety comes from a scalar
-- hue offset instead of the reference's per-card seed, which is free.
--
-- The field's own divisors are 143/99/53 seconds, so it drifts far slower than the
-- frame rate; rebuilding at FIELD_HZ rather than every frame is invisible and takes
-- the shared cost to a fifth.
--------------------------------------------------------------------------------

-- Grid resolution for field-driven passes. 6 gives 49 field samples and a 94-vertex
-- strip, well inside the runtime's 24576-per-frame budget even with a full board.
--
-- Vertex count is where the real cost sits, and it is not the GPU's: `setVertices`
-- reads every vertex across the Lua/C boundary one component at a time (nine rawgets
-- and six number checks each, mirroring `wrap_graphics.cpp:1594-1641`), every animated
-- pass, every frame. An Old 3DS at 268 MHz drops to 4, which
-- is 46 vertices — half the crossings for a grid that is still finer than the ~70 px
-- cell it shades at 240p.
local FIELD_GRID_FULL = 6
local FIELD_GRID_REDUCED = 4
local FIELD_HZ = 15

--- Grid resolution for this console. Probed per call rather than resolved at load: the
--- probe caches internally, and tests swap `love` out and call `Console.reset_cache()`.
---@return integer
local function field_grid()
    return Console.is_new_3ds() and FIELD_GRID_FULL or FIELD_GRID_REDUCED
end

-- The reference feeds the field `G.TIMERS.REAL` directly (`holo.fs:104`), which with
-- those divisors is a crawl measured in minutes. On a handheld a card is on screen for
-- seconds at a time, so the clock runs faster to get the same sense of motion within
-- the time a card is actually looked at.
local FIELD_DRIFT_RATE = 6

local FIELD_SCALES = { holo = 250, polychrome = 50 }
local fields = {}

--- Rebuild one field table for time `t`. The six drift offsets are per-frame, not
--- per-vertex, so they are hoisted out of the loop.
local function build_field(values, t, scale, grid)
    local sin, cos, sqrt = math.sin, math.cos, math.sqrt
    local a1, a2 = 50 * sin(-t / 143.6340), 50 * cos(-t / 99.4324)
    local b1, b2 = 50 * cos(t / 53.1532), 50 * cos(t / 61.4532)
    local c1, c2 = 50 * sin(-t / 87.53218), 50 * sin(-t / 49.0000)
    local n = 0
    for j = 0, grid do
        local y = (j / grid - 0.5) * scale
        for i = 0, grid do
            local x = (i / grid - 0.5) * scale
            local ax, ay = x + a1, y + a2
            local bx, by = x + b1, y + b2
            local cx, cy = x + c1, y + c2
            n = n + 1
            values[n] = (1 + (cos(sqrt(ax * ax + ay * ay) / 19.483)
                + sin(sqrt(bx * bx + by * by) / 33.155) * cos(by / 15.73)
                + cos(sqrt(cx * cx + cy * cy) / 27.193) * sin(cx / 21.92))) / 2
        end
    end
end

--- The shared field table for `kind` at time `t`, rebuilt at most FIELD_HZ times a
--- second. Exposed for tests.
---@param kind "holo"|"polychrome"
---@param t number
---@return table values (grid+1)^2 samples, row-major
function Fx.field_table(kind, t)
    local f = fields[kind]
    if not f then
        f = { values = {}, built_at = nil, grid = nil }
        fields[kind] = f
    end
    -- `t < built_at` catches a clock that went backwards (a test, or a reset). A changed
    -- grid forces a rebuild too, since the sample count and spacing both depend on it.
    local grid = field_grid()
    if f.built_at == nil or f.grid ~= grid
        or t - f.built_at >= 1 / FIELD_HZ or t < f.built_at then
        build_field(f.values, t * FIELD_DRIFT_RATE, FIELD_SCALES[kind], grid)
        f.built_at = t
        f.grid = grid
    end
    return f.values
end

--------------------------------------------------------------------------------
-- Edition vertex colours
--
-- Each edition is a base pass (multiplies the art) and an additive pass (light the
-- card gives off). The additive pass samples either the art again or, where the
-- edition has a spatial signature the vertex grid cannot express, a baked pattern
-- sheet whose alpha carries the structure (see dev/bake_edition_patterns.py).
-- u/v are 0..1 across the cell.
--------------------------------------------------------------------------------

-- Foil is an *overlay*, not a repaint. The reference draws the card normally through
-- `dissolve` and only then draws `foil` over the top (`card.lua:4459-4464`), and
-- `foil.fs:129` caps that overlay's alpha at `0.3*tex.a + 0.9*min(0.5, maxfac*0.1)` --
-- so off the ridges the foil layer is 30% opaque and nothing more. Compositing the
-- reference's own overlay colour (`tex.rgb - delta` on red and green, blue untouched,
-- `foil.fs:126-128`) at that 30% over a mid-tone card lands on roughly a
-- (0.72, 0.70, 1.00) multiply of the art.
--
-- This port has no second layer to spare -- the base pass *is* the card draw -- so the
-- composite is baked into the multiply instead. Using the raw shader colour here would
-- apply an overlay meant for 30% at 100%, which is what made foil read as a solid blue
-- chip rather than as a sheen over readable art.
local FOIL_R, FOIL_G, FOIL_B = 0.70, 0.68, 1.00

--- Foil base: a cold multiply at the strength the reference's 30% overlay works out to.
--- Green sits a hair under red because `delta` is subtracted from both while the art's
--- own red usually starts higher.
function Fx.foil_base_rgba(u, v, t)
    return FOIL_R + 0.06 * v, FOIL_G + 0.06 * v, FOIL_B, 1
end

--- Foil add: the ring sheet, lit by a broad sweep so different arcs catch the light.
---
--- `maxfac` is zero across almost all of the card and spikes on the interference ridges
--- (`foil.fs:107-116`), so the reference's additive term is *absent* between sweeps
--- rather than merely dim. The old 0.35 floor lit every ring on the sheet continuously,
--- which read as a bright blue lattice pasted over the art; the floor here is just
--- enough to keep the rings from disappearing entirely on a resting card.
function Fx.foil_add_rgba(u, v, t)
    local pos = (t * 0.5) % 1.9 - 0.35
    return 0.55, 0.78, 1.0, 0.06 + 0.54 * Fx.band(u * 0.72 + v * 0.45, pos, 0.35)
end

-- Holo is the +Mult edition and it reads red. That is not a stylistic choice made here:
-- `holo.fs:131` blends the hue-rotated copy over the art by `delta`, and
-- `holo.fs:123-125` puts `delta` at `0.2 + 0.3*(high-low) + 0.1*high` -- between 0.2 and
-- 0.6, typically around a third. Two thirds of what the player sees is the card's own
-- art; the rotating hue is a shimmer laid over it, tinted pink-violet by the
-- `vec4(0.9, 0.8, 1.2)` multiply on the way in.
--
-- Driving a full-circle hue at the strength this port used made holo read as a rainbow,
-- which is polychrome's signature, not holo's. Two things fix it: the additive pass
-- carries roughly the reference's third rather than dominating, and its hue is confined
-- to the red-through-magenta arc instead of sweeping the whole wheel.
local HOLO_HUE_CENTER = 0.93
local HOLO_HUE_SWING = 0.09

--- Holo base: magenta-leaning lift. `holo.fs:127-129` raises lightness (`hsl.z*0.6+0.4`)
--- and multiplies the result by (0.9, 0.8, 1.2), which skews it pink-violet; that skew
--- is the whole reason holo and foil do not look alike. Kept shallow because the
--- reference only ever blends it in at `delta`.
function Fx.holo_base_rgba(u, v, t)
    return 1.00, 0.86 + 0.06 * v, 0.97, 1
end

--- Holo add: the lattice sheet in a hue taken from the shared field, so the prisms shift
--- colour in place rather than sliding a ramp across the card. The field drives the hue
--- across the red/magenta arc only, and the alpha stays near the reference's `delta`.
---@param field table shared field samples
---@param n number 1-based vertex index into `field`
function Fx.holo_add_rgba(field, n, u, v, t, seed)
    local swing = (field[n] + seed) % 1
    local r, g, b = Fx.hue_rgb(HOLO_HUE_CENTER + HOLO_HUE_SWING * (2 * swing - 1))
    return r, g, b, 0.20 + 0.10 * math.sin(t * 1.4 + u * 3.0)
end

-- How dark the polychrome sweep may push the art. `polychrome.fs:130` replaces hue
-- outright and floors saturation at 0.6; a multiply cannot replace hue, but a low floor
-- gets the same saturated result while keeping the art's own luminance.
local POLY_FLOOR = 0.32

--- Polychrome base: the field's hue multiplying the art.
function Fx.polychrome_base_rgba(field, n, u, v, t, seed)
    local r, g, b = Fx.hue_rgb(field[n] + 0.15 + seed)
    return POLY_FLOOR + (1 - POLY_FLOOR) * r,
        POLY_FLOOR + (1 - POLY_FLOOR) * g,
        POLY_FLOOR + (1 - POLY_FLOOR) * b, 1
end

--- Polychrome add: the same hue as a glow, so bright art shimmers rather than just
--- being tinted.
function Fx.polychrome_add_rgba(field, n, u, v, t, seed)
    local r, g, b = Fx.hue_rgb(field[n] + 0.15 + seed)
    return r, g, b, 0.20
end

--- Baked pattern sheets. Geometry is declared, never derived from image dimensions:
--- on hardware a t3x reports its source size while the GPU texture is power-of-two
--- padded, so any column count computed by division is wrong on-device.
--- Written by dev/bake_edition_patterns.py; keep the two in step.
local PATTERNS = {
    foil = {
        atlas = "edition_foil",
        phases = 6,
        cols = 3,
        variants = {
            card  = { x = 0, y = 0,   w = 72, h = 95 },
            joker = { x = 0, y = 190, w = 70, h = 94 },
        },
    },
    holo = {
        atlas = "edition_holo",
        phases = 1,
        cols = 1,
        variants = {
            card  = { x = 0, y = 0,  w = 72, h = 95 },
            joker = { x = 0, y = 95, w = 70, h = 94 },
        },
    },
}

local EDITION_PASSES = {
    foil = {
        base = Fx.foil_base_rgba,
        add = Fx.foil_add_rgba,
        pattern = PATTERNS.foil,
    },
    holo = {
        base = Fx.holo_base_rgba,
        add = Fx.holo_add_rgba,
        add_field = "holo",
        pattern = PATTERNS.holo,
    },
    polychrome = {
        base = Fx.polychrome_base_rgba,
        base_field = "polychrome",
        add = Fx.polychrome_add_rgba,
        add_field = "polychrome",
    },
}

--------------------------------------------------------------------------------
-- Mod editions
--------------------------------------------------------------------------------

--- A mod edition's look (`SMODS.Edition`'s `fx`) as the same two passes the vanilla editions
--- use: `tint` multiplies the art, `glow` is added over it, and `animation` moves the glow --
--- "sweep" a band across the card like foil, "shimmer" through the shared interference field
--- like holo, "rainbow" the field's hues like polychrome (tint and glow colour ignored),
--- "pulse" in and out, "steady" not at all. Declarative on purpose: these run per vertex
--- every frame, and mod code there could neither be afforded nor safely fail.
---@param look table `{ tint = {r,g,b}, glow = {r,g,b,a}, animation = string }`
---@return table passes
local function mod_edition_passes(look)
    local tr, tg, tb = look.tint[1], look.tint[2], look.tint[3]
    local gr, gg, gb, ga = look.glow[1], look.glow[2], look.glow[3], look.glow[4]
    local anim = look.animation
    if anim == "rainbow" then
        return {
            base = Fx.polychrome_base_rgba, base_field = "polychrome",
            add = function(field, n, u, v, t, seed)
                local r, g, b = Fx.hue_rgb(field[n] + 0.15 + seed)
                return r, g, b, ga
            end,
            add_field = "polychrome",
        }
    end
    local passes = { base = function() return tr, tg, tb, 1 end }
    if anim == "shimmer" then
        passes.add = function(field, n, u, v, t, seed)
            return gr, gg, gb, ga * (0.4 + 0.6 * ((field[n] + seed) % 1))
        end
        passes.add_field = "holo"
    elseif anim == "pulse" then
        passes.add = function(u, v, t) return gr, gg, gb, ga * (0.55 + 0.45 * math.sin(t * 2.5)) end
    elseif anim == "steady" then
        passes.add = function() return gr, gg, gb, ga end
    else
        passes.add = function(u, v, t)
            local pos = (t * 0.5) % 1.9 - 0.35
            return gr, gg, gb, ga * (0.12 + 0.88 * Fx.band(u * 0.72 + v * 0.45, pos, 0.35))
        end
    end
    return passes
end

--- The flat stand-in tint for each mod edition, where shelves do not animate.
local MOD_EDITION_TINTS = {}

--- Make a mod edition drawable. Called by `SMODS.Edition`.
function Fx.register_edition(id, look)
    EDITION_PASSES[id] = mod_edition_passes(look)
    MOD_EDITION_TINTS[id] = look.animation == "rainbow" and { 0.88, 0.72, 1.0 } or look.tint
end

function Fx.unregister_edition(id)
    if MOD_EDITION_TINTS[id] then
        EDITION_PASSES[id] = nil
        MOD_EDITION_TINTS[id] = nil
    end
end

--- The flat tint for a mod edition, or nil for anything else.
---@return table|nil `{ r, g, b }`
function Fx.mod_edition_tint(id)
    return MOD_EDITION_TINTS[id]
end

--- Source rect of one pattern cell.
---@param pattern table
---@param variant string "card" or "joker"
---@param phase number 0..1, wraps; the reference drives this from card rotation, juice
---                    and tilt rather than from a frame counter (`card.lua:4349`)
---@return number sx, number sy, number cw, number ch
function Fx.pattern_cell(pattern, variant, phase)
    local geo = pattern.variants[variant] or pattern.variants.card
    local i = math.floor((phase % 1) * pattern.phases) % pattern.phases
    local col, row = i % pattern.cols, math.floor(i / pattern.cols)
    return geo.x + col * geo.w, geo.y + row * geo.h, geo.w, geo.h
end

-- Foil's phase crawls on its own at one cycle per FOIL_CRAWL_PERIOD seconds. The
-- reference's own crawl is `REAL/28` against a `foil.r*2` phase, which is one cycle per
-- ~88 s; there the shimmer comes almost entirely from mouse-driven card motion, and a
-- 3DS has none. This is the deliberate divergence: fast enough to read as alive on a
-- resting card, with rotation and juice still doing most of the work when a card moves.
local FOIL_CRAWL_PERIOD = 6

--- Foil pattern phase for a card. Mirrors `card.lua:4349`'s inputs — rotation clamped
--- the same way, juice, and a clock — normalized to the 0..1 the pattern sheet wants.
---@param rot number|nil card rotation in radians
---@param juice_r number|nil juice rotation
---@param t number animation time
---@return number
function Fx.foil_phase(rot, juice_r, t)
    local r = math.min((rot or 0) * 3, 1)
    return (r + (juice_r or 0) * 20 + t / FOIL_CRAWL_PERIOD) % 1
end

--- Whether `edition` has a mesh effect (negative uses baked sprites instead).
---@param edition string|nil
---@return boolean
function Fx.has_edition_fx(edition)
    return EDITION_PASSES[edition] ~= nil
end

-- Shop shelves animate editions only where the CPU can afford two transient meshes per
-- item per frame on top of shop input handling: New 3DS (804 MHz, >2 ARM11 cores — the
-- same probe input_bindings.lua and sfx.lua use) and desktop. The Old 3DS keeps the flat
-- tint. In play areas editions always animate; this gate is shop-only.
---@return boolean
function Fx.shop_editions_animated()
    return Console.is_new_3ds()
end

--------------------------------------------------------------------------------
-- Strip mesh
--------------------------------------------------------------------------------

-- Columns in the strip. 8 gives ~9 px per column on a 71 px card cell: enough for the
-- Gouraud bands to look continuous, few enough that a hand of edition cards stays well
-- inside the runtime's 24576-vertices-per-frame buffer.
local COLS = 8
local VERT_COUNT = (COLS + 1) * 2

-- Pooled vertex tables. newMesh copies the data, so one pool serves every pass.
local vert_pool = {}
for i = 1, VERT_COUNT do
    vert_pool[i] = { 0, 0, 0, 0, 1, 1, 1, 1 }
end

--- Fill the pooled strip for one cell. Triangle-strip order: top/bottom pairs per
--- column, positions local to the layer (0..w, 0..h), UVs against the full image.
---@param sx number cell x in source pixels
---@param sy number cell y in source pixels
---@param cw number cell width in source pixels
---@param ch number cell height in source pixels
---@param iw number image width as reported by getDimensions
---@param ih number image height as reported by getDimensions
---@param w number draw width
---@param h number draw height
---@param t number animation time
---@param color_fn fun(u:number, v:number, t:number): number, number, number, number
---@return table[] verts the pooled vertex tables (valid until the next build)
function Fx.build_strip(sx, sy, cw, ch, iw, ih, w, h, t, color_fn)
    local n = 0
    for i = 0, COLS do
        local u = i / COLS
        local tx = (sx + u * cw) / iw
        for row = 0, 1 do
            n = n + 1
            local vert = vert_pool[n]
            vert[1] = u * w
            vert[2] = row * h
            vert[3] = tx
            vert[4] = (sy + row * ch) / ih
            vert[5], vert[6], vert[7], vert[8] = color_fn(u, row, t)
        end
    end
    return vert_pool
end

-- Grid mesh for field-driven passes. One triangle strip walks every row, stitched at
-- the seams with a pair of degenerate vertices, so the whole grid is still one draw.
--
-- One pool per resolution, each sized exactly, because `newMesh` takes the table whole:
-- a shared oversized pool would need a per-frame slice, which is the allocation this
-- pooling exists to avoid. Built on demand so only the console's own size is paid for.
local grid_pools = {}

---@param grid integer
---@return table[] pool, integer vert_count
local function grid_pool_for(grid)
    local pool = grid_pools[grid]
    if not pool then
        pool = {}
        for i = 1, grid * (grid + 1) * 2 + (grid - 1) * 2 do
            pool[i] = { 0, 0, 0, 0, 1, 1, 1, 1 }
        end
        grid_pools[grid] = pool
    end
    return pool, #pool
end

--- Fill the pooled grid for one cell. Colours come from a shared field table indexed by
--- vertex, so the expensive part of the field is paid once a frame for the whole board.
---@param color_fn fun(field:table, n:number, u:number, v:number, t:number, seed:number): number, number, number, number
---@param field table shared field samples from `Fx.field_table`
---@param seed number per-card hue offset
---@param grid_override integer|nil resolution to build at; defaults to this console's
---@param colors table|nil flat r,g,b,a per field sample; supplied instead of `color_fn` when
---       the colour depends only on the sample, which lets the caller bake it once per sample
---       rather than once per vertex (see `bake_dissolve_samples`)
---@return table[] verts the pooled grid, always filled exactly
function Fx.build_grid(sx, sy, cw, ch, iw, ih, w, h, t, color_fn, field, seed, grid_override,
                       colors)
    local grid = grid_override or field_grid()
    local pool, vert_count = grid_pool_for(grid)
    local stride = grid + 1
    local n = 0

    -- The emit body is written out rather than factored into a local function: this runs
    -- 46-94 times per pass per node per frame, and a closure over the dozen upvalues it
    -- would need is a real allocation on every call plus an indirect call each vertex.
    for j = 0, grid - 1 do
        for i = 0, grid do
            local u = i / grid
            local tx, ty = (sx + u * cw) / iw, u * w
            for row = j, j + 1 do
                local v = row / grid
                n = n + 1
                local vert = pool[n]
                vert[1] = ty
                vert[2] = v * h
                vert[3] = tx
                vert[4] = (sy + v * ch) / ih
                local m = row * stride + i
                if colors then
                    m = m * 4
                    vert[5], vert[6], vert[7], vert[8] =
                        colors[m + 1], colors[m + 2], colors[m + 3], colors[m + 4]
                else
                    vert[5], vert[6], vert[7], vert[8] =
                        color_fn(field, m + 1, u, v, t, seed)
                end
            end
        end
        if j < grid - 1 then
            -- Degenerate pair: close this row out and restart at the next row's left edge.
            local v = (j + 1) / grid
            local vy, tv = v * h, (sy + v * ch) / ih
            local base = (j + 1) * stride
            for k = 1, 2 do
                local i = k == 1 and grid or 0
                local u = i / grid
                n = n + 1
                local vert = pool[n]
                vert[1] = u * w
                vert[2] = vy
                vert[3] = (sx + u * cw) / iw
                vert[4] = tv
                local m = base + i
                if colors then
                    m = m * 4
                    vert[5], vert[6], vert[7], vert[8] =
                        colors[m + 1], colors[m + 2], colors[m + 3], colors[m + 4]
                else
                    vert[5], vert[6], vert[7], vert[8] =
                        color_fn(field, m + 1, u, v, t, seed)
                end
            end
        end
    end
    assert(n == vert_count, "grid strip must fill the pool exactly")
    return pool
end

--- Rewrite just the colours of an already-built grid, leaving positions and UVs alone.
---
--- Measured, the per-vertex *geometry* is what a grid pass costs - the UV divides, the
--- position math and the pool writes - not the colour that goes with it. Two passes over the
--- same cell (the dissolve's masked art and its additive burn) build byte-identical positions
--- and UVs and differ in nothing but colour, so the second one has no business rebuilding
--- them: recolouring the strip runs at about half the cost of rebuilding it.
---
--- Only safe immediately after the `build_grid` whose strip is being recoloured, because the
--- pool is shared per grid size. `draw_mesh` copies the vertices into the draw command
--- (`Mesh:setVertices`), so drawing in between is fine; building another grid is not.
---@param verts table[] the pool returned by `build_grid`
---@param colors table flat r,g,b,a per field sample
---@param grid integer the resolution it was built at
---@return table[] verts the same pool
function Fx.recolor_grid(verts, colors, grid)
    local stride = grid + 1
    local n = 0
    for j = 0, grid - 1 do
        for i = 0, grid do
            for row = j, j + 1 do
                n = n + 1
                local m, vert = (row * stride + i) * 4, verts[n]
                vert[5], vert[6], vert[7], vert[8] =
                    colors[m + 1], colors[m + 2], colors[m + 3], colors[m + 4]
            end
        end
        if j < grid - 1 then
            local base = (j + 1) * stride
            for k = 1, 2 do
                n = n + 1
                local m = (base + (k == 1 and grid or 0)) * 4
                local vert = verts[n]
                vert[5], vert[6], vert[7], vert[8] =
                    colors[m + 1], colors[m + 2], colors[m + 3], colors[m + 4]
            end
        end
    end
    return verts
end

--- Padded texture dimensions for UV math. On the 3DS the GPU texture is padded to
--- powers of two (`platform/ctr/source/objects/texture_ext.cpp:10`, `NextPo2`) and the
--- runtime normalizes quad UVs against that physical size (`texture_ext.cpp:291`), but
--- `Image:getDimensions()` reports the source art size (`t3xhandler.cpp:51`) and meshes
--- get no rescale (`source/objects/mesh/mesh.cpp:222` only V-flips). Dividing by the
--- reported size therefore maps the whole padded texture into the quad on hardware:
--- the art shrinks to source/padded of the mesh and the effect sweeps mostly padding.
--- Desktop textures are never padded, so there the reported size is the physical size.
--- `Console.is_hardware` is the probe that can tell a real 3DS from nest; see console.lua
--- for why the console name alone cannot.

--- Physical (padded) texture size for a reported source size. Pure; exposed for tests.
---@param iw number
---@param ih number
---@return number, number
function Fx.padded_uv_dimensions(iw, ih)
    local function next_pow2(n)
        local p = 8 -- t3x minimum edge (t3xhandler.cpp:43, 1 << 3)
        while p < n do p = p * 2 end
        return p
    end
    return next_pow2(iw), next_pow2(ih)
end

local function uv_dimensions(image)
    local iw, ih = image:getDimensions()
    if Console.is_hardware() then
        return Fx.padded_uv_dimensions(iw, ih)
    end
    return iw, ih
end

--- Draw a pooled vertex table through a cached mesh, one per vertex count (the strip
--- and one grid size per console). The runtime copies the buffer into the draw command
--- on every draw, so one mesh can be rewritten and drawn many times a frame. The
--- texture is detached after drawing because a Mesh holds a strong reference to it —
--- a cached mesh left pointing at an edition sheet would pin the sheet through the
--- atlas unloads on state transitions (game.lua `unload_asset_atlas`).
---
--- `Mesh:setVertices` is this repo's own runtime binding (dev/patch_lovepotion.py);
--- against an unpatched runtime the probe fails once and every pass falls back to the
--- old build-and-release path.
local mesh_cache = {}
local function draw_mesh(verts, image, dx, dy, blend)
    local key = #verts
    local mesh = mesh_cache[key]
    if mesh then
        mesh:setVertices(verts)
    else
        mesh = love.graphics.newMesh(verts, "strip", "stream")
        if mesh.setVertices then
            mesh_cache[key] = mesh
        end
    end
    mesh:setTexture(image)
    if blend then love.graphics.setBlendMode(blend) end
    love.graphics.draw(mesh, dx, dy)
    if blend then love.graphics.setBlendMode("alpha") end
    mesh:setTexture(nil)
    if not mesh_cache[key] and mesh.release then mesh:release() end
end

--- One edition pass. `field_kind` selects the dense grid driven by a shared field
--- table; without it the pass is the cheap 9x2 strip.
local function edition_pass(image, sx, sy, cw, ch, dx, dy, w, h, t, color_fn, blend,
                            field_kind, seed)
    if not image then return end
    local iw, ih = uv_dimensions(image)
    if field_kind then
        local field = Fx.field_table(field_kind, t)
        -- build_grid always fills the pool exactly, so newMesh can take it whole.
        draw_mesh(Fx.build_grid(sx, sy, cw, ch, iw, ih, w, h, t, color_fn, field, seed),
            image, dx, dy, blend)
    else
        draw_mesh(Fx.build_strip(sx, sy, cw, ch, iw, ih, w, h, t, color_fn),
            image, dx, dy, blend)
    end
end

--- The loaded pattern sheet for an edition, or nil if it is not resident yet. Lazily
--- loaded through the game's atlas registry so it is unloaded with everything else on a
--- state transition; a missing sheet degrades to the base pass rather than failing.
---@param pattern table
---@return love.Image|nil
function Fx.pattern_image(pattern)
    local game = _G.G
    if not (game and game.ensure_asset_atlas_loaded) then return nil end
    local atlas = game:ensure_asset_atlas_loaded(pattern.atlas)
    return atlas and atlas.image or nil
end

--- Run both passes of an edition over one source rect.
---
--- `art_h` is the height of the real art inside `h`, for the handful of joker fronts whose
--- sprite is shorter than the cell it ships in (`joker.lua` SHORT_ART_HEIGHT). It only ever
--- shrinks the additive pass: that one samples a *baked* silhouette rather than the art, so
--- nothing else knows the art stops early and the sheen would otherwise hang below the card.
--- The base pass still spans `h`, because its texture is the art itself and any other
--- rectangle would squash it; its alpha does the masking there, and the only cost is that the
--- colour ramp runs over the padded height. Nil means "art fills the rect", the normal case.
local function draw_edition(image, sx, sy, cw, ch, dx, dy, w, h, edition, t, variant, phase, seed, art_h)
    local passes = EDITION_PASSES[edition]
    if not passes then return end
    seed = seed or 0

    edition_pass(image, sx, sy, cw, ch, dx, dy, w, h, t, passes.base, nil,
        passes.base_field, seed)

    -- The additive pass samples the pattern sheet where the edition has one, and the
    -- art itself otherwise. Either way the source's own alpha masks the pass to the
    -- card silhouette: ctr has no stencil, and `add` is (SRC_ALPHA, ONE).
    local add_image, ax, ay, aw, ah = image, sx, sy, cw, ch
    local add_h = h
    if passes.pattern then
        local sheet = Fx.pattern_image(passes.pattern)
        if sheet then
            add_image = sheet
            ax, ay, aw, ah = Fx.pattern_cell(passes.pattern, variant or "card", phase or 0)
            if art_h and art_h > 0 and art_h < h then add_h = art_h end
        elseif passes.pattern_required then
            return
        end
    end
    edition_pass(add_image, ax, ay, aw, ah, dx, dy, w, add_h, t, passes.add, "add",
        passes.add_field, seed)
end

--- Draw one atlas cell with an edition effect, replacing the plain layer draw.
--- Call under the caller's transform; `dx, dy` are the layer's draw position.
---@param image love.Image
---@param sx number cell x in source pixels (declared geometry, never derived)
---@param sy number cell y
---@param cw number cell width
---@param ch number cell height
---@param dx number draw x
---@param dy number draw y
---@param w number draw width
---@param h number draw height
---@param edition "foil"|"holo"|"polychrome"
---@param t number animation time
---@param variant string|nil "card" (default) or "joker" — which baked silhouette to use
---@param phase number|nil 0..1 pattern phase; foil takes card rotation/juice here
---@param seed number|nil per-card hue offset so a row of cards does not move in lockstep
function Fx.draw_edition_cell(image, sx, sy, cw, ch, dx, dy, w, h, edition, t, variant, phase, seed)
    draw_edition(image, sx, sy, cw, ch, dx, dy, w, h, edition, t, variant or "card", phase, seed)
end

--- Draw a whole image with an edition effect, mirroring `love.graphics.draw(image,
--- dx, dy)` exactly: positions span the reported dimensions, UVs run 0..1. This is
--- the only safe form for individual sprites (jokers) — sub-region cell math against
--- a t3x's power-of-two padded dimensions shifts and shrinks the art on hardware,
--- while the full rectangle is geometrically identical to the plain draw on every
--- platform by construction. On hardware the colour gradient spans the padded
--- rectangle rather than just the art; at these paddings that only stretches the
--- sweep slightly.
---@param image love.Image
---@param dx number draw x
---@param dy number draw y
---@param edition "foil"|"holo"|"polychrome"
---@param t number animation time
---@param phase number|nil 0..1 pattern phase
---@param seed number|nil per-card hue offset
---@param art_h number|nil height of the real art within the sprite, for fronts that ship
---                       shorter than their cell; nil when the art fills it
function Fx.draw_edition_image(image, dx, dy, edition, t, phase, seed, art_h)
    if not EDITION_PASSES[edition] then return end
    local iw, ih = image:getDimensions()
    draw_edition(image, 0, 0, iw, ih, dx, dy, iw, ih, edition, t, "joker", phase, seed, art_h)
end

-- Gold seal sweep timing: a shine crosses the seal for SHINE_SWEEP seconds out of
-- every SHINE_PERIOD, echoing the reference's pulsed `gold_seal.r` uniform
-- (`reference/Balatro/resources/shaders/gold_seal.fs:15`).
local SHINE_PERIOD = 4.0
local SHINE_SWEEP = 0.8

--- Sweep progress at time `t`, or nil while resting. Exposed for tests and so callers
--- can skip the pass entirely most of the time.
---@param t number
---@return number|nil pos band centre in projected 0..1-ish space
function Fx.shine_pos(t)
    local phase = t % SHINE_PERIOD
    if phase >= SHINE_SWEEP then return nil end
    -- run past both edges so the band enters and leaves cleanly
    return (phase / SHINE_SWEEP) * 1.6 - 0.3
end

local function shine_color_fn(u, v, t)
    local pos = Fx.shine_pos(t)
    if not pos then return 1, 1, 1, 0 end
    local a = Fx.band(u * 0.8 + v * 0.4, pos, 0.22)
    return 1.0, 0.95, 0.7, a * 0.9
end

--- Additive light sweep over a layer (gold seals; also fits voucher/booster sheens).
--- Draw the layer normally first; this only adds the moving highlight.
function Fx.draw_shine_cell(image, sx, sy, cw, ch, dx, dy, w, h, t)
    if not Fx.shine_pos(t) then return end
    edition_pass(image, sx, sy, cw, ch, dx, dy, w, h, t, shine_color_fn, "add")
end

--------------------------------------------------------------------------------
-- Dissolve / materialize
--
-- The reference does not shrink or fade a card that is being destroyed or created.
-- `Card:start_dissolve` and `Card:start_materialize` (`reference/Balatro/card.lua:2130`,
-- `:2183`) only ease a scalar `dissolve` — 0 to 1 over 0.7 s, or 1 to 0 over 0.6 s,
-- linearly (`engine/event.lua:70`, ease type `lerp`) — and every sprite layer is then
-- drawn through `dissolve.fs` with that value. The card stays at full size and full
-- opacity throughout; what the player sees is entirely the shader.
--
-- Three things happen in it, and all three survive the trip to a fragment-stage-less
-- GPU because `Fx.build_grid` already gives per-vertex colour over an image cell:
--
--  * The art lerps toward a burn colour, `tex.rgb*(1-0.6*d) + 0.6*burn.rgb*d`
--    (`dissolve.fs:59-65`). Split here into a greyscale multiply on the base pass and
--    an additive pass, the same two-pass shape every edition already uses.
--  * A per-pixel noise value is thresholded against `d`, so pixels drop out in noise
--    order (`dissolve.fs:36-41`). The field is the same three-part interference field
--    holo and polychrome use — `build_field` is shared — but sampled at a time that is
--    a per-card constant (`sprite.lua:100` feeds it `123.33412*(ID/1.14212)%3000`), so
--    unlike the edition fields it never moves. That is what makes this cheap: the field
--    is built once per variant per grid size and cached forever, and a frame only
--    thresholds it.
--  * The threshold front is coloured. Pixels just above the cut take `burn_colour_1`,
--    a wider band behind them takes `burn_colour_2` (`dissolve.fs:44-50`).
--
-- Two deliberate divergences. The shader's cut is per-pixel and hard; Gouraud gives a
-- soft front about one grid cell wide (~18 px at grid 4 on a 71 px card), which
-- EDGE_SHARPNESS tightens as far as vertex interpolation allows. And the shader
-- normalizes both texture axes by the larger one before testing the 0.2/0.8 border
-- margins, so on a 71x95 cell the right-hand margin is never reached and the card burns
-- in from three sides; each axis is normalized by its own extent here, so the burn is
-- symmetric.
--------------------------------------------------------------------------------

-- What the mask can and cannot be on this hardware, decided by measurement rather than taste.
--
-- The base game cuts per pixel, so its holes have smooth curved outlines. Three ways to get a
-- per-pixel cut on a PICA200 were checked and all three are closed: there is no programmable
-- fragment stage; `C3D_AlphaTest` is never bound by LovePotion on ctr (only the Wii U backend
-- calls the equivalent, `platform/cafe/.../renderer_ext.cpp:56`); and stencil appears on ctr
-- only in render-target plumbing, which is moot because canvases do not render there at all.
-- So the outline has to be built out of geometry, and the only question is which geometry.
--
-- Flat hard-edged tiles were tried and are worse than the problem they solved. A tile is honest
-- per-pixel-style masking at tile resolution, but resolution is exactly what is scarce:
-- vertices are the binding cost (`wrap_graphics.cpp:1594-1641` - `setVertices` crosses the
-- Lua/C boundary nine times per vertex), and a tile grid fine enough to trace a curve needs
-- thousands of them. At an affordable 8x10 the card came apart into 9 px blocks, which reads as
-- a mosaic filter rather than as burning.
--
-- An interpolated grid spends its vertices better. The alpha = 0.5 contour of a Gouraud grid is
-- a polyline through the cells, so it *curves* - the edge is placed to sub-cell precision even
-- though the samples are not. That is the right trade at 240p: a curved edge one cell soft
-- looks far more like the shader than a hard edge nine pixels square. What went wrong the first
-- time round was not interpolation, it was resolution - at grid 8 with a field cut down to one
-- blob per card, isolated single-sample survivors were common and each one interpolates into a
-- diamond. A grid fine enough to resolve the field turns those into connected regions with
-- curved boundaries, which is what `test_fx.lua` now measures directly.
-- Chosen by eye against the shader running side by side, at grid 16. 154 puts six or seven
-- separate holes in the card at mid-tween and takes the measured front to 4.6 px.
local DISSOLVE_FIELD_SPAN = 154

-- Distinct noise fields to draw from. The reference gives every card its own by seeding
-- from the card's ID; four is enough that two cards dissolving side by side do not come
-- apart in lockstep, and it bounds the cache.
local DISSOLVE_VARIANTS = 4

-- Grid resolution for the mask. 16 puts a sample every ~4.4 px on a 71 px card and costs 574
-- vertices a pass; a dissolving card is 1148 across both passes, against the ~1500 a full board
-- of animated editions already spends every frame. This is affordable precisely because a
-- dissolve is one to three nodes for 0.7 s rather than the whole board forever. An Old 3DS
-- drops to 10 (~7 px samples, 476 vertices a card), still fine enough for the contour to curve.
local DISSOLVE_GRID_FULL = 16
local DISSOLVE_GRID_REDUCED = 10
local DISSOLVE_GRID_CROWD = 8

-- How many cards have to be dissolving at once before the mask drops a resolution step.
--
-- The vertex cost is per card and the passes are per card, so a Mega pack landing five
-- materialises at once asks for five times the work a lone dissolve was tuned against, and
-- the tuning had no headroom in it. Dropping a step during a crowd is the cheap half of the
-- answer: grid 16 to 10 is 574 vertices a pass down to 238, and grid 10 to 8 is 238 down to
-- 158. What it costs is contour resolution on the burn front, which is precisely what nobody
-- can look at while five cards are burning in on a 240p screen - and the moment the crowd
-- thins the fine grid comes back, so the dissolve a player actually watches is unchanged.
--
-- Three rather than two because two overlapping dissolves is ordinary play (a hand's worth of
-- consumables, a card destroyed while another arrives) and those still get the full grid.
local DISSOLVE_CROWD = 3

-- Cards counted mid-dissolve last frame, and the counter this frame is filling. Read a frame
-- late on purpose: a dissolve runs 0.6-0.7 s, so a one-frame-stale count is right for all but
-- the first frame of a burst, and reading it stale is what keeps the grid *stable within* a
-- frame. A card's base, additive and shadow passes have to agree on a resolution or they mask
-- each other's holes, and they only agree because nothing moves this between them.
local dissolve_draws, dissolve_crowd = 0, 0

--- Roll the dissolve crowd count over. Call once per frame from `love.update`, not from
--- `love.draw` - draw runs once per screen (twice with stereoscopic depth on), and rolling
--- there would zero the count halfway through the frame it describes.
function Fx.begin_frame()
    dissolve_crowd = dissolve_draws
    dissolve_draws = 0
end

--- Cards seen dissolving last frame. Exposed for tests.
---@return integer
function Fx.dissolve_crowd()
    return dissolve_crowd
end

---@return integer
local function dissolve_grid()
    local crowded = dissolve_crowd >= DISSOLVE_CROWD
    if Console.is_new_3ds() then
        return crowded and DISSOLVE_GRID_REDUCED or DISSOLVE_GRID_FULL
    end
    return crowded and DISSOLVE_GRID_CROWD or DISSOLVE_GRID_REDUCED
end

--- Field span for a grid, scaled so every console samples the pattern at the same density.
---
--- Span and grid are not independent: what matters is samples per wave. At the tuned span a
--- New 3DS gets about five, which is enough that survivors form connected regions. Handing the
--- Old 3DS's coarser grid the same span drops it to three, and single-sample survivors start
--- appearing - each one interpolating into the diamond this whole approach exists to avoid
--- (measured: two of 244 samples). Scaling the span keeps the ratio, so the Old 3DS gets the
--- same look with fewer, larger holes rather than the same holes with artifacts in them.
---@param grid integer
---@return number
local function dissolve_span(grid)
    return DISSOLVE_FIELD_SPAN * grid / DISSOLVE_GRID_FULL
end

-- How fast the mask goes from opaque to gone across the front, in field units.
--
-- One Gouraud cell is the hard floor: once neighbouring samples saturate at 0 and 1 the
-- interpolated ramp spans exactly one cell however sharp this gets. At grid 16 that is ~4.4 px
-- on a 71 px card, which is the softness being traded for a curved contour. At the tuned span
-- the measured 90%-to-10% front is 4.6 px (grid 16) and 6.2 px (grid 10); `test_fx.lua` pins
-- that so a regression to a foggy front is caught.
local EDGE_SHARPNESS = 80

-- Half the width of that transition, in field units. The shader's cut is a hard test
-- (`dissolve.fs:51`), so at d = 0 a sample sitting 0.005 above the threshold is fully opaque,
-- where a soft front would render it half gone. The field is squeezed into [h, 1-h] when it is
-- baked so the ramp has that headroom at both ends.
local EDGE_HALF_WIDTH = 0.5 / EDGE_SHARPNESS

-- How far the art is pushed toward the burn colour at full dissolve. `dissolve.fs:61` uses 0.6;
-- this port pushes a little harder because its front is softer than a per-pixel cut and the
-- wash has to say some of what the edge cannot. Not much harder, though: a heavy wash flattens
-- the art's own contrast, and a low-contrast card on a 240p screen reads as blurred rather than
-- as burning.
local BURN_WASH = 0.7

-- Where the border bias starts eating, and how hard (`dissolve.fs:38-41`).
local BORDER_LOW, BORDER_HIGH = 0.2, 0.8

-- The shader's erosion schedule, inverted.
--
-- What has to match the base game is *when* a card is half gone, not which half. The port gets
-- to choose its own pattern - it has 81 samples where the shader has 6745, so it has to - but
-- if the schedules differ the whole animation is mistimed, and it did: the port was empty by
-- d = 0.6 where the shader still has a third of the card, then sat invisible for the rest of
-- the tween. A materialise had it worse, since that is the same curve backwards: nothing on
-- screen for the first 40% of the fade and then a card arriving at half strength, which is
-- what a booster pack of them looked like.
--
-- So the schedule is taken from the shader rather than inferred. Sampling `dissolve.fs` per
-- pixel over a real 70x94 sprite, across all four noise variants and 401 values of `d` - with
-- its own `floored_uv` normalisation and its own border term - gives the fraction of the card
-- still standing at every moment. Inverting that gives this: for each fraction eroded, the
-- `adjusted_dissolve` at which the shader has eaten exactly that much.
--
-- Baking it into the field (see `dissolve_field`) makes the port's schedule identical by
-- construction, and lets the runtime drop the border term entirely - the ordering it bought is
-- already in the data.
local REFERENCE_ERODE_SCHEDULE = {
    0.0000, 0.0066, 0.0523, 0.1207, 0.1900, 0.2482, 0.3092, 0.3704, 0.4247,
    0.4892, 0.5677, 0.6518, 0.7480, 0.8423, 0.9171, 0.9760, 1.0000,
}

-- How strongly the card's margins are pushed to the front of the queue when the field is
-- baked. The shader eats edges with a term that *grows* through the tween (`dissolve.fs:38-41`)
-- - near zero early, dominant late - so its first holes are interior and the border rush comes
-- mid-tween. A static bake cannot reproduce that ordering-over-time, and the first value here
-- (2.5, against a field range of 1) sent every border sample first, which read as the card
-- being eaten from the sides instead of through. 0.2 leaves the margins only slightly ahead, so
-- the field decides almost everything and holes open wherever its waves fall; the schedule map
-- keeps the overall timing right regardless of how the ordering is weighted.
local BORDER_ORDER_BIAS = 0.2

--- Threshold samples for one variant at one grid size: the static per-sample value every
--- frame of a dissolve compares against. Built once, kept for the process's life — the
--- whole table is (grid+1)^2 numbers, 289 at grid 16.
local dissolve_fields = {}

---@param variant integer 1..DISSOLVE_VARIANTS
---@param grid integer
---@return table values (grid+1)^2 samples, row-major
local function dissolve_field(variant, grid)
    local by_grid = dissolve_fields[variant]
    if not by_grid then
        by_grid = {}
        dissolve_fields[variant] = by_grid
    end
    local values = by_grid[grid]
    if values then return values end

    values = {}
    -- `sprite.lua:100` sends `time` as this expression of the card's ID and `dissolve.fs:23`
    -- then reads `time*10 + 2003`; the variant index stands in for the ID.
    local t = ((123.33412 * (variant / 1.14212)) % 3000) * 10 + 2003
    build_field(values, t, dissolve_span(grid), grid)
    -- `dissolve.fs:36` folds the field through a cosine to get the threshold. Its
    -- `adjusted_dissolve/82.612` term maxes out at 0.013 over the whole tween, which is
    -- below one step of this grid, so it is dropped and the result stays cacheable.
    for i = 1, #values do
        values[i] = 0.5 + 0.5 * math.cos((values[i] - 0.5) * math.pi)
    end

    -- Push the margins toward the front of the queue, the way the shader's border term does.
    -- Baked rather than applied per frame because after the ranking below only the order it
    -- produces survives, so a fixed profile is worth exactly as much as a growing one.
    local stride = grid + 1
    for j = 0, grid do
        local v = j / grid
        for i = 0, grid do
            local u = i / grid
            local pen = 0
            if u < BORDER_LOW then pen = pen + (BORDER_LOW - u) end
            if u > BORDER_HIGH then pen = pen + (u - BORDER_HIGH) end
            if v < BORDER_LOW then pen = pen + (BORDER_LOW - v) end
            if v > BORDER_HIGH then pen = pen + (v - BORDER_HIGH) end
            local n = j * stride + i + 1
            values[n] = values[n] - pen * BORDER_ORDER_BIAS
        end
    end

    -- Now put every sample on the shader's schedule. Sorting gives each one its place in the
    -- queue; REFERENCE_ERODE_SCHEDULE says what threshold that place is supposed to fall at.
    -- Because the map is monotone it reorders nothing - the front still eats the same parts of
    -- the card in the same order - but the timing becomes the base game's by construction, and
    -- `dissolve_delta` no longer needs a border term at all.
    local order = {}
    for i = 1, #values do order[i] = i end
    table.sort(order, function(a, b) return values[a] < values[b] end)
    local last = #values - 1
    local steps = #REFERENCE_ERODE_SCHEDULE - 1
    local scheduled = {}
    for rank, idx in ipairs(order) do
        local q = (rank - 1) / last * steps
        local lo = math.min(steps - 1, math.floor(q))
        local frac = q - lo
        local a0 = REFERENCE_ERODE_SCHEDULE[lo + 1]
        local a1 = REFERENCE_ERODE_SCHEDULE[lo + 2]
        scheduled[idx] = a0 + (a1 - a0) * frac
    end
    -- Leave the ramp's own width as headroom at both ends. A sample is fully opaque while the
    -- threshold sits EDGE_HALF_WIDTH below it and fully gone once it sits that far above, so
    -- squeezing the schedule into [h, 1-h] is what makes d = 0 a whole card and d = 1 an empty
    -- one. Doing it here rather than by stretching the threshold matters: stretching pushed the
    -- threshold past the top of the field before the tween ended, so the last sliver of a
    -- dissolve went early - and the first frame of a materialise, which is the same moment read
    -- backwards, showed nothing at all.
    local h = EDGE_HALF_WIDTH
    for i = 1, #values do values[i] = h + scheduled[i] * (1 - 2 * h) end

    by_grid[grid] = values
    return values
end

--- Build every dissolve field this console can ask for, ahead of time.
---
--- A field is cached for the life of the process but costs a `build_field` plus a sort of its
--- samples to bake, and a burst is by definition several cards wanting uncached ones on the
--- same frame. Both resolutions are baked, not just the crowded one: the crowd count is read a
--- frame late, so the *first* frame of a burst is still drawn at the full grid and would
--- otherwise bake four full-resolution fields on the one frame this all exists to protect.
---
--- Paying for all eight at boot is a few milliseconds against the 90 ms an atlas load already
--- costs there.
function Fx.prewarm_dissolve()
    local fine = Console.is_new_3ds() and DISSOLVE_GRID_FULL or DISSOLVE_GRID_REDUCED
    local coarse = Console.is_new_3ds() and DISSOLVE_GRID_REDUCED or DISSOLVE_GRID_CROWD
    for variant = 1, DISSOLVE_VARIANTS do
        dissolve_field(variant, fine)
        dissolve_field(variant, coarse)
    end
end

--- Declare a burst that is about to start, so its first frame is already at crowd resolution.
---
--- The crowd count is otherwise a frame behind, which is right for a burst that builds up and
--- wrong for one that arrives all at once: a booster pack releases five cards on a single
--- frame, and that frame - the one the player is watching - would be the only one drawn at the
--- full grid. The pack knows how many cards it is about to release, so it can just say.
---@param n number cards about to start dissolving
function Fx.expect_dissolves(n)
    n = math.floor(tonumber(n) or 0)
    if n > dissolve_crowd then dissolve_crowd = n end
end

--- Drop every baked field. For tests that need to observe baking happen; the running game
--- never calls this, since a field is valid for the life of the process.
function Fx.reset_dissolve_fields()
    for k in pairs(dissolve_fields) do dissolve_fields[k] = nil end
end

--- Whether a field is already baked, without baking it. Exposed so a test can tell the
--- difference between prewarming and merely asking - `dissolve_field_table` builds on demand,
--- so asserting through it would pass whether or not the prewarm did anything.
---@param variant integer
---@param grid integer
---@return boolean
function Fx.dissolve_field_cached(variant, grid)
    local by_grid = dissolve_fields[variant]
    return by_grid ~= nil and by_grid[grid] ~= nil
end

--- The threshold samples for one variant at this console's grid size. Exposed for tests and
--- for the desktop preview harness, which renders the shipped field rather than a copy of it.
---@param variant integer 1..DISSOLVE_VARIANTS
---@param grid integer|nil defaults to this console's grid
---@return table values, integer grid
function Fx.dissolve_field_table(variant, grid)
    grid = grid or dissolve_grid()
    return dissolve_field(variant, grid), grid
end

--- Noise variant for a node, from whatever identity it can offer.
---@param seed number|nil
---@return integer
function Fx.dissolve_variant(seed)
    return (math.floor(math.abs(tonumber(seed) or 0)) % DISSOLVE_VARIANTS) + 1
end

-- Per-pass state. The colour functions run once per vertex per pass and `build_grid`
-- fixes their signature, so what they need beyond a field sample lives here rather than
-- in a closure: a closure over eight upvalues would be a fresh allocation on every pass
-- of every dissolving node, which is exactly the per-frame garbage this module avoids.
-- Half-width of the burn ring in field units, and how much of the shader's `reach` the ring's
-- strength needs before it is at full heat. Against the field's ~0.06-per-cell gradient, 0.08
-- puts the ring a little over a cell either side of the front - wide enough to read as a band
-- rather than as a vertex lighting up, narrow enough that the card behind it is still art.
-- 0.2 saturates about a fifth of the way into the tween, which is where the shader's own band
-- has opened up enough to be visible.
local RING_HALF_WIDTH = 0.08
local RING_FADE_REACH = 0.2

local dstate = {
    d = 0, adj = 0, outer = 0, inner_frac = 1, ring = 0, tint = 1, shadow = 0,
    b1r = 1, b1g = 1, b1b = 1,
    b2r = 1, b2g = 1, b2b = 1,
}

--- Set up `dstate` for a dissolve amount and its burn colours.
---@param d number 0 = whole, 1 = gone
---@param burn1 table|nil leading-edge colour
---@param burn2 table|nil trailing band and wash colour
local function set_dissolve_state(d, burn1, burn2)
    -- `dissolve.fs:22`: smoothstep, then stretched past both ends so the mask does not
    -- stall at 0 and 1.
    local adj = (d * d * (3 - 2 * d)) * 1.02 - 0.01
    dstate.d = d
    -- Used raw: the headroom the soft front needs is baked into the field, not added here.
    dstate.adj = adj
    -- Band widths pinch shut at both ends of the tween and are widest halfway through
    -- (`dissolve.fs:44-47`), so the burn ring fades in and out with the erosion. The shader
    -- has two hard bands, the inner 0.5 of `reach` and the outer 0.8; here that ratio becomes
    -- where the ring finishes crossing from one burn colour to the other.
    --
    -- The shader's band is 0.8 of `reach` wide, so it pinches shut at both ends of the tween
    -- and is widest halfway through. Following that literally does not survive the drop from
    -- per-pixel to per-vertex: early on `reach` is about 0.02 while the threshold moves 0.01
    -- per frame, so a vertex crosses the entire ring between two frames and the burn colour
    -- strobes. The geometric width is fixed here instead, wide enough that crossing it takes
    -- several frames, and the pinching is moved onto the ring's *strength* — which is what it
    -- was buying visually anyway.
    local reach = 0.5 - math.abs(adj - 0.5)
    dstate.outer = RING_HALF_WIDTH
    dstate.inner_frac = 0.5 / 0.8
    dstate.ring = reach > 0 and math.min(1, reach / RING_FADE_REACH) or 0
    dstate.tint = 1 - BURN_WASH * d
    dstate.shadow = 0
    dstate.b1r, dstate.b1g, dstate.b1b = burn1 and burn1[1] or 1, burn1 and burn1[2] or 1,
        burn1 and burn1[3] or 1
    dstate.has_b2 = burn2 ~= nil
    dstate.b2r, dstate.b2g, dstate.b2b = burn2 and burn2[1] or dstate.b1r,
        burn2 and burn2[2] or dstate.b1g, burn2 and burn2[3] or dstate.b1b
end

--- Alpha of one tile: 1 fully present, 0 fully eaten, ramped across the temporal fade.
---@return number
local function dissolve_alpha(delta)
    local a = 0.5 + delta * EDGE_SHARPNESS
    if a > 1 then return 1 end
    if a < 0 then return 0 end
    return a
end

--- How hot the burn ring is at one tile, 1 right on the cut and 0 at the band's far edge.
---
--- A smooth bump rather than the shader's hard band test, and with tiles the reason is
--- temporal rather than spatial: a tile is one flat colour, so a hard classification would
--- flip the whole 9 px square from art to burn between two frames and the ring would strobe.
--- The bump makes every tile's ring heat a continuous function of `d`, so the burn washes
--- through a tile over a few frames on its way to eating it.
---@return number
local function dissolve_ring(delta)
    local strength = dstate.ring
    if strength <= 0 then return 0 end
    return Fx.band(delta, 0, RING_HALF_WIDTH) * strength
end

--- Which burn colour a ring sample carries. `dissolve.fs:44-50` puts colour 1 nearest the cut
--- and colour 2 behind it; the hard boundary between them becomes a crossfade.
---@return number r, number g, number b
local function dissolve_burn_rgb(delta)
    local q = delta / (RING_HALF_WIDTH * dstate.inner_frac)
    if q < 0 then q = -q end
    if q >= 1 then return dstate.b2r, dstate.b2g, dstate.b2b end
    return dstate.b1r + (dstate.b2r - dstate.b1r) * q,
        dstate.b1g + (dstate.b2g - dstate.b1g) * q,
        dstate.b1b + (dstate.b2b - dstate.b1b) * q
end

--- Base pass: the art, masked, pulled toward the burn colour by the wash, and pushed the rest
--- of the way at the ring.
local function dissolve_base_rgba(field, n)
    local delta = (field[n] or 0) - dstate.adj
    if delta <= -EDGE_HALF_WIDTH then return 0, 0, 0, 0 end
    local a = dissolve_alpha(delta)
    -- The shadow pass wants the silhouette and nothing else: black at a fixed opacity, so it
    -- comes apart on exactly the same holes as the card above it.
    if dstate.shadow > 0 then return 0, 0, 0, a * dstate.shadow end
    local ring = dissolve_ring(delta)
    local k = dstate.tint
    if ring <= 0 then return k, k, k, a end
    local r, g, b = dissolve_burn_rgb(delta)
    return k + (r - k) * ring, k + (g - k) * ring, k + (b - k) * ring, a
end

-- How hard the additive pass pushes the burn ring. The shader replaces the texel with a
-- flat burn colour there; a multiply can only darken, so the ring is brought back up by
-- adding it a second time.
local BAND_GLOW = 0.75

--- Additive pass: the other half of the burn lerp, plus the ring's own glow. `add` is
--- (SRC_ALPHA, ONE) here, so the art's own alpha masks it to the silhouette.
local function dissolve_add_rgba(field, n)
    local delta = (field[n] or 0) - dstate.adj
    if delta <= -EDGE_HALF_WIDTH then return 0, 0, 0, 0 end
    local a = dissolve_alpha(delta)
    local ring = dissolve_ring(delta)
    local r, g, b = dissolve_burn_rgb(delta)
    -- Wash everywhere, ring on top of it, both continuous in `delta`.
    local wash = BURN_WASH * dstate.d
    return r, g, b, a * (wash + (BAND_GLOW - wash) * ring)
end

-- Per-sample colour scratch for the two passes, flat r,g,b,a per field sample. Reused
-- across every dissolving card: a pass is baked and handed straight to `build_grid`, which
-- copies the numbers out before anything else runs, so no two cards ever need theirs at once.
local dissolve_base_colors = {}
local dissolve_add_colors = {}

--- Bake one pass's colours once per field sample rather than once per vertex.
---
--- The grid strip visits most samples twice - once as a row's bottom edge, once as the next
--- row's top - and the base, additive and shadow passes each recompute the same delta, alpha,
--- ring heat and burn lerp from the same field value. At grid 16 that is 574 evaluations a
--- pass against 289 distinct answers, and three passes deep on five cards at once the
--- duplicated arithmetic *is* the frame: this is PUC 5.1 at 0.31 us an op, and the pass
--- functions are twenty-odd ops each. Baking per sample first cuts the colour math about
--- six-fold and leaves `build_grid` copying four numbers a vertex, which also spares it the
--- per-vertex indirect call the `color_fn` path costs.
---@param out table flat r,g,b,a per sample, in place
---@param field table threshold samples
---@param rgba_fn fun(field:table, n:integer): number, number, number, number
local function bake_dissolve_samples(out, field, rgba_fn)
    local k = 0
    for n = 1, #field do
        local r, g, b, a = rgba_fn(field, n)
        out[k + 1], out[k + 2], out[k + 3], out[k + 4] = r, g, b, a
        k = k + 4
    end
end

--- Whether the mask can be drawn at all. Without a Mesh the caller has to fall back to a
--- plain alpha fade, so every draw entry point reports this rather than silently drawing
--- nothing.
---@return boolean
function Fx.dissolve_available()
    return love.graphics ~= nil and love.graphics.newMesh ~= nil
end

--- Draw one image cell through the dissolve mask, replacing its plain layer draw.
--- Call under the caller's transform; `dx, dy` is the layer's draw position.
---@param image love.Image
---@param sx number cell x in source pixels (declared geometry, never derived)
---@param sy number cell y
---@param cw number cell width
---@param ch number cell height
---@param dx number draw x
---@param dy number draw y
---@param w number draw width
---@param h number draw height
---@param d number 0 = whole, 1 = gone
---@param burn1 table|nil leading-edge colour, `{r, g, b}`
---@param burn2 table|nil trailing band and wash colour
---@param seed number|nil picks the noise variant
---@return boolean drawn false when the caller must fall back
function Fx.draw_dissolve_cell(image, sx, sy, cw, ch, dx, dy, w, h, d, burn1, burn2, seed)
    if not image or not Fx.dissolve_available() then return false end
    d = math.min(1, math.max(0, tonumber(d) or 0))
    if d >= 1 then return true end

    -- Counted before the passes, and read only on later frames (`Fx.begin_frame`), so a card
    -- never changes the resolution it is itself being drawn at. The shadow pass deliberately
    -- does not count: it is the same card.
    dissolve_draws = dissolve_draws + 1

    local grid = dissolve_grid()
    local field = dissolve_field(Fx.dissolve_variant(seed), grid)
    local iw, ih = uv_dimensions(image)
    set_dissolve_state(d, burn1, burn2)

    bake_dissolve_samples(dissolve_base_colors, field, dissolve_base_rgba)
    local verts = Fx.build_grid(sx, sy, cw, ch, iw, ih, w, h, 0, nil, field, 0, grid,
        dissolve_base_colors)
    draw_mesh(verts, image, dx, dy)
    -- Nothing to add before the burn has any colour in it; a card at rest never reaches
    -- this function, but the first frame of a materialize does.
    if d > 0.001 then
        -- Same cell, same grid, so the same geometry: recolour the strip rather than
        -- rebuilding it. `draw_mesh` has already copied the base pass out of the pool.
        bake_dissolve_samples(dissolve_add_colors, field, dissolve_add_rgba)
        draw_mesh(Fx.recolor_grid(verts, dissolve_add_colors, grid), image, dx, dy, "add")
    end
    return true
end

--- The same mask as a flat shadow: black at `alpha`, eaten on exactly the same holes.
---
--- The reference runs its shadow through `dissolve.fs` with `shadow = true`, which discards
--- the texel's colour and keeps its alpha (`sprite.lua:105`, `dissolve.fs:52`). Without this
--- the port left a solid card-shaped silhouette under a card that was two thirds gone, which
--- is the one part of a dissolve that cannot be hidden by being small.
---@return boolean drawn
function Fx.draw_dissolve_shadow(image, sx, sy, cw, ch, dx, dy, w, h, d, alpha, seed)
    if not image or not Fx.dissolve_available() then return false end
    d = math.min(1, math.max(0, tonumber(d) or 0))
    if d >= 1 then return true end

    local grid = dissolve_grid()
    local field = dissolve_field(Fx.dissolve_variant(seed), grid)
    local iw, ih = uv_dimensions(image)
    set_dissolve_state(d, nil, nil)
    dstate.shadow = alpha or 1
    bake_dissolve_samples(dissolve_base_colors, field, dissolve_base_rgba)
    draw_mesh(Fx.build_grid(sx, sy, cw, ch, iw, ih, w, h, 0, nil, field, 0, grid,
        dissolve_base_colors), image, dx, dy)
    dstate.shadow = 0
    return true
end

--- Whole-image form, mirroring `love.graphics.draw(image, dx, dy)` exactly. The only
--- safe form for individual sprites (jokers) — see `Fx.draw_edition_image` for why cell
--- math against a padded t3x shifts the art on hardware.
---@return boolean drawn
function Fx.draw_dissolve_image(image, dx, dy, d, burn1, burn2, seed)
    if not image or not Fx.dissolve_available() then return false end
    local iw, ih = image:getDimensions()
    return Fx.draw_dissolve_cell(image, 0, 0, iw, ih, dx, dy, iw, ih, d, burn1, burn2, seed)
end

--------------------------------------------------------------------------------
-- Score flames
--
-- The reference renders chip/mult flames with `flame.fs` driven by an intensity
-- state machine in `G.FUNCS.flame_handler`. The state machine ports directly
-- (`reference/Balatro/functions/button_callbacks.lua:2020-2033`); the rendering is
-- additive primitive licks instead of the shader's smoke field.
--------------------------------------------------------------------------------

--- Fresh flame state. `seed` offsets the flicker so two flames never sync.
---@param seed number|nil
function Fx.new_flame(seed)
    return { intensity = 0, real = 0, vel = 0, change = 0, timer = 0, seed = seed or 0 }
end

--- Target intensity from score: zero until the blind is beaten, then log5 of the
--- overkill score (`reference/Balatro/functions/button_callbacks.lua:2022-2026`).
---@param earned number|nil round score
---@param required number|nil blind target
---@return number
function Fx.flame_target(earned, required)
    earned = tonumber(earned) or 0
    required = tonumber(required) or 0
    if required <= 0 or earned < required then return 0 end
    return math.max(0, math.log(earned) / math.log(5) - 2)
end

--- Advance the flame toward `target`. Velocity-smoothed exactly like the reference
--- (`reference/Balatro/functions/button_callbacks.lua:2028-2033`), including the
--- faster clock at high intensity.
---@param f table flame state from new_flame
---@param target number
---@param dt number
function Fx.update_flame(f, target, dt)
    local exptime = math.exp(-0.4 * dt)
    f.intensity = target
    f.timer = f.timer + dt * (1 + f.intensity * 0.2)
    if f.vel < 0 then f.vel = f.vel * (1 - 10 * dt) end
    f.vel = (1 - exptime) * (f.intensity - f.real) * dt * 25 + exptime * f.vel
    f.real = math.max(0, f.real + f.vel)
    f.change = f.change * (1 - 4 * dt) + (4 * dt) * ((f.real < f.intensity) and 1 or 0) * f.real
end

--- Accent colour for the flame base, the reference's "lick" formula
--- (`reference/Balatro/functions/button_callbacks.lua:1964-1969`).
---@param colour table {r,g,b,a}
---@param yellow table {r,g,b,a}
---@return table accent
function Fx.flame_accent(colour, yellow)
    local accent = {}
    for i = 1, 3 do
        local c = (colour[i] * 0.5 + yellow[i] * 0.5) + 0.1
        accent[i] = math.min(math.max(c * c, 0.1), 1)
    end
    accent[4] = 1
    return accent
end

local FLAME_MIN = 0.08
local FLAME_MAX_H = 46 -- pixel height budget; the top screen is a 240 px readout
local FLAME_COL_W = 4  -- bar width: chunky, like the reference's PIXEL_SIZE_FAC pixelation
local FLAME_PX = 2     -- height quantization, hard steps like pixel art

--- Draw a flame rising from the top edge of a panel at (x, y), width w.
---
--- The reference flame (`flame.fs:57-66`) is a *solid* flat-colour silhouette cut out
--- of a wobbling noise field and pixelated hard — not a glow. Soft additive shapes
--- smear into blobs at 240p, so this draws opaque pixel columns: per-column heights
--- from layered sines (deterministic — effects must never advance math.random, the
--- run reseeds it for reproducibility), tapered toward the panel edges, with the
--- accent colour burning low in each column like the reference's root ramp
--- (`flame.fs:61-63`).
---@param f table flame state
---@param x number panel left
---@param y number flame base (panel top edge)
---@param w number panel width
---@param colour table body colour {r,g,b,a}
---@param accent table base colour {r,g,b,a}
function Fx.draw_flame(f, x, y, w, colour, accent)
    if f.real < FLAME_MIN then return end
    local inten = math.min(f.real, 10)
    local h = math.min(8 + 7 * inten, FLAME_MAX_H)
    local t = f.timer + f.seed
    local cols = math.max(3, math.floor(w / FLAME_COL_W))
    for i = 0, cols - 1 do
        local u = (i + 0.5) / cols
        -- Tallest mid-panel, tapering to stubs at the edges.
        local envelope = 0.30 + 0.70 * math.sin(math.pi * u)
        -- Two incommensurate sines per column: flickers without ever looping visibly.
        local flick = 0.62 + 0.38 * math.sin(t * 5.1 + i * 1.93) * math.sin(t * 3.7 + i * 0.77)
        local bh = math.floor((h * envelope * flick) / FLAME_PX + 0.5) * FLAME_PX
        if bh >= FLAME_PX then
            local cx = x + i * FLAME_COL_W
            love.graphics.setColor(colour[1], colour[2], colour[3], 1)
            love.graphics.rectangle("fill", cx, y - bh, FLAME_COL_W, bh)
            local ah = math.floor((bh * (0.34 + 0.12 * math.sin(t * 6.3 + i * 2.41))) / FLAME_PX + 0.5) * FLAME_PX
            if ah >= FLAME_PX then
                love.graphics.setColor(accent[1], accent[2], accent[3], 1)
                love.graphics.rectangle("fill", cx, y - ah, FLAME_COL_W, ah)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Fx

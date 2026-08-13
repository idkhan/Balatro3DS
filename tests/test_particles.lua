local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

bootstrap.load()
local Particles = require("particles")

suite.test("particles expire back into the pool and reuse their table", function()
    Particles.reset(1)
    local first = Particles.emit({ x = 4, y = 5, lifetime = 0.1 })
    T.assert_not_nil(first)
    Particles.update(0.1)
    T.assert_eq(Particles.count(), 0, "expired particle leaves the active set")

    local reused = Particles.emit({ x = 9, y = 12, lifetime = 1 })
    T.assert_eq(reused, first, "next burst reuses the expired table")
    T.assert_eq(reused.x, 9)
    T.assert_eq(reused.y, 12)
end)

suite.test("particles respect the fixed pool capacity", function()
    Particles.reset(2)
    T.assert_not_nil(Particles.emit({ lifetime = 1 }))
    T.assert_not_nil(Particles.emit({ lifetime = 1 }))
    local particle, reason = Particles.emit({ lifetime = 1 })
    T.assert_nil(particle)
    T.assert_eq(reason, "pool_exhausted")
    T.assert_eq(Particles.count(), 2)
end)

suite.test("particles integrate velocity and gravity before they expire", function()
    Particles.reset(1)
    local particle = Particles.emit({ x = 2, y = 3, vx = 4, vy = -2, gravity = 10, lifetime = 1 })
    Particles.update(0.5)
    T.assert_eq(particle.x, 4)
    T.assert_eq(particle.y, 4.5)
    T.assert_eq(particle.vy, 3)
end)

suite.test("card lifecycle retains a dissolving ghost and stays within the particle pool", function()
    local game = bootstrap.new_game(555)
    game.hand = Hand(game)
    Particles.reset(12)
    game.hand:create_card({ rank = 8, suit = "Hearts" })
    game.hand:create_card({ rank = 9, suit = "Clubs" })

    T.assert_true(game.hand:destroy_card_at_index(1, true))
    T.assert_eq(#game.hand.cards, 1, "destroyed card leaves the logical hand immediately")
    T.assert_eq(#game.hand._destroying_nodes, 1, "ghost stays retained for its visual lifetime")
    T.assert_eq(Particles.count(), 8, "one dissolve emits its fixed shard burst")

    -- The hand keeps its nodes in sort order, so take whichever survived rather than
    -- assuming creation order.
    T.assert_true(game.hand:destroy_card_node(game.hand.card_nodes[1], true))
    T.assert_eq(Particles.count(), 12, "a concurrent dissolve sheds excess shards at pool capacity")

    -- The reference's dissolve is 0.7 s (`card.lua:2131`).
    game.hand:update_card_lifecycles(0.69)
    T.assert_eq(#game.hand._destroying_nodes, 2, "ghosts remain visible before 0.7 seconds")
    game.hand:update_card_lifecycles(0.02)
    T.assert_eq(#game.hand._destroying_nodes, 0, "ghosts are removed after the dissolve lifetime")

    -- Shards age on the particle clock, which Game:update drives independently of the
    -- card lifecycle bookkeeping. They live for 0.7 of the dissolve, as in the reference.
    Particles.update(0.5)
    T.assert_eq(Particles.count(), 0, "expired shards return to the bounded pool")
    Particles.reset(96)
end)

--- Particles arrive in bursts that share a colour table and are emitted together, so they
--- also fade in lockstep. Pushing the colour per particle meant crossing into C++ once per
--- particle to write the value that was already there -- 96% of the calls in a saturated
--- pool. The draw must still be pixel-identical, so the colour has to change exactly when
--- the particle's effective colour does, and never be skipped on the first particle.
local function record_colour_sequence()
    local seq = {}
    local original = love.graphics.setColor
    love.graphics.setColor = function(r, g, b, a)
        if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        seq[#seq + 1] = { r or 1, g or 1, b or 1, a or 1 }
        return original(r, g, b, a)
    end
    Particles.draw()
    love.graphics.setColor = original
    -- The trailing reset to white is bookkeeping for later callers, not a particle colour.
    table.remove(seq)
    return seq
end

suite.test("particles sharing a colour push it once", function()
    Particles.reset(8)
    local red = { 1, 0, 0, 1 }
    for _ = 1, 5 do
        Particles.emit({ x = 0, y = 0, lifetime = 1, colour = red, fade = false })
    end
    local seq = record_colour_sequence()
    T.assert_eq(#seq, 1, "five identical particles should set the colour once")
    T.assert_deep_eq(seq[1], { 1, 0, 0, 1 }, "and it should be the right colour")
end)

suite.test("a colour change is still pushed", function()
    Particles.reset(8)
    Particles.emit({ x = 0, y = 0, lifetime = 1, colour = { 1, 0, 0, 1 }, fade = false })
    Particles.emit({ x = 0, y = 0, lifetime = 1, colour = { 1, 0, 0, 1 }, fade = false })
    Particles.emit({ x = 0, y = 0, lifetime = 1, colour = { 0, 0, 1, 1 }, fade = false })
    Particles.emit({ x = 0, y = 0, lifetime = 1, colour = { 0, 0, 1, 1 }, fade = false })
    local seq = record_colour_sequence()
    T.assert_eq(#seq, 2, "two runs of one colour each")
    T.assert_deep_eq(seq[1], { 1, 0, 0, 1 }, "first run")
    T.assert_deep_eq(seq[2], { 0, 0, 1, 1 }, "second run")
end)

--- Same colour table, different ages: the fade makes the effective alpha differ, so the
--- dedup must compare the computed alpha rather than the table identity.
suite.test("fading particles of different ages each push their own alpha", function()
    Particles.reset(8)
    local white = { 1, 1, 1, 1 }
    local a = Particles.emit({ x = 0, y = 0, lifetime = 1, colour = white })
    local b = Particles.emit({ x = 0, y = 0, lifetime = 1, colour = white })
    a.age, b.age = 0.25, 0.75
    local seq = record_colour_sequence()
    T.assert_eq(#seq, 2, "different alphas are different colours")
    T.assert_true(math.abs(seq[1][4] - 0.75) < 1e-6, "first particle alpha")
    T.assert_true(math.abs(seq[2][4] - 0.25) < 1e-6, "second particle alpha")
end)

--- The tracker is per-draw: it must not assume the colour survived from the previous frame,
--- because everything else on the bottom screen sets colours between particle passes.
suite.test("the first particle of a frame always pushes its colour", function()
    Particles.reset(4)
    Particles.emit({ x = 0, y = 0, lifetime = 1, colour = { 0, 1, 0, 1 }, fade = false })
    T.assert_eq(#record_colour_sequence(), 1, "first frame")
    T.assert_eq(#record_colour_sequence(), 1, "second frame re-pushes rather than assuming")
end)

--- The batched path replaces one DrawCommand per particle with a single untextured mesh.
--- It has to put exactly the same quads in the same places, so these compare it against the
--- per-rectangle path rather than trusting it in isolation.
local function capture_rectangles()
    local rects = {}
    local original = love.graphics.rectangle
    love.graphics.rectangle = function(mode, x, y, w, h)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h }
        return original(mode, x, y, w, h)
    end
    Particles.set_batched(false)
    Particles.draw()
    love.graphics.rectangle = original
    return rects
end

--- Pull the drawn quads back out of the mesh as rectangles, so they can be compared with
--- what the per-rectangle path emitted.
local function capture_batched_quads()
    local drawn = {}
    local original = love.graphics.draw
    love.graphics.draw = function(mesh, ...)
        if type(mesh) == "table" and mesh._vertices then
            drawn[#drawn + 1] = mesh
            return
        end
        return original(mesh, ...)
    end
    Particles.set_batched(true)
    Particles.draw()
    love.graphics.draw = original
    Particles.set_batched(false)

    T.assert_eq(#drawn, 1, "the whole pool should be a single draw")
    local verts = drawn[1]._vertices
    local quads = {}
    for i = 1, Particles.count() do
        local o = (i - 1) * 6
        local a, c = verts[o + 1], verts[o + 3]
        quads[#quads + 1] = { x = a[1], y = a[2], w = c[1] - a[1], h = c[2] - a[2],
                              r = a[5], g = a[6], b = a[7], alpha = a[8] }
    end
    return quads
end

local function emit_spread()
    Particles.reset(16)
    for i = 1, 6 do
        Particles.emit({
            x = i * 7, y = i * 3, w = 2 + i, h = 1 + i, lifetime = 1,
            colour = { i / 6, 0.5, 1 - i / 6, 1 }, fade = false,
        })
    end
end

suite.test("the batched draw places the same quads as the per-rectangle draw", function()
    emit_spread()
    local rects = capture_rectangles()
    emit_spread()
    local quads = capture_batched_quads()

    T.assert_eq(#quads, #rects, "same number of quads")
    for i = 1, #rects do
        T.assert_eq(quads[i].x, rects[i].x, "quad " .. i .. " x")
        T.assert_eq(quads[i].y, rects[i].y, "quad " .. i .. " y")
        T.assert_eq(quads[i].w, rects[i].w, "quad " .. i .. " w")
        T.assert_eq(quads[i].h, rects[i].h, "quad " .. i .. " h")
    end
end)

suite.test("the batched draw carries each particle's colour in its vertices", function()
    emit_spread()
    local quads = capture_batched_quads()
    for i = 1, #quads do
        T.assert_true(math.abs(quads[i].r - i / 6) < 1e-6, "quad " .. i .. " red")
        T.assert_true(math.abs(quads[i].b - (1 - i / 6)) < 1e-6, "quad " .. i .. " blue")
        T.assert_eq(quads[i].alpha, 1, "quad " .. i .. " alpha")
    end
end)

--- Mesh vertices persist between frames, so a shrinking pool has to collapse the slots it
--- no longer uses or the mesh keeps drawing last frame's particles. (On a runtime with
--- setDrawRange the range handles it; the stub has none, which is the case exercised here.)
suite.test("a shrinking pool does not leave stale quads in the mesh", function()
    Particles.reset(16)
    local keep = Particles.emit({ x = 1, y = 1, w = 4, h = 4, lifetime = 10, fade = false })
    for _ = 1, 5 do
        Particles.emit({ x = 90, y = 90, w = 9, h = 9, lifetime = 0.1, fade = false })
    end
    Particles.set_batched(true)
    Particles.draw()

    Particles.update(0.2)  -- the five short-lived particles expire
    T.assert_eq(Particles.count(), 1, "one particle left")

    local mesh
    local original = love.graphics.draw
    love.graphics.draw = function(m) mesh = m end
    Particles.draw()
    love.graphics.draw = original
    Particles.set_batched(false)

    T.assert_true(mesh ~= nil, "still drew")
    local verts = mesh._vertices
    T.assert_eq(verts[1][1], keep.x, "the survivor is still quad one")
    for i = 7, 36 do
        T.assert_eq(verts[i][1], 0, "vertex " .. i .. " collapsed to the origin")
        T.assert_eq(verts[i][8], 0, "vertex " .. i .. " alpha zeroed")
    end
end)

suite.test("batching is off unless it is asked for", function()
    local enabled = Particles.batched()
    T.assert_eq(enabled, false, "default off")
end)

--- A runtime without the mesh binding must fall back rather than skip the particles.
suite.test("an unavailable mesh falls back to the per-rectangle draw", function()
    Particles.reset(4)
    Particles.emit({ x = 3, y = 4, w = 2, h = 2, lifetime = 1, fade = false })

    local original_new = love.graphics.newMesh
    love.graphics.newMesh = nil
    Particles.reset(4)  -- drops any mesh built earlier so the probe re-runs
    Particles.emit({ x = 3, y = 4, w = 2, h = 2, lifetime = 1, fade = false })

    local rects = 0
    local original_rect = love.graphics.rectangle
    love.graphics.rectangle = function(...) rects = rects + 1 return original_rect(...) end
    Particles.set_batched(true)
    Particles.draw()
    love.graphics.rectangle = original_rect
    Particles.set_batched(false)
    love.graphics.newMesh = original_new

    T.assert_eq(rects, 1, "the particle was still drawn, the slow way")
end)

return suite


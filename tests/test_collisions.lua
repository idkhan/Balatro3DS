--- Drag collision: the nudge, and the cost of not dragging.
---
--- `Game:check_collisions` runs every frame of every state, and for the overwhelming majority
--- of them nothing is being dragged. It used to walk every node in the scene on each of those
--- frames to clear a flag that the first such frame had already cleared, which is O(nodes) of
--- pure nothing at 60 Hz.
---
--- The rewrite makes that a transition -- one sweep when the finger comes up -- plus a short
--- tail while displaced nodes slide home. The tail is not an optimisation: before it, nothing
--- decayed the offsets once the drag ended, because the decay loop only ever ran inside the
--- dragging branch. A card shoved aside stayed shoved for the rest of the run and the
--- displacement accumulated across drags.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function node(x, y, w, h)
    local n = Moveable(x, y, w or 40, h or 40)
    n.states.collide.can = true
    return n
end

--- A Game with a known node list and its own collision state.
local function scene(count)
    local game = bootstrap.new_game(1)
    game.nodes = {}
    game._collidables_buf = {}
    game._collision_nudged = {}
    game._collision_active = false
    for i = 1, count do
        game.nodes[i] = node((i - 1) * 50, 0)
    end
    return game
end

suite.test("an idle frame touches nothing once the release sweep is done", function()
    local game = scene(6)
    for _, n in ipairs(game.nodes) do n.states.collide.is = true end

    -- The release sweep clears every flag, collidable or not.
    game.dragging = nil
    game:check_collisions(1 / 60)
    -- _collision_active was false to begin with, so nothing was cleared: the sweep only runs
    -- on the transition out of dragging.
    T.assert_true(game.nodes[1].states.collide.is, "no drag happened, so no sweep")

    game.dragging = game.nodes[1]
    game:check_collisions(1 / 60)
    game.dragging = nil
    game:check_collisions(1 / 60)
    for i, n in ipairs(game.nodes) do
        T.assert_false(n.states.collide.is, "node " .. i .. " should be cleared on release")
    end

    -- And a later idle frame must not re-walk the list. Setting a flag by hand and checking it
    -- survives is the observable proof that the loop did not run.
    game.nodes[3].states.collide.is = true
    game:check_collisions(1 / 60)
    T.assert_true(game.nodes[3].states.collide.is,
        "an idle frame after the sweep must not walk the node list")
end)

suite.test("a nudged node slides back to its layout position after release", function()
    local game = scene(2)
    -- Overlapping by 30 px, which is inside the deadzone-to-max window that nudges.
    game.nodes[2].T.x, game.nodes[2].VT.x = 20, 20

    game.dragging = game.nodes[1]
    for _ = 1, 5 do game:check_collisions(1 / 60) end

    local offset = game.nodes[2].collision_offset
    T.assert_true(math.abs(offset.x) > 0.5,
        "the held node should have shoved it aside, got " .. offset.x)

    game.dragging = nil
    for _ = 1, 400 do game:check_collisions(1 / 60) end

    T.assert_eq(offset.x, 0, "and it must come all the way back")
    T.assert_eq(offset.y, 0, "on both axes")
    T.assert_eq(#game._collision_nudged, 0, "and stop being tracked")
end)

suite.test("the nudge list holds each node once, however long the drag runs", function()
    local game = scene(2)
    game.nodes[2].T.x, game.nodes[2].VT.x = 20, 20
    game.dragging = game.nodes[1]
    for _ = 1, 30 do game:check_collisions(1 / 60) end
    T.assert_eq(#game._collision_nudged, 1, "thirty nudged frames, one entry")
end)

--- The overlap arithmetic moved from two allocated rectangles to four scalars. The two must
--- agree exactly, or cards would start being shoved at different moments than before.
suite.test("the scalar bounds describe the same rectangle as the table form", function()
    local n = node(12, 34, 40, 50)
    n.VT.scale = 1.5
    n.collision_offset.x, n.collision_offset.y = 3, -4

    local rect = n:get_collision_rect()
    local x1, y1, x2, y2 = n:get_collision_bounds()

    T.assert_eq(x1, rect.x, "left edge")
    T.assert_eq(y1, rect.y, "top edge")
    T.assert_eq(x2, rect.x + rect.w, "right edge")
    T.assert_eq(y2, rect.y + rect.h, "bottom edge")
end)

suite.test("overlap detection matches the rectangle test it replaced", function()
    local game = bootstrap.new_game(1)
    local a = node(0, 0, 40, 40)

    local cases = {
        { x = 10, y = 0, overlap = true, why = "partly over" },
        { x = 39, y = 39, overlap = true, why = "corner touching" },
        { x = 40, y = 0, overlap = false, why = "edge to edge is not overlap" },
        { x = 0, y = 40, overlap = false, why = "edge to edge vertically" },
        { x = 100, y = 100, overlap = false, why = "well clear" },
        { x = -10, y = -10, overlap = true, why = "overlapping from above left" },
    }

    for _, c in ipairs(cases) do
        local b = node(c.x, c.y, 40, 40)
        local ra, rb = a:get_collision_rect(), b:get_collision_rect()
        local ax1, ay1, ax2, ay2 = a:get_collision_bounds()
        local bx1, by1, bx2, by2 = b:get_collision_bounds()

        local scalar = ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1
        T.assert_eq(scalar, game:rects_overlap(ra, rb), c.why .. ": scalar vs table test")
        T.assert_eq(scalar, c.overlap, c.why .. ": expected result")
    end
end)

--- The idle path has to be independent of the node count or the whole exercise was pointless.
--- Wall-clock timing is too noisy under a test runner to assert on, so what is counted instead
--- is how many nodes the call actually reads: the flag lookup is instrumented through a
--- metatable, and an idle frame must not touch any of them.
suite.test("idle collision cost does not scale with the node count", function()
    local game = scene(40)

    game.dragging = game.nodes[1]
    game:check_collisions(1 / 60)
    game.dragging = nil
    game:check_collisions(1 / 60)
    -- Nothing overlaps in this scene, so nothing was nudged and the tail is empty.
    T.assert_eq(#game._collision_nudged, 0, "no node was displaced")

    local reads = 0
    for _, n in ipairs(game.nodes) do
        local real = n.states
        n.states = setmetatable({}, {
            __index = function(_, key) reads = reads + 1 return real[key] end,
            __newindex = function(_, key, value) reads = reads + 1 real[key] = value end,
        })
    end

    for _ = 1, 10 do game:check_collisions(1 / 60) end
    T.assert_eq(reads, 0, "ten idle frames should read no node state at all")
end)

return suite

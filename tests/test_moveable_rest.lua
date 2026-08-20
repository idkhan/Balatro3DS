--- The settled fast path in `Moveable:update`.
---
--- Most nodes on most frames have nowhere to go, and the movers already early-out for them --
--- but a settled node still made four method calls and around thirty table reads to find that
--- out. On hardware that was a millisecond a frame for fifty resting nodes.
---
--- The risk of a whole-function early-out is that it fires when something DOES have work, and
--- the symptom is an animation that silently stops rather than anything throwing. So the shape
--- of this file is: one test that a genuinely settled node is untouched, and one test per kind
--- of pending work that the node still advances.

local T = require("tests.testlib")
require("tests.bootstrap").load()

local suite = T.suite()

local function settled_node()
    local m = Moveable(40, 60, 20, 30)
    m.VT.x, m.VT.y = m.T.x, m.T.y
    m.VT.r, m.VT.scale = m.T.r, m.T.scale
    m.velocity.x, m.velocity.y, m.velocity.r, m.velocity.scale = 0, 0, 0, 0
    return m
end

--- Everything `Moveable:update` is allowed to touch, flattened so a test can say "none of
--- this moved" without listing it again.
local function snapshot(m)
    return {
        m.VT.x, m.VT.y, m.VT.r, m.VT.scale,
        m.velocity.x, m.velocity.y, m.velocity.r, m.velocity.scale,
        m.juice_scale, m.juice_r, m.juice_off, m:flip_sx(),
    }
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

--- Run `body` with a known real_dt, since `Moveable:update` prefers G.real_dt over its
--- argument and a stale one would make these tests depend on whatever ran before them.
local function with_real_dt(dt, body)
    local previous = G and G.real_dt
    if G then G.real_dt = dt end
    local ok, err = pcall(body)
    if G then G.real_dt = previous end
    if not ok then error(err, 0) end
end

suite.test("a node at rest is left exactly as it was", function()
    with_real_dt(1 / 60, function()
        local m = settled_node()
        local before = snapshot(m)
        for _ = 1, 20 do m:update(1 / 60) end
        T.assert_true(same(before, snapshot(m)), "twenty updates must change nothing")
    end)
end)

--- Each of these is a reason the node is NOT at rest. If the fast path fires on any of them,
--- the corresponding animation stops dead on screen.
local pending = {
    ["a target it has not reached"] = function(m) m.T.x = m.VT.x + 40 end,
    ["a target scale it has not reached"] = function(m) m.T.scale = 1.5 end,
    ["a target rotation it has not reached"] = function(m) m.T.r = 0.4 end,
    ["carried xy velocity"] = function(m) m.velocity.x = 3 end,
    ["carried rotational velocity"] = function(m) m.velocity.r = 0.2 end,
    ["carried scale velocity"] = function(m) m.velocity.scale = 0.2 end,
    ["a running juice"] = function(m) m:juice_up() end,
    ["a running flip"] = function(m) m:start_flip() end,
    ["a finger on it"] = function(m)
        m.states.drag.is = true
        m.drag_velocity.x = 12
    end,
}

for why, arrange in pairs(pending) do
    suite.test("a node with " .. why .. " still advances", function()
        with_real_dt(1 / 60, function()
            local m = settled_node()
            arrange(m)
            local before = snapshot(m)
            m:update(1 / 60)
            T.assert_false(same(before, snapshot(m)),
                "one update should have moved something")
        end)
    end)
end

--- The scale test in the fast path mirrors `move_scale`'s own early-out, which tolerates a
--- residual velocity inside EPS_SCALE rather than requiring exactly zero. Skipping the call in
--- that case is not a behaviour change: `move_scale` would have returned immediately too.
suite.test("a residual scale velocity inside the epsilon is treated as at rest", function()
    with_real_dt(1 / 60, function()
        local m = settled_node()
        m.velocity.scale = 0.0001
        local before = snapshot(m)
        m:update(1 / 60)
        T.assert_true(same(before, snapshot(m)),
            "move_scale would itself have returned without touching anything")
    end)
end)

--- A node that arrives goes quiet, and stays quiet. This is the transition the fast path has
--- to pick up: a card flies in, settles, and from then on costs nothing.
suite.test("a node that arrives settles into the fast path", function()
    with_real_dt(1 / 60, function()
        local m = settled_node()
        m.T.x = m.VT.x + 60
        for _ = 1, 600 do m:update(1 / 60) end

        T.assert_eq(m.VT.x, m.T.x, "it should have arrived exactly")
        T.assert_eq(m.velocity.x, 0, "with no velocity left")

        local before = snapshot(m)
        for _ = 1, 10 do m:update(1 / 60) end
        T.assert_true(same(before, snapshot(m)), "and then stop changing")
    end)
end)

return suite

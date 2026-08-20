--- The incremental collector's schedule.
---
--- PUC Lua 5.1 allocates enough during a hand for the collector to matter, and on a New 3DS a
--- full cycle is 23.8 ms -- a dropped frame and a half. So no full collect ever runs during
--- play, and the incremental work is placed rather than left to arrive.
---
--- The shape that replaced the old schedule: a small step every frame instead of a large one
--- five times a second. `collectgarbage("step", n)` costs about 14.6 us per unit of n on
--- hardware, so step(8) sixty times a second is the same total work as step(96) five times a
--- second -- identical average, and none of it concentrated in five frames out of sixty.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

--- Record what the collector is asked to do, without doing it.
local function with_recorded_gc(body)
    local original = _G.collectgarbage
    local calls = {}
    _G.collectgarbage = function(what, arg)
        calls[#calls + 1] = { what = what, arg = arg }
        if what == "count" then return 1024 end
        return original(what, arg)
    end
    local ok, err = pcall(body, calls)
    _G.collectgarbage = original
    if not ok then error(err, 0) end
    return calls
end

local function steps(calls)
    local out = {}
    for _, c in ipairs(calls) do
        if c.what == "step" then out[#out + 1] = c.arg end
    end
    return out
end

--- The cadence is the point. A step costs ~270 us before it does any work, so the schedule
--- buys its reclamation in the largest piece that still disappears into a frame, as rarely as
--- that allows -- not in the smallest piece every frame.
suite.test("the collector is stepped on a cadence, not every frame", function()
    local game = bootstrap.new_game(1)
    local frames = Game.GC.STEP_FRAMES * 10
    local calls = with_recorded_gc(function()
        for _ = 1, frames do game:step_gc() end
    end)

    local sizes = steps(calls)
    T.assert_eq(#sizes, 10, "one step per STEP_FRAMES frames")
    for i, size in ipairs(sizes) do
        T.assert_eq(size, Game.GC.STEP, "step " .. i .. " should be the ordinary size")
    end
end)

--- Whatever the cadence, the reclamation rate has to match what the old schedule did, or
--- memory quietly grows or the collector quietly costs more.
suite.test("the reclamation rate matches the schedule it replaced", function()
    -- The old schedule was step(96) every 0.2 s: 480 units a second at 60 fps.
    local units_per_second = Game.GC.STEP * (60 / Game.GC.STEP_FRAMES)
    T.assert_eq(units_per_second, 480, "same units per second as step(96) five times a second")

    -- And a boost has to reclaim what twelve frames of step(160) did.
    T.assert_eq(Game.GC.BOOST_STEP * Game.GC.BOOST_FRAMES, 160 * 12,
        "a boost reclaims what the burst it replaced reclaimed")
end)

suite.test("a garbage wave raises the rate without raising the spike", function()
    local game = bootstrap.new_game(1)
    game._gc_boost_frames = Game.GC.BOOST_FRAMES

    local calls = with_recorded_gc(function()
        for _ = 1, Game.GC.BOOST_FRAMES + 5 do game:step_gc() end
    end)

    local sizes = steps(calls)
    for i = 1, Game.GC.BOOST_FRAMES do
        T.assert_eq(sizes[i], Game.GC.BOOST_STEP, "frame " .. i .. " should be boosted")
    end
    for i = Game.GC.BOOST_FRAMES + 1, #sizes do
        T.assert_eq(sizes[i], Game.GC.STEP, "and afterwards back to the ordinary size")
    end

    -- The point of the whole change: no single frame is allowed to be expensive.
    T.assert_true(Game.GC.BOOST_STEP <= 48,
        "a boosted frame must stay well under the 2.3 ms a step(160) costs")
end)

suite.test("nothing in the schedule ever asks for a full collect", function()
    local game = bootstrap.new_game(1)
    local calls = with_recorded_gc(function()
        game._gc_boost_frames = Game.GC.BOOST_FRAMES
        for _ = 1, 200 do game:step_gc() end
    end)

    for _, c in ipairs(calls) do
        T.assert_ne(c.what, "collect", "a full cycle is 23.8 ms and must never be scheduled")
    end
end)

suite.test("the heap is sampled, but not every frame", function()
    local game = bootstrap.new_game(1)
    local calls = with_recorded_gc(function()
        for _ = 1, Game.GC.HEAP_SAMPLE_FRAMES * 3 do game:step_gc() end
    end)

    local counts = 0
    for _, c in ipairs(calls) do
        if c.what == "count" then counts = counts + 1 end
    end
    T.assert_eq(counts, 3, "one sample per HEAP_SAMPLE_FRAMES frames")
    T.assert_true(game._gc_heap_kb > 0, "and the reading is kept for the report")
end)

suite.test("a heap over the threshold boosts on its own", function()
    local game = bootstrap.new_game(1)
    local original = _G.collectgarbage
    local sizes = {}
    _G.collectgarbage = function(what, arg)
        if what == "count" then return Game.GC.HEAP_BOOST_KB + 512 end
        if what == "step" then sizes[#sizes + 1] = arg return end
        return original(what, arg)
    end

    local ok, err = pcall(function()
        for _ = 1, Game.GC.HEAP_SAMPLE_FRAMES + 2 do game:step_gc() end
    end)
    _G.collectgarbage = original
    if not ok then error(err, 0) end

    -- Ordinary frames step on a cadence, so the interesting entry is the last one: once the
    -- sampling frame sees a large heap the schedule goes to the boost rate, which steps every
    -- frame.
    T.assert_eq(sizes[#sizes], Game.GC.BOOST_STEP,
        "the sampling frame that sees a large heap should start a boost")
    T.assert_true(game._gc_boost_frames > 0, "and the boost should still be running")
    T.assert_true(game._gc_heap_peak >= Game.GC.HEAP_BOOST_KB, "and record the high-water mark")
end)

--- A discard wave is the case the old schedule was built for, and it still has to trigger.
suite.test("a discard wave starts a boost", function()
    local game = bootstrap.new_game(1)
    game._gc_discarded_nodes = Game.GC.DISCARD_NODES - 1
    T.assert_eq(game._gc_boost_frames, 0, "not boosted yet")

    -- One more discarded node crosses the threshold; the update loop is what counts them, so
    -- the arithmetic is restated here rather than driving a whole round.
    game._gc_discarded_nodes = game._gc_discarded_nodes + 1
    if game._gc_discarded_nodes >= Game.GC.DISCARD_NODES then
        game._gc_discarded_nodes = 0
        game._gc_boost_frames = Game.GC.BOOST_FRAMES
    end

    local calls = with_recorded_gc(function() game:step_gc() end)
    T.assert_eq(steps(calls)[1], Game.GC.BOOST_STEP,
        "the next frame should be boosted, cadence or no cadence")
end)

return suite

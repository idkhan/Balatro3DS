--- `Game:do_random(min, max, goal)` probability, including the "Oops! All 6s" multiplier.
---
--- These enumerate rather than sample. `do_random` draws exactly one `math.random(min, max)`,
--- so swapping in a generator that yields each face of that range once turns the probability
--- into an exact count -- no seeds, no tolerance band, no flakes.
---
--- The contract under test (from the reference game): base odds are 1-in-(max-min+1) per goal
--- value, and each copy of j_oops doubles the odds, so with k copies the chance is
--- (goal * 2^k) / (max - min + 1), capped at certainty.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local game = bootstrap.new_game(20240101)

--- Give the game exactly `n` copies of a joker id. `count_jokers_with_id` only looks at
--- `j.def.id`, so a bare stub is a faithful stand-in for a real Joker here.
---@param id string
---@param n integer
local function set_jokers(id, n)
    game.jokers = {}
    for _ = 1, n do
        game.jokers[#game.jokers + 1] = { def = { id = id } }
    end
end

--- Count how many of the (max - min + 1) equally likely draws make `do_random` return true.
---
--- Replaces the global `math.random` for the duration. `do_random` calls it once per
--- invocation; the replacement asserts that, so a future implementation that draws twice
--- fails loudly instead of silently skewing this count.
---@param min integer
---@param max integer
---@param goal integer|nil
---@return integer hits
---@return integer outcomes
local function enumerate(min, max, goal)
    local real_random = math.random
    local hits, outcomes = 0, 0
    local draws

    for face = min, max do
        draws = 0
        math.random = function(a, b)
            draws = draws + 1
            -- Guard the assumption this enumeration rests on.
            if a ~= min or b ~= max then
                math.random = real_random
                error(string.format(
                    "do_random drew math.random(%s, %s), expected (%d, %d)",
                    tostring(a), tostring(b), min, max))
            end
            return face
        end

        local ok, res = pcall(game.do_random, game, min, max, goal)
        math.random = real_random
        if not ok then error(res, 0) end

        if draws ~= 1 then
            error(string.format("do_random drew math.random %d times for face %d, expected 1",
                draws, face))
        end

        outcomes = outcomes + 1
        if res == true then
            hits = hits + 1
        elseif res ~= false then
            error("do_random returned a non-boolean: " .. T.repr(res))
        end
    end

    return hits, outcomes
end

--- The probability `do_random(min, max, goal)` returns true, exactly.
---@return number
local function probability(min, max, goal)
    local hits, outcomes = enumerate(min, max, goal)
    return hits / outcomes
end

suite.test("returns a boolean", function()
    set_jokers("j_oops", 0)
    local hits, outcomes = enumerate(1, 5, 1)
    T.assert_eq(outcomes, 5, "expected one outcome per face of a 1-5 draw")
    T.assert_eq(hits, 1, "exactly one face of 1-5 should satisfy goal 1")
end)

suite.test("base odds are 1 in 5 for do_random(1, 5, 1)", function()
    set_jokers("j_oops", 0)
    T.assert_near(probability(1, 5, 1), 1 / 5, 1e-12, "base 1-in-5")
end)

suite.test("one Oops! All 6s doubles the odds to 2 in 5", function()
    set_jokers("j_oops", 1)
    T.assert_near(probability(1, 5, 1), 2 / 5, 1e-12,
        "one j_oops should double 1-in-5 to 2-in-5")
end)

suite.test("two Oops! All 6s quadruple the odds to 4 in 5", function()
    set_jokers("j_oops", 2)
    T.assert_near(probability(1, 5, 1), 4 / 5, 1e-12,
        "two copies should quadruple 1-in-5 to 4-in-5")
end)

suite.test("three Oops! All 6s saturate a 1-in-5 roll at certainty", function()
    set_jokers("j_oops", 3)
    T.assert_eq(probability(1, 5, 1), 1.0,
        "three copies should make an 1-in-5 roll certain")
end)

suite.test("odds saturate at certainty rather than exceeding it", function()
    -- Five copies would nominally be 6-in-5. A probability cannot exceed 1, and more
    -- importantly the call must not start returning false again from an overflow.
    set_jokers("j_oops", 5)
    local p = probability(1, 5, 1)
    T.assert_eq(p, 1.0, "5 copies of j_oops on a 1-in-5 roll should always hit")
end)

suite.test("a 1 in 4 roll doubles to 2 in 4", function()
    set_jokers("j_oops", 0)
    T.assert_near(probability(1, 4, 1), 1 / 4, 1e-12, "base 1-in-4")
    set_jokers("j_oops", 1)
    T.assert_near(probability(1, 4, 1), 2 / 4, 1e-12, "one j_oops on a 1-in-4 roll")
end)

suite.test("one Oops! All 6s doubles the base odds for any goal", function()
    -- The multiplier contract should not depend on `goal`. Every live call site today
    -- passes goal = 1, so a break here is latent rather than shipping, but the two
    -- branches of do_random treat `goal` differently (`== goal` vs `<= goal * n`) and
    -- that divergence only shows up once goal > 1.
    for goal = 1, 3 do
        set_jokers("j_oops", 0)
        local base = probability(1, 12, goal)
        set_jokers("j_oops", 1)
        local doubled = probability(1, 12, goal)
        T.assert_near(doubled, base * 2, 1e-12,
            string.format("goal=%d: one j_oops should double the base odds (base was %s)",
                goal, tostring(base)))
    end
end)

suite.test("goal defaults to 1 when omitted", function()
    set_jokers("j_oops", 0)
    T.assert_near(probability(1, 5, nil), 1 / 5, 1e-12,
        "an omitted goal should behave as goal = 1")
end)

suite.test("an unrelated joker does not change the odds", function()
    set_jokers("j_joker", 3)
    T.assert_near(probability(1, 5, 1), 1 / 5, 1e-12,
        "jokers other than j_oops must not affect the roll")
end)

suite.test("a 0-based range still enumerates cleanly", function()
    -- do_random(0, 4, 1) appears verbatim in game.lua's blind-skip path.
    set_jokers("j_oops", 0)
    T.assert_near(probability(0, 4, 1), 1 / 5, 1e-12, "base odds for do_random(0, 4, 1)")
end)

return suite

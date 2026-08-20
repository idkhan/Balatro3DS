--- The "(Currently ...)" line on a joker tooltip.
---
--- `Joker:get_live_current_tooltip_text` runs from `Joker:draw_tooltip`, so it is on the
--- draw path for every frame a joker tooltip is up. Its dispatch tables used to be built
--- inline -- three table literals and ~37 closures per call, all three built even when the
--- joker matched none of them -- and are now module-scope constants. These tests pin both
--- the text each branch produces and the fact that the lookup no longer allocates.

local T = require("tests.testlib")
local bootstrap = require("tests.bootstrap")

local suite = T.suite()

local function joker_with(id, fields)
    bootstrap.load()
    local def = JOKER_DEFS[id]
    assert(def, "no such joker: " .. tostring(id))
    local j = Joker(0, 0, Joker.SPRITE_W, Joker.SPRITE_H, def)
    for k, v in pairs(fields or {}) do j[k] = v end
    return j
end

suite.test("stored xmult jokers report their running multiplier", function()
    local g = bootstrap.new_game(7)
    g.jokers = {}
    T.assert_eq(joker_with("j_constellation", { stored_xmult = 1.6 }):get_live_current_tooltip_text(""),
        "(Currently X1.6 Mult)", "constellation")
    T.assert_eq(joker_with("j_vampire", { stored_xmult = 2.25 }):get_live_current_tooltip_text(""),
        "(Currently X2.25 Mult)", "vampire")
end)

suite.test("stored mult jokers report their running bonus", function()
    local g = bootstrap.new_game(7)
    g.jokers = {}
    T.assert_eq(joker_with("j_ceremonial", { stored_mult = 14 }):get_live_current_tooltip_text(""),
        "(Currently +14 Mult)", "ceremonial")
    T.assert_eq(joker_with("j_ride_the_bus", { runtime_counter = 9 }):get_live_current_tooltip_text(""),
        "(Currently +9 Mult)", "ride the bus")
end)

suite.test("stored chip jokers report their running bonus", function()
    local g = bootstrap.new_game(7)
    g.jokers = {}
    T.assert_eq(joker_with("j_runner", { stored_chips = 45 }):get_live_current_tooltip_text(""),
        "(Currently +45 Chips)", "runner")
    T.assert_eq(joker_with("j_square", { stored_chips = 32 }):get_live_current_tooltip_text(""),
        "(Currently +32 Chips)", "square")
end)

--- The three tables are consulted in order, so a joker in none of them has to fall through
--- all three to the id chain below -- the case that used to build every table for nothing.
suite.test("a joker in none of the tables falls through to the id chain", function()
    local g = bootstrap.new_game(7)
    g.jokers = {}
    T.assert_eq(joker_with("j_invisible", { runtime_counter = 1 }):get_live_current_tooltip_text(""),
        "(Currently 1/2)", "invisible falls through to its own branch")
end)

suite.test("a joker with no live line is handed back its base text", function()
    local j = joker_with("j_joker", {})
    j.def = {}
    T.assert_eq(j:get_live_current_tooltip_text("base"), "base", "no id means no live line")
end)

--- The point of the refactor. A call that misses every table used to allocate three tables
--- and ~37 closures; one that hits a table still allocated them all up to the hit. Neither
--- should allocate anything now beyond the returned string.
suite.test("the dispatch tables are not rebuilt per call", function()
    local g = bootstrap.new_game(7)
    g.jokers = {}
    local miss = joker_with("j_invisible", { runtime_counter = 1 })

    -- Warm any first-call laziness, then measure a long run of table-miss lookups.
    for _ = 1, 50 do miss:get_live_current_tooltip_text("") end
    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 500 do miss:get_live_current_tooltip_text("") end
    local growth_kb = collectgarbage("count") - before

    -- 500 calls each rebuilding three tables and ~37 closures ran to hundreds of KB. The
    -- returned string still allocates, so this is a ceiling, not a claim of zero.
    T.assert_eq(growth_kb < 100, true,
        string.format("500 lookups grew the heap by %.1f KB; the tables are being rebuilt", growth_kb))
end)

return suite
